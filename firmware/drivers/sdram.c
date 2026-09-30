/*
 * Driver — OMAP3530 SDRAM Controller (SDRC)
 * Micron MT48H32M16LF-7: 256Mb × 16, mobile SDRAM, 7ns CL3
 * 266 MHz DDR clock → 133 MHz SDR → tCK = 7.5ns
 *
 * OMAP3530 SDRC timing values are in SDR clock cycles.
 */

#include "sdram.h"

/* Timing constants for MT48H32M16LF-7 at 133 MHz SDR */
#define SDRC_T_RFC   22     /* Refresh-to-Active: 66ns / 7.5ns = ~9, use 22 for margin */
#define SDRC_T_RP    2      /* Precharge-to-Active: 15ns / 7.5ns = 2 */
#define SDRC_T_RCD   3      /* Active-to-Read/Write: 18ns / 7.5ns = ~2.4, round up */
#define SDRC_T_RAS   5      /* Active-to-Precharge: 42ns / 7.5ns = ~5.6, round up */
#define SDRC_T_RC    7      /* Active-to-Active: 60ns / 7.5ns = ~8, round down w/margin */
#define SDRC_T_WR    2      /* Write recovery: 2 cycles */
#define SDRC_T_RAS_MAX 9    /* Max RAS: 9 cycles */
#define SDRC_T_XSR   22     /* Exit self-refresh: same as tRFC */

int sdram_init(void) {
    hw_reg32_t sdrc = (hw_reg32_t)SDRC_BASE;

    /* 1. Configure SDRC module (smart idle, auto-wakeup) */
    reg_write32(sdrc + SDRC_SYSCONFIG, 0x00000010);
    delay_cycles(500);

    /* 2. Configure chip-select mapping — CS0 maps to 0x30000000 */
    reg_write32(sdrc + SDRC_CS_CFG, 0x00000030);  /* CS0: 256MB at 0x30000000 */

    /* 3. Configure sharing — all bandwidth to CS0 */
    reg_write32(sdrc + SDRC_SHARING, 0x00000000);

    /* 4. Configure CS0 — Mobile SDRAM, 16-bit, 4 banks, 8K rows × 512 cols */
    reg32_t mcfg = 0;
    mcfg |= SDRC_MCFG_MEMTYPE_DDR;     /* DDR/Mobile SDRAM */
    mcfg |= (0x01 << 8);                /* 4 banks */
    mcfg |= (0x03 << 4);                /* 8K row address */
    mcfg |= (0x00 << 0);                /* 512 column address (9-bit for 16-bit bus) */
    reg_write32(sdrc + SDRC_MCFG_0, mcfg);

    /* 5. Timing registers — ACTIM_CTRLA and ACTIM_CTRLB */
    reg32_t actima = 0;
    actima |= (SDRC_T_RFC  << 24);      /* tRFC */
    actima |= (SDRC_T_XSR  << 16);      /* tXSR */
    actima |= (SDRC_T_RP   << 8);       /* tRP */
    actima |= (SDRC_T_RCD  << 0);       /* tRCD */
    reg_write32(sdrc + SDRC_ACTIM_CTRLA_0, actima);

    reg32_t actimb = 0;
    actimb |= (SDRC_T_RAS << 24);       /* tRAS */
    actimb |= (SDRC_T_RC  << 16);       /* tRC */
    actimb |= (SDRC_T_WR  << 8);        /* tWR */
    actimb |= (SDRC_T_RAS_MAX << 0);    /* tRAS max */
    reg_write32(sdrc + SDRC_ACTIM_CTRLB_0, actimb);

    /* 6. Refresh rate — 7.8µs for 8K rows at 133MHz: 1040 cycles */
    reg32_t rfr = (1040 << 8) | 0x01;   /* Enabled, 1040 cycles */
    reg_write32(sdrc + SDRC_RFR_CTRL_0, rfr);

    /* 7. Issue NOP command to SDRAM */
    reg_write32(sdrc + SDRC_MR_0, SDRC_MR_CMD_NOP << 0);
    delay_cycles(5000);

    /* 8. Issue PRECHARGE-ALL command */
    reg_write32(sdrc + SDRC_MR_0, SDRC_MR_CMD_PRC << 0);
    delay_cycles(5000);

    /* 9. Issue AUTO-REFRESH (2x) */
    reg_write32(sdrc + SDRC_MR_0, SDRC_MR_CMD_REF << 0);
    delay_cycles(5000);
    reg_write32(sdrc + SDRC_MR_0, SDRC_MR_CMD_REF << 0);
    delay_cycles(5000);

    /* 10. Issue MRS (Mode Register Set) — CAS latency 3, burst length 4, sequential */
    reg32_t mrs_val = (SDRC_MR_CMD_MRS << 0) | (0x03 << 4) | (0x02 << 8);
    reg_write32(sdrc + SDRC_MR_0, mrs_val);
    delay_cycles(5000);

    /* 11. Configure for normal operation */
    reg_write32(sdrc + SDRC_MR_0, 0x00);
    delay_cycles(500);

    return 0;
}

int sdram_test(void) {
    volatile uint32_t *dram = (volatile uint32_t *)DRAM_BOOT_BASE;
    const uint32_t pattern = 0xCAFEBABEUL;

    /* Write test pattern */
    dram[0] = pattern;
    dram[1] = ~pattern;
    __asm__ volatile("dmb" ::: "memory");

    /* Read back and verify */
    if (dram[0] != pattern || dram[1] != ~pattern)
        return -1;

    /* Walking-1s test on first 64 words */
    for (int i = 0; i < 64; i++) {
        dram[i] = (1UL << (i % 32));
    }
    __asm__ volatile("dmb" ::: "memory");

    for (int i = 0; i < 64; i++) {
        if (dram[i] != (1UL << (i % 32)))
            return -1;
    }

    return 0;
}
