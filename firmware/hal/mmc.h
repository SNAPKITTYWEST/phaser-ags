/*
 * OMAP3530 HSMMC (High-Speed MMC/SD) driver
 * OMAP3530 has 3 MMC controllers: MMC1 (eMMC/SD card), MMC2, MMC3
 * Needed for: loading kernel from SD card, FAT filesystem boot
 */

#ifndef FIRMWARE_HAL_MMC_H
#define FIRMWARE_HAL_MMC_H

#include "../common/types.h"
#include "../common/platform.h"

#define MMC1_BASE  0x4809C000UL
#define MMC2_BASE  0x480B4000UL
#define MMC3_BASE  0x480AD000UL

/* MMC register offsets */
#define MMC_SYSCONFIG   0x010
#define MMC_SYSSTATUS   0x014
#define MMC_CSRE        0x024
#define MMC_SYST        0x028
#define MMC_CON         0x02C
#define MMC_PWCNT       0x030
#define MMC_BLK         0x104
#define MMC_ARG         0x108
#define MMC_CMD         0x10C
#define MMC_RSP10       0x110
#define MMC_RSP32       0x114
#define MMC_RSP54       0x118
#define MMC_RSP76       0x11C
#define MMC_DATA        0x120
#define MMC_PSTATE      0x124
#define MMC_HCTL        0x128
#define MMC_SYSCTL      0x12C
#define MMC_STAT        0x130
#define MMC_IE          0x134
#define MMC_ISE         0x138
#define MMC_AC12        0x13C
#define MMC_CAPA        0x140

/* MMC_CON bits */
#define MMC_CON_INIT    (1 << 1)    /* Initialization stream */
#define MMC_CON_DW8     (1 << 5)    /* 8-bit data bus */
#define MMC_CON_CEATA   (1 << 6)    /* eMMC DDR mode */

/* MMC_HCTL bits */
#define MMC_HCTL_SDBP   (1 << 8)    /* Bus power on */
#define MMC_HCTL_SDVS_SHIFT  9      /* Voltage select: 1=1.8V, 6=3.0V */
#define MMC_HCTL_DTW_SHIFT   1      /* Data width: 0=1-bit, 1=4-bit, 2=8-bit */

/* MMC_SYSCTL bits */
#define MMC_SYSCTL_SRC_SHIFT 16     /* Clock source select */
#define MMC_SYSCTL_SRD       (1 << 24)  /* Software reset for CMD line */
#define MMC_SYSCTL_SRH       (1 << 25)  /* Software reset for data line */
#define MMC_SYSCTL_ICE       (1 << 0)   /* Input clock enable */
#define MMC_SYSCTL_ICS       (1 << 1)   /* Input clock stable */
#define MMC_SYSCTL_CEN       (1 << 2)   /* Card clock enable */
#define MMC_SYSCTL_CLKD_SHIFT 6         /* Clock divider [15:6] */

/* MMC_PSTATE bits */
#define MMC_PSTATE_CMDI   (1 << 0)   /* CMD line in use */
#define MMC_PSTATE_DATI   (1 << 1)   /* DAT line in use */

/* MMC_STAT bits */
#define MMC_STAT_CC       (1 << 0)   /* Command complete */
#define MMC_STAT_TC       (1 << 1)   /* Transfer complete */
#define MMC_STAT_ERR      (1 << 15)  /* Any error */

/* MMC_CMD bits */
#define MMC_CMD_INDX_SHIFT 24
#define MMC_CMD_RSP_TYPE_SHIFT 16
#define MMC_CMD_DP       (1 << 21)   /* Data present */
#define MMC_CMD_MSBS     (1 << 5)    /* Multi-block select */
#define MMC_CMD_RSP_NONE   (0 << MMC_CMD_RSP_TYPE_SHIFT)
#define MMC_CMD_RSP_136   (1 << MMC_CMD_RSP_TYPE_SHIFT)
#define MMC_CMD_RSP_48    (2 << MMC_CMD_RSP_TYPE_SHIFT)
#define MMC_CMD_RSP_48B   (3 << MMC_CMD_RSP_TYPE_SHIFT)

/* MMC_BLK bits */
#define MMC_BLK_NBLK_SHIFT 16        /* Number of blocks */
#define MMC_BLK_BLEN_SHIFT 0         /* Block length (512 = 0x200) */

/* SD card commands */
#define SD_CMD_GO_IDLE_STATE      0
#define SD_CMD_ALL_SEND_CID       2
#define SD_CMD_SEND_RELATIVE_ADDR 3
#define SD_CMD_SELECT_CARD        7
#define SD_CMD_SEND_IF_COND       8
#define SD_CMD_SEND_CSD           9
#define SD_CMD_SEND_CID          10
#define SD_CMD_STOP_TRANSMISSION 12
#define SD_CMD_SEND_STATUS       13
#define SD_CMD_READ_SINGLE_BLOCK 17
#define SD_CMD_READ_MULTI_BLOCK  18
#define SD_CMD_WRITE_SINGLE_BLOCK 24
#define SD_CMD_WRITE_MULTI_BLOCK 25
#define SD_CMD_APP_CMD           55

/* SD APP commands (preceded by CMD55) */
#define SD_ACMD_SET_BUS_WIDTH      6
#define SD_ACMD_SD_SEND_OP_COND  41

/* Block size */
#define MMC_BLOCK_SIZE  512

typedef struct {
    hw_reg32_t base;
    uint32_t   clock_hz;       /* Input clock */
    uint32_t   card_clock;     /* Card clock frequency */
    uint16_t   rca;            /* Relative card address */
    uint8_t    bus_width;      /* 1, 4, or 8 */
    int        high_capacity;  /* SDHC/eMMC */
} mmc_dev_t;

int   mmc_init(mmc_dev_t *dev, uint32_t base, uint32_t clock_hz);
int   mmc_send_cmd(mmc_dev_t *dev, uint32_t cmd, uint32_t arg,
                   uint32_t rsp_type, uint32_t *rsp);
int   mmc_read_block(mmc_dev_t *dev, uint32_t block, uint8_t *buf);
int   mmc_read_blocks(mmc_dev_t *dev, uint32_t start, uint8_t *buf, uint32_t count);
int   mmc_detect_card(mmc_dev_t *dev);

#endif /* FIRMWARE_HAL_MMC_H */
