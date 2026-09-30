/*
 * Platform definitions — OMAP3530 memory-mapped peripherals
 * Derived from device-tree.dts and memory-map.json
 */

#ifndef FIRMWARE_COMMON_PLATFORM_H
#define FIRMWARE_COMMON_PLATFORM_H

/* ---- Memory regions (from memory-map.json) ---- */

#define RESET_VECTOR_BASE  0xFFF00000UL
#define SRAM_BASE          0x00000000UL
#define SRAM_SIZE          0x00020000UL   /* 128 KB */
#define DRAM_BOOT_BASE     0x30000000UL
#define DRAM_BOOT_SIZE     0x00040000UL   /* 256 KB */
#define DRAM_KERNEL_BASE   0x30040000UL
#define DRAM_KERNEL_SIZE   0x00400000UL   /* 4 MB */
#define NOR_FLASH_BASE     0x08000000UL
#define NOR_FLASH_SIZE     0x10000000UL   /* 256 MB */
#define NAND_FLASH_BASE    0x40000000UL
#define NAND_FLASH_SIZE    0x20000000UL   /* 512 MB */

/* ---- Stack / Heap (from linker scripts) ---- */

#define STACK_BASE         0x20010000UL
#define STACK_SIZE         0x00004000UL   /* 16 KB */
#define HEAP_BASE          0x20014000UL
#define HEAP_SIZE          0x00008000UL   /* 32 KB */

/* ---- OMAP3530 Peripheral Base Addresses (from device-tree) ---- */

#define OMAP_L4_CORE_BASE 0x48000000UL

#define UART0_BASE         0x4806A000UL
#define UART1_BASE         0x4806C000UL

#define GPIO1_BASE         0x48310000UL
#define GPIO2_BASE         0x49050000UL
#define GPIO3_BASE         0x49052000UL
#define GPIO4_BASE         0x49054000UL
#define GPIO5_BASE         0x49056000UL
#define GPIO6_BASE         0x49058000UL

#define INTC_BASE          0x48200000UL

#define GPTIMER1_BASE      0x48318000UL
#define GPTIMER2_BASE      0x49032000UL
#define GPTIMER3_BASE      0x49034000UL
#define GPTIMER4_BASE      0x49036000UL
#define GPTIMER5_BASE      0x49038000UL
#define GPTIMER6_BASE      0x4903A000UL
#define GPTIMER7_BASE      0x4903C000UL
#define GPTIMER8_BASE      0x4903E000UL
#define GPTIMER9_BASE      0x49040000UL
#define GPTIMER10_BASE     0x48086000UL
#define GPTIMER11_BASE     0x48088000UL

#define SCM_BASE           0x48002000UL
#define CM_BASE            0x48004000UL
#define PRM_BASE           0x48306000UL

/* ---- Clock frequencies (from clock-tree.json) ---- */

#define REF_CLK_HZ         26000000UL   /* 26 MHz */
#define CPU_CLK_HZ         600000000UL  /* 600 MHz */
#define DDR_CLK_HZ         266000000UL  /* 266 MHz */

/* ---- OMAP3530 UART register offsets (NS16550A compatible) ---- */

#define UART_THR           0x00   /* Transmit Holding (write) */
#define UART_RBR           0x00   /* Receive Buffer (read) */
#define UART_IER           0x04   /* Interrupt Enable */
#define UART_IIR           0x08   /* Interrupt ID (read) */
#define UART_FCR           0x08   /* FIFO Control (write) */
#define UART_LCR           0x0C   /* Line Control */
#define UART_MCR           0x10   /* Modem Control */
#define UART_LSR           0x14   /* Line Status */
#define UART_MSR           0x18   /* Modem Status */
#define UART_SCR           0x1C   /* Scratch */
#define UART_MDR1          0x20   /* Mode Definition (OMAP-specific) */
#define UART_DLL           0x00   /* Divisor Latch Low (LCR.DLAB=1) */
#define UART_DLH           0x04   /* Divisor Latch High (LCR.DLAB=1) */

/* UART LSR bits */
#define UART_LSR_DR        0x01   /* Data Ready */
#define UART_LSR_THRE      0x20   /* TX Holding Register Empty */
#define UART_LSR_TEMT      0x40   /* Transmitter Empty */

/* UART FCR bits */
#define UART_FCR_FIFO_EN   0x01   /* Enable FIFOs */
#define UART_FCR_RXSR      0x02   /* Reset RX FIFO */
#define UART_FCR_TXSR      0x04   /* Reset TX FIFO */

/* UART LCR bits */
#define UART_LCR_DLAB      0x80   /* Divisor Latch Access */
#define UART_LCR_8N1       0x03   /* 8 data, no parity, 1 stop */

/* ---- OMAP3530 GPIO register offsets ---- */

#define GPIO_REVISION      0x000
#define GPIO_SYSCONFIG     0x010
#define GPIO_SYSSTATUS     0x014
#define GPIO_IRQSTATUS1    0x018
#define GPIO_IRQENABLE1    0x01C
#define GPIO_CTRL          0x030
#define GPIO_OE            0x034   /* Output Enable (0=output, 1=input) */
#define GPIO_DATAIN        0x038
#define GPIO_DATAOUT       0x03C
#define GPIO_LEVELDETECT0  0x040
#define GPIO_LEVELDETECT1  0x044
#define GPIO_RISINGDETECT  0x048
#define GPIO_FALLINGDETECT 0x04C
#define GPIO_CLEARDATAOUT  0x090
#define GPIO_SETDATAOUT    0x094

/* ---- OMAP3530 INTC (AINTC) register offsets ---- */

#define INTC_REVISION      0x000
#define INTC_SYSCONFIG     0x010
#define INTC_SYSSTATUS     0x014
#define INTC_SIR_IRQ       0x040
#define INTC_SIR_FIQ       0x044
#define INTC_CONTROL       0x048
#define INTC_PROTECTION    0x04C
#define INTC_IDLE          0x050
#define INTC_IRQ_PRIORITY  0x060
#define INTC_FIQ_PRIORITY  0x064
#define INTC_THRESHOLD     0x068
#define INTC_ITR(n)        (0x080 + (n) * 0x20)
#define INTC_MIR(n)        (0x084 + (n) * 0x20)
#define INTC_MIR_CLEAR(n)  (0x08C + (n) * 0x20)
#define INTC_MIR_SET(n)    (0x088 + (n) * 0x20)
#define INTC_ISR_CLEAR(n)  (0x094 + (n) * 0x20)

/* ---- OMAP3530 GPTimer register offsets ---- */

#define GPTIMER_TIDR       0x000
#define GPTIMER_TIOCP_CFG  0x010
#define GPTIMER_TISTAT     0x014
#define GPTIMER_TISR       0x018
#define GPTIMER_TIER       0x01C
#define GPTIMER_TWER       0x020
#define GPTIMER_TCLR       0x024
#define GPTIMER_TCRR       0x028
#define GPTIMER_TLDR       0x02C
#define GPTIMER_TTGR       0x030
#define GPTIMER_TWPS       0x034
#define GPTIMER_TMAR       0x038
#define GPTIMER_TCAR1      0x03C
#define GPTIMER_TCAR2      0x040
#define GPTIMER_TSCR       0x044

/* Timer TCLR bits */
#define GPTIMER_TCLR_ST    0x01   /* Start timer */
#define GPTIMER_TCLR_AR    0x02   /* Auto-reload */
#define GPTIMER_TCLR_PTV   0x0C   /* Pre-scale value */

/* ---- OMAP3530 PRCM (Clock/Power Management) ---- */

#define CM_FCLKEN1_CORE    (CM_BASE + 0x200)
#define CM_FCLKEN3_CORE    (CM_BASE + 0x208)
#define CM_ICLKEN1_CORE    (CM_BASE + 0x210)
#define CM_ICLKEN2_CORE    (CM_BASE + 0x214)
#define CM_ICLKEN3_CORE    (CM_BASE + 0x218)
#define CM_ICLKEN4_CORE    (CM_BASE + 0x21C)
#define CM_AUTOIDLE1_CORE  (CM_BASE + 0x230)
#define CM_IDLEST1_CORE    (CM_BASE + 0x220)
#define CM_IDLEST3_CORE    (CM_BASE + 0x228)

#define CM_CLKSEL_CORE     (CM_BASE + 0x240)

#define CM_FCLKEN_WKUP     (CM_BASE + 0x400)
#define CM_ICLKEN_WKUP     (CM_BASE + 0x410)
#define CM_IDLEST_WKUP     (CM_BASE + 0x420)
#define CM_AUTOIDLE_WKUP   (CM_BASE + 0x430)
#define CM_CLKSEL_WKUP     (CM_BASE + 0x440)

/* ---- OMAP3530 SMS (SDRAM Controller) ---- */

#define SMS_BASE           0x6C000000UL
#define SMS_SDRC_REVISION  (SMS_BASE + 0x000)
#define SMS_SYSCONFIG      (SMS_BASE + 0x010)

#define SDRC_BASE          0x6D000000UL
#define SDRC_SYSCONFIG     (SDRC_BASE + 0x010)
#define SDRC_CS_CFG        (SDRC_BASE + 0x040)
#define SDRC_SHARING       (SDRC_BASE + 0x044)
#define SDRC_MCFG_0        (SDRC_BASE + 0x080)
#define SDRC_MR_0          (SDRC_BASE + 0x084)
#define SDRC_EMR1_0        (SDRC_BASE + 0x088)
#define SDRC_ACTIM_CTRLA_0 (SDRC_BASE + 0x09C)
#define SDRC_ACTIM_CTRLB_0 (SDRC_BASE + 0x0A0)
#define SDRC_RFR_CTRL_0    (SDRC_BASE + 0x0A4)
#define SDRC_MCFG_1        (SDRC_BASE + 0x0B0)
#define SDRC_MR_1          (SDRC_BASE + 0x0B4)

/* SDRC MR command values */
#define SDRC_MR_CMD_NOP    0x0
#define SDRC_MR_CMD_PRC    0x1
#define SDRC_MR_CMD_EMRS   0x2
#define SDRC_MR_CMD_MRS    0x3
#define SDRC_MR_CMD_REF    0x4

/* SDRC MCFG bits */
#define SDRC_MCFG_MEMTYPE_DDR 0x01

/* ---- OMAP3530 GPMC (General Purpose Memory Controller for NOR/NAND) ---- */

#define GPMC_BASE          0x6E000000UL
#define GPMC_SYSCONFIG     (GPMC_BASE + 0x010)
#define GPMC_SYSSTATUS     (GPMC_BASE + 0x014)
#define GPMC_IRQSTATUS     (GPMC_BASE + 0x018)
#define GPMC_IRQENABLE     (GPMC_BASE + 0x01C)
#define GPMC_TIMEOUT_CTRL  (GPMC_BASE + 0x040)
#define GPMC_ERR_ADDRESS   (GPMC_BASE + 0x044)
#define GPMC_ERR_TYPE      (GPMC_BASE + 0x048)
#define GPMC_CONFIG        (GPMC_BASE + 0x050)
#define GPMC_STATUS        (GPMC_BASE + 0x054)

/* Per-chip-select config (cs0..cs7, stride 0x30) */
#define GPMC_CONFIG1(cs)   (GPMC_BASE + 0x060 + (cs) * 0x30)
#define GPMC_CONFIG2(cs)   (GPMC_BASE + 0x064 + (cs) * 0x30)
#define GPMC_CONFIG3(cs)   (GPMC_BASE + 0x068 + (cs) * 0x30)
#define GPMC_CONFIG4(cs)   (GPMC_BASE + 0x06C + (cs) * 0x30)
#define GPMC_CONFIG5(cs)   (GPMC_BASE + 0x070 + (cs) * 0x30)
#define GPMC_CONFIG6(cs)   (GPMC_BASE + 0x074 + (cs) * 0x30)
#define GPMC_CONFIG7(cs)   (GPMC_BASE + 0x078 + (cs) * 0x30)

/* GPMC CONFIG1 bits */
#define GPMC_CONFIG1_MWIDTH_16  (0x2 << 12)
#define GPMC_CONFIG1_DEVICESIZE_16 (1 << 4)
#define GPMC_CONFIG1_DEVICETYPE_NOR  (0x0 << 1)
#define GPMC_CONFIG1_DEVICETYPE_NAND (0x2 << 1)
#define GPMC_CONFIG1_READTYPE_SYNC  (1 << 8)
#define GPMC_CONFIG1_WRITETYPE_SYNC (1 << 9)

/* GPMC CONFIG7 bits */
#define GPMC_CONFIG7_CSVALID (1 << 6)

/* GPMC NAND command/address spaces */
#define GPMC_NAND_CMD(cs)   (GPMC_BASE + 0x1C0 + (cs) * 0x10)
#define GPMC_NAND_ADDR(cs)  (GPMC_BASE + 0x1C4 + (cs) * 0x10)
#define GPMC_NAND_DATA(cs)  (GPMC_BASE + 0x1C8 + (cs) * 0x10)

/* NAND flash commands (ONFI) */
#define NAND_CMD_READ0      0x00
#define NAND_CMD_READ1      0x01
#define NAND_CMD_PAGEPROG   0x10
#define NAND_CMD_READSTART  0x30
#define NAND_CMD_ERASE1     0x60
#define NAND_CMD_STATUS     0x70
#define NAND_CMD_SEQIN      0x80
#define NAND_CMD_ERASE2     0xD0
#define NAND_CMD_READID     0x90
#define NAND_CMD_RESET      0xFF

/* NAND status bits */
#define NAND_STATUS_READY   0x40
#define NAND_STATUS_FAIL    0x01

/* NOR flash commands (CFI) */
#define NOR_CMD_READ        0xFF
#define NOR_CMD_RESET       0xF0
#define NOR_CMD_READ_ID     0x90
#define NOR_CMD_CFI         0x98
#define NOR_CMD_ERASE       0x20
#define NOR_CMD_CONFIRM     0xD0
#define NOR_CMD_PROG        0x40

/* ---- Boot source detection ---- */

typedef enum {
    BOOT_SOURCE_NAND = 0,
    BOOT_SOURCE_NOR,
    BOOT_SOURCE_MMC,
    BOOT_SOURCE_UART,
    BOOT_SOURCE_USB,
    BOOT_SOURCE_UNKNOWN
} boot_source_t;

/* ---- OMAP3530 boot configuration (SYS_BOOT pins) ---- */

#define CONTROL_STATUS     (SCM_BASE + 0x2F0)

#define SYSBOOT_MASK       0x0000001FUL

#endif /* FIRMWARE_COMMON_PLATFORM_H */
