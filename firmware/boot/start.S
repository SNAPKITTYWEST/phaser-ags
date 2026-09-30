/*
 * ARM Cortex-A8 (OMAP3530) Low-Level Startup
 * Runs from SRAM before any C code — modeled on SH7734 lowlevel_init.S
 *
 * Responsibilities:
 *   1. CPU mode + FPU + endianness (CP15)
 *   2. Disable WDT2
 *   3. Invalidate caches + TLB
 *   4. Configure DPLL1 (MPU 600MHz) and DPLL3 (CORE)
 *   5. Enable peripheral clocks (UART, GPIO, GPTIMER, GPMC, SDRC)
 *   6. Initialize SDRC (JEDEC DDR sequence with wait timers)
 *   7. Set up stack, zero BSS
 *   8. Jump to C entry (reset_handler)
 */

#include "platform_offsets.h"

    .text
    .arm
    .align 2

    .global _start
    .global lowlevel_init

/* ================================================================
 *  Exception Vector Table — placed at 0xFFF00000 or 0x00000000
 * ================================================================ */

_start:
    b   reset_entry           /* 0x00 Reset            */
    b   undef_handler         /* 0x04 Undefined instr  */
    b   svc_handler           /* 0x08 SVC              */
    b   prefetch_handler      /* 0x0C Prefetch abort   */
    b   data_handler          /* 0x10 Data abort       */
    nop                       /* 0x14 Reserved         */
    b   irq_handler           /* 0x18 IRQ              */
    b   fiq_handler           /* 0x1C FIQ              */

undef_handler:
svc_handler:
prefetch_handler:
data_handler:
fiq_handler:
    b   .

irq_handler:
    sub lr, lr, #4
    stmfd sp!, {r0-r12, lr}
    bl  intc_handle_irq
    ldmfd sp!, {r0-r12, pc}^

/* ================================================================
 *  RESET ENTRY — first code executed
 * ================================================================ */

reset_entry:
    /* ---- 1. Enter SVC mode, disable IRQ/FIQ ---- */
    mrs r0, cpsr
    bic r0, r0, #0x1F         /* Clear mode bits */
    orr r0, r0, #0xD3         /* SVC mode + IRQ/FIQ disabled */
    msr cpsr, r0

    /* ---- 2. Disable WDT2 (OMAP3530 WDT2 at 0x48314000) ---- */
    ldr r1, =WDT2_WSPR
    ldr r2, =0x0000AAAA
    str r2, [r1]
    ldr r2, =0x00005555
    str r2, [r1]

    /* ---- 3. Invalidate caches and TLB ---- */
    mov r0, #0
    mcr p15, 0, r0, c7, c5, 0    /* Invalidate I-cache */
    mcr p15, 0, r0, c7, c6, 0    /* Invalidate D-cache */
    mcr p15, 0, r0, c8, c7, 0    /* Invalidate entire TLB */

    /* Disable caches + MMU for clean state */
    mrc p15, 0, r0, c1, c0, 0
    bic r0, r0, #(1 << 0)        /* MMU off */
    bic r0, r0, #(1 << 2)        /* D-cache off */
    bic r0, r0, #(1 << 12)       /* I-cache off */
    bic r0, r0, #(1 << 11)       /* Branch prediction off */
    mcr p15, 0, r0, c1, c0, 0

    dsb
    isb

    /* ---- 4. Set VBAR (vector base) to current location ---- */
    ldr r0, =_start
    mcr p15, 0, r0, c12, c0, 0   /* VBAR = _start */

    /* ---- 5. Enable NEON/VFP ---- */
    mrc p15, 0, r0, c1, c0, 2    /* CPACR */
    orr r0, r0, #(0xF << 20)     /* CP10 + CP11 full access */
    mcr p15, 0, r0, c1, c0, 2
    isb
    mov r0, #0x40000000           /* FPEXC.EN = 1 */
    vmsr FPEXC, r0

    /* ---- 6. Jump to lowlevel_init ---- */
    bl  lowlevel_init

    /* ---- 7. Set up stack and jump to C ---- */
    ldr sp, =STACK_BASE_VAL
    bl  bss_zero
    bl  reset_handler

    b   .    /* Should never reach here */

/* ================================================================
 *  LOWLEVEL INIT — OMAP3530 DPLL + Clock + SDRC
 *  Modeled on SH7734 lowlevel_init: WDT → MMU → FRQCR → CS → DBSC
 * ================================================================ */

lowlevel_init:
    /* ---- A. Wait for power sequencing (50ms from power-tree.json) ---- */
    ldr r0, =POWER_SEQ_DELAY
    bl  wait_cycles

    /* ---- B. Configure DPLL1 (MPU) — 600MHz from 26MHz ref ---- */
    /* Read current DPLL1 state from CM_CLKSEL1_PLL_MPU */
    ldr r1, =CM_CLKSEL1_PLL_MPU
    ldr r0, [r1]

    /* Check if DPLL1 is already at target (M=23, N=1) */
    ldr r2, =DPLL1_MPU_TARGET
    cmp r0, r2
    beq dpll1_done

    /* DPLL1 not at target — reconfigure */
    /* Step 1: Put DPLL1 in bypass (low-power stop) */
    ldr r1, =CM_CLKEN_PLL_MPU
    ldr r0, [r1]
    bic r0, r0, #0x07            /* Clear DPLL_EN bits */
    orr r0, r0, #0x04            /* DPLL_EN = MN bypass */
    str r0, [r1]

    /* Wait for DPLL to enter bypass */
    ldr r0, =DPLL_LOCK_DELAY
    bl  wait_cycles

    /* Step 2: Set M and N dividers */
    ldr r1, =CM_CLKSEL1_PLL_MPU
    ldr r2, =DPLL1_MPU_TARGET
    str r2, [r1]

    /* Step 3: Re-lock DPLL1 */
    ldr r1, =CM_CLKEN_PLL_MPU
    ldr r0, [r1]
    bic r0, r0, #0x07
    orr r0, r0, #0x07            /* DPLL_EN = lock mode */
    str r0, [r1]

    /* Wait for DPLL1 lock (typically <100µs) */
    ldr r1, =CM_IDLEST_PLL_MPU
dpll1_lock_wait:
    ldr r0, [r1]
    ands r0, r0, #0x01           /* Check ST_MPU_CLK bit */
    bne dpll1_lock_wait           /* 0 = locked, keep polling */

dpll1_done:

    /* ---- C. Configure DPLL3 (CORE) — leave at ROM default for now ---- */
    /* DPLL3 drives L3 interconnect. ROM typically sets 166MHz L3. */
    /* For bring-up, we accept ROM defaults. */

    /* ---- D. Configure DPLL5 (DDR) — 266MHz ---- */
    ldr r1, =CM_CLKSEL2_PLL
    ldr r0, [r1]
    ldr r2, =DPLL5_DDR_TARGET
    cmp r0, r2
    beq dpll5_done

    /* Bypass DPLL5 */
    ldr r1, =CM_CLKEN_PLL
    ldr r0, [r1]
    bic r0, r0, #(0x07 << 8)
    orr r0, r0, #(0x04 << 8)
    str r0, [r1]
    ldr r0, =DPLL_LOCK_DELAY
    bl  wait_cycles

    /* Set DPLL5 M/N */
    ldr r1, =CM_CLKSEL2_PLL
    ldr r2, =DPLL5_DDR_TARGET
    str r2, [r1]

    /* Lock DPLL5 */
    ldr r1, =CM_CLKEN_PLL
    ldr r0, [r1]
    bic r0, r0, #(0x07 << 8)
    orr r0, r0, #(0x07 << 8)
    str r0, [r1]

    /* Wait for lock */
    ldr r1, =CM_IDLEST_CORE
dpll5_lock_wait:
    ldr r0, [r1]
    ands r0, r0, #0x02
    bne dpll5_lock_wait

dpll5_done:

    /* ---- E. Enable peripheral clocks ---- */
    ldr r1, =CM_FCLKEN1_CORE_VAL
    ldr r0, [r1]
    ldr r1, =CM_FCLKEN1_CORE
    str r0, [r1]

    ldr r1, =CM_ICLKEN1_CORE_VAL
    ldr r0, [r1]
    ldr r1, =CM_ICLKEN1_CORE
    str r0, [r1]

    ldr r1, =CM_FCLKEN_WKUP_VAL
    ldr r0, [r1]
    ldr r1, =CM_FCLKEN_WKUP
    str r0, [r1]

    ldr r1, =CM_ICLKEN_WKUP_VAL
    ldr r0, [r1]
    ldr r1, =CM_ICLKEN_WKUP
    str r0, [r1]

    /* Wait for clocks to become active */
    ldr r0, =CLOCK_SETTLE_DELAY
    bl  wait_cycles

    /* ---- F. Initialize SDRC — JEDEC DDR init sequence ---- */
    /* Modeled on SH7734 DBSC3 init: power pad → NOP → PRECHARGE →
       REFRESH ×2 → MRS → EMRS → normal, with wait timers */
    bl  sdrc_init_asm

    /* ---- G. Initialize GPMC for NOR/NAND ---- */
    bl  gpmc_init_asm

    /* ---- H. Return to caller ---- */
    bx  lr

/* ================================================================
 *  SDRC INIT — Assembly-level JEDEC DDR sequence
 *  OMAP3530 SDRC for MT48H32M16LF-7 (mobile SDR SDRAM)
 *  Mirrors SH7734 DBSC3 pattern: pad power → NOP → PRC → REF → MRS
 * ================================================================ */

sdrc_init_asm:
    /* Enable SDRC interface clock (should be on, but be safe) */
    ldr r1, =SDRC_SYSCONFIG
    ldr r0, =0x00000010         /* Smart idle, auto-wakeup */
    str r0, [r1]
    ldr r0, =WAIT_50US
    bl  wait_cycles

    /* CS0 mapping: 256MB at 0x30000000 */
    ldr r1, =SDRC_CS_CFG_REG
    ldr r0, =0x00000030
    str r0, [r1]

    /* SDRC sharing */
    ldr r1, =SDRC_SHARING_REG
    ldr r0, =0x00000000
    str r0, [r1]

    /* MCFG0: Mobile SDRAM, 4 banks, 8K rows */
    ldr r1, =SDRC_MCFG_0_REG
    ldr r0, =SDRC_MCFG_0_VAL
    str r0, [r1]

    /* ACTIM_CTRLA0: tRFC=22, tXSR=22, tRP=2, tRCD=3 */
    ldr r1, =SDRC_ACTIM_CTRLA_0_REG
    ldr r0, =SDRC_ACTIM_CTRLA_0_VAL
    str r0, [r1]

    /* ACTIM_CTRLB0: tRAS=5, tRC=7, tWR=2, tRASMAX=9 */
    ldr r1, =SDRC_ACTIM_CTRLB_0_REG
    ldr r0, =SDRC_ACTIM_CTRLB_0_VAL
    str r0, [r1]

    /* RFR_CTRL0: Refresh rate — 7.8µs @ 133MHz = 1040 cycles */
    ldr r1, =SDRC_RFR_CTRL_0_REG
    ldr r0, =SDRC_RFR_CTRL_0_VAL
    str r0, [r1]

    /* ---- JEDEC Init Sequence (mirrors SH7734 DBPDCNT sequence) ---- */

    /* Step 1: NOP command (DBPDCNT3_D equivalent — first pad power-on) */
    ldr r1, =SDRC_MR_0_REG
    ldr r0, =0x00000000          /* CMD = NOP */
    str r0, [r1]
    ldr r0, =WAIT_200US          /* 200µs — matches SH7734 WAIT_200US_400 */
    bl  wait_cycles

    /* Step 2: PRECHARGE-ALL */
    ldr r1, =SDRC_MR_0_REG
    ldr r0, =0x00000001          /* CMD = PRC */
    str r0, [r1]
    ldr r0, =WAIT_100US
    bl  wait_cycles

    /* Step 3: AUTO-REFRESH #1 (SH7734 does 2× DBCMD_D1) */
    ldr r1, =SDRC_MR_0_REG
    ldr r0, =0x00000004          /* CMD = REF */
    str r0, [r1]
    ldr r0, =WAIT_32MCLK         /* Wait 32 MCLK cycles */
    bl  wait_cycles

    /* Step 4: AUTO-REFRESH #2 */
    ldr r1, =SDRC_MR_0_REG
    ldr r0, =0x00000004          /* CMD = REF */
    str r0, [r1]
    ldr r0, =WAIT_32MCLK
    bl  wait_cycles

    /* Step 5: MRS — CAS latency 3, burst length 4, sequential */
    ldr r1, =SDRC_MR_0_REG
    ldr r0, =SDRC_MRS_VAL        /* CMD=MRS | CL=3 | BL=4 | Sequential */
    str r0, [r1]
    ldr r0, =WAIT_16MCLK
    bl  wait_cycles

    /* Step 6: EMRS — extended mode (drive strength, ODT if DDR2) */
    ldr r1, =SDRC_MR_0_REG
    ldr r0, =0x00000002          /* CMD = EMRS */
    str r0, [r1]
    ldr r0, =WAIT_16MCLK
    bl  wait_cycles

    /* Step 7: Normal operation */
    ldr r1, =SDRC_MR_0_REG
    ldr r0, =0x00000000
    str r0, [r1]

    /* Dummy read from SDRAM (like SH7734 synco + mov.l @r1, r0) */
    ldr r1, =SDRAM_BASE_ADDR
    ldr r0, [r1]
    dsb

    ldr r0, =WAIT_10KMCLK        /* Settle — matches SH7734 WAIT_10KMCLK */
    bl  wait_cycles

    bx  lr

/* ================================================================
 *  GPMC INIT — minimal NOR + NAND setup (SH7734 CS0CTRL/CSWCR)
 * ================================================================ */

gpmc_init_asm:
    /* Enable GPMC functional clock (should be on) */
    /* GPMC SYSCONFIG: smart idle */
    ldr r1, =GPMC_SYSCONFIG_REG
    ldr r0, =0x00000010
    str r0, [r1]
    ldr r0, =WAIT_50US
    bl  wait_cycles

    /* GPMC TIMEOUT: 16× timeout, enable */
    ldr r1, =GPMC_TIMEOUT_CTRL_REG
    ldr r0, =0x00010011
    str r0, [r1]

    /* CS0: NOR Flash 16-bit async at 0x08000000 */
    ldr r1, =GPMC_CONFIG1_0_REG
    ldr r0, =NOR_GPMC_CONFIG1
    str r0, [r1]

    ldr r1, =GPMC_CONFIG2_0_REG
    ldr r0, =NOR_GPMC_CONFIG2
    str r0, [r1]

    ldr r1, =GPMC_CONFIG3_0_REG
    ldr r0, =NOR_GPMC_CONFIG3
    str r0, [r1]

    ldr r1, =GPMC_CONFIG4_0_REG
    ldr r0, =NOR_GPMC_CONFIG4
    str r0, [r1]

    ldr r1, =GPMC_CONFIG5_0_REG
    ldr r0, =NOR_GPMC_CONFIG5
    str r0, [r1]

    ldr r1, =GPMC_CONFIG6_0_REG
    ldr r0, =NOR_GPMC_CONFIG6
    str r0, [r1]

    /* CS0 base address + enable */
    ldr r1, =GPMC_CONFIG7_0_REG
    ldr r0, =NOR_GPMC_CONFIG7
    str r0, [r1]

    /* CS1: NAND Flash 8-bit at 0x40000000 */
    ldr r1, =GPMC_CONFIG1_1_REG
    ldr r0, =NAND_GPMC_CONFIG1
    str r0, [r1]

    ldr r1, =GPMC_CONFIG7_1_REG
    ldr r0, =NAND_GPMC_CONFIG7
    str r0, [r1]

    /* Reset NAND device */
    ldr r1, =GPMC_NAND_CMD_1
    ldr r0, =0xFF                /* NAND_CMD_RESET */
    strb r0, [r1]
    ldr r0, =WAIT_200US
    bl  wait_cycles

    bx  lr

/* ================================================================
 *  BSS ZERO — clear .bss section
 * ================================================================ */

bss_zero:
    ldr r0, =__bss_start
    ldr r1, =__bss_end
    mov r2, #0
bss_loop:
    cmp r0, r1
    bge bss_done
    str r2, [r0], #4
    b   bss_loop
bss_done:
    bx  lr

/* ================================================================
 *  WAIT CYCLES — simple busy loop (SH7734 wait_timer pattern)
 * ================================================================ */

wait_cycles:
    subs r0, r0, #1
    bne wait_cycles
    bx  lr

/* ================================================================
 *  LITERAL POOL — all constant addresses and values
 * ================================================================ */

    .align 2

/* ---- OMAP3530 PRCM (Power/Reset/Clock Management) ---- */
CM_CLKEN_PLL_MPU:       .long 0x48004900
CM_IDLEST_PLL_MPU:      .long 0x48004920
CM_CLKSEL1_PLL_MPU:     .long 0x48004940
DPLL1_MPU_TARGET:       .long 0x00170001   /* M=23, N=1 → 598MHz */

CM_CLKEN_PLL:           .long 0x48004D00
CM_IDLEST_CORE:         .long 0x48004A20
CM_CLKSEL2_PLL:         .long 0x48004D44
DPLL5_DDR_TARGET:       .long 0x000A0001   /* M=10, N=1 → 260MHz */

/* ---- Clock enable values ---- */
CM_FCLKEN1_CORE:        .long 0x48004A00
CM_FCLKEN1_CORE_VAL:    .long 0x04060026   /* EN_UART1|EN_UART2|EN_GPMC|EN_HSMMC1 */
CM_ICLKEN1_CORE:        .long 0x48004A10
CM_ICLKEN1_CORE_VAL:    .long 0x04068026   /* Interface clocks */

CM_FCLKEN_WKUP:         .long 0x48004C00
CM_FCLKEN_WKUP_VAL:     .long 0x00000014   /* EN_GPIO1 | EN_GPT1 */
CM_ICLKEN_WKUP:         .long 0x48004C10
CM_ICLKEN_WKUP_VAL:     .long 0x00000014

/* ---- WDT2 ---- */
WDT2_WSPR:              .long 0x48314048

/* ---- SDRC registers ---- */
SDRC_SYSCONFIG:         .long 0x6D000010
SDRC_CS_CFG_REG:        .long 0x6D000040
SDRC_SHARING_REG:       .long 0x6D000044
SDRC_MCFG_0_REG:        .long 0x6D000080
SDRC_MR_0_REG:          .long 0x6D000084
SDRC_ACTIM_CTRLA_0_REG: .long 0x6D00009C
SDRC_ACTIM_CTRLB_0_REG: .long 0x6D0000A0
SDRC_RFR_CTRL_0_REG:    .long 0x6D0000A4

SDRC_MCFG_0_VAL:        .long 0x02584011   /* DDR, 4 banks, 8K rows, 512 cols */
SDRC_ACTIM_CTRLA_0_VAL: .long 0x16A00902   /* tRFC=22, tXSR=22, tRP=2, tRCD=3 */
SDRC_ACTIM_CTRLB_0_VAL: .long 0x50290705   /* tRAS=5, tRC=7, tWR=2, tRASMAX=9 */
SDRC_RFR_CTRL_0_VAL:    .long 0x00041001   /* 1040 cycles, enabled */
SDRC_MRS_VAL:           .long 0x00000033   /* CMD=MRS, CL=3, BL=4, sequential */

SDRAM_BASE_ADDR:        .long 0x30000000

/* ---- GPMC registers ---- */
GPMC_SYSCONFIG_REG:     .long 0x6E000010
GPMC_TIMEOUT_CTRL_REG:  .long 0x6E000040
GPMC_CONFIG1_0_REG:     .long 0x6E000060
GPMC_CONFIG2_0_REG:     .long 0x6E000064
GPMC_CONFIG3_0_REG:     .long 0x6E000068
GPMC_CONFIG4_0_REG:     .long 0x6E00006C
GPMC_CONFIG5_0_REG:     .long 0x6E000070
GPMC_CONFIG6_0_REG:     .long 0x6E000074
GPMC_CONFIG7_0_REG:     .long 0x6E000078
GPMC_CONFIG1_1_REG:     .long 0x6E000090
GPMC_CONFIG7_1_REG:     .long 0x6E0000A8
GPMC_NAND_CMD_1:        .long 0x6E0001D0

/* NOR Flash GPMC config (CS0: 16-bit async) */
NOR_GPMC_CONFIG1:       .long 0x00001200   /* 16-bit, NOR async */
NOR_GPMC_CONFIG2:       .long 0x001F1F08   /* CS on/off timing */
NOR_GPMC_CONFIG3:       .long 0x00060602   /* ADV on/off */
NOR_GPMC_CONFIG4:       .long 0x0C0C0303   /* OE/WE on/off */
NOR_GPMC_CONFIG5:       .long 0x02020202   /* RD/WR cycle/access */
NOR_GPMC_CONFIG6:       .long 0x00020200   /* WrDataMux, wr access */
NOR_GPMC_CONFIG7:       .long 0x00000F4E   /* Base=0x08, mask=0xF, CSVALID */

/* NAND Flash GPMC config (CS1: 8-bit NAND) */
NAND_GPMC_CONFIG1:      .long 0x00000800   /* 8-bit, NAND */
NAND_GPMC_CONFIG7:      .long 0x00000FCE   /* Base=0x40, mask=0xF, CSVALID */

/* ---- Wait timer values (SH7734 pattern) ---- */
POWER_SEQ_DELAY:        .long 30000000     /* ~50ms at 600MHz */
DPLL_LOCK_DELAY:        .long 300000       /* ~0.5ms at 600MHz */
CLOCK_SETTLE_DELAY:     .long 300000       /* ~0.5ms */

WAIT_200US:             .long 120000       /* 200µs at 600MHz */
WAIT_100US:             .long 60000        /* 100µs at 600MHz */
WAIT_50US:              .long 30000
WAIT_32MCLK:            .long 19200        /* 32 MCLK cycles at 133MHz → 240ns → ~144k CPU cycles */
WAIT_16MCLK:            .long 9600
WAIT_10KMCLK:           .long 6000000      /* 10000 MCLK at 133MHz ≈ 75µs → ~45000 CPU cycles; pad to 10ms */
WAIT_1MCLK:             .long 600

/* ---- Stack ---- */
STACK_BASE_VAL:         .long 0x20010000

/* ---- Linker symbols ---- */
    .extern __bss_start
    .extern __bss_end
