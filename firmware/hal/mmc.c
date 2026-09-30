/*
 * OMAP3530 HSMMC driver
 */

#include "mmc.h"
#include "gpio.h"

static int mmc_wait_status(mmc_dev_t *dev, uint32_t mask, uint32_t timeout) {
    while (timeout--) {
        if (reg_read32(dev->base + MMC_STAT) & mask)
            return 0;
    }
    return -1;
}

static void mmc_set_clock(mmc_dev_t *dev, uint32_t freq) {
    hw_reg32_t base = dev->base;

    /* Stop clock */
    reg_clr32(base + MMC_SYSCTL, MMC_SYSCTL_CEN);

    /* Calculate divider: MMC_CLK = SYS_CLK / (2 * CLKD) */
    uint32_t div = 1;
    while ((dev->clock_hz / (2 * div)) > freq) div++;
    if (div > 0x3FF) div = 0x3FF;

    /* Set divider */
    reg32_t sysctl = reg_read32(base + MMC_SYSCTL);
    sysctl &= ~(0x3FF << MMC_SYSCTL_CLKD_SHIFT);
    sysctl |= (div << MMC_SYSCTL_CLKD_SHIFT);
    reg_write32(base + MMC_SYSCTL, sysctl);

    /* Enable clock */
    reg_set32(base + MMC_SYSCTL, MMC_SYSCTL_ICE);
    while (!(reg_read32(base + MMC_SYSCTL) & MMC_SYSCTL_ICS))
        ;

    reg_set32(base + MMC_SYSCTL, MMC_SYSCTL_CEN);
    dev->card_clock = dev->clock_hz / (2 * div);
}

int mmc_init(mmc_dev_t *dev, uint32_t base, uint32_t clock_hz) {
    dev->base = (hw_reg32_t)base;
    dev->clock_hz = clock_hz;
    dev->rca = 0;
    dev->bus_width = 1;
    dev->high_capacity = 0;

    /* Soft reset */
    reg_set32(dev->base + MMC_SYSCONFIG, 0x02);
    delay_cycles(200);
    while (!(reg_read32(dev->base + MMC_SYSSTATUS) & 0x01))
        ;

    /* Reset CMD and DAT lines */
    reg_set32(dev->base + MMC_SYSCTL, MMC_SYSCTL_SRD | MMC_SYSCTL_SRH);
    delay_cycles(200);
    while (reg_read32(dev->base + MMC_SYSCTL) & (MMC_SYSCTL_SRD | MMC_SYSCTL_SRH))
        ;

    /* Set voltage to 3.0V */
    reg32_t hctl = reg_read32(dev->base + MMC_HCTL);
    hctl &= ~(0xF << MMC_HCTL_SDVS_SHIFT);
    hctl |= (6 << MMC_HCTL_SDVS_SHIFT);  /* 3.0V */
    reg_write32(dev->base + MMC_HCTL, hctl);

    /* Turn on bus power */
    reg_set32(dev->base + MMC_HCTL, MMC_HCTL_SDBP);
    delay_cycles(500);

    /* Start with identification clock (400kHz) */
    mmc_set_clock(dev, 400000);

    /* Enable all interrupts */
    reg_write32(dev->base + MMC_IE, 0xFFFFFFFF);
    reg_write32(dev->base + MMC_ISE, 0xFFFFFFFF);

    /* Set block length to 512 */
    reg_write32(dev->base + MMC_BLK, (1 << MMC_BLK_NBLK_SHIFT) | MMC_BLOCK_SIZE);

    return 0;
}

int mmc_send_cmd(mmc_dev_t *dev, uint32_t cmd, uint32_t arg,
                 uint32_t rsp_type, uint32_t *rsp) {
    hw_reg32_t base = dev->base;

    /* Wait for CMD and DAT lines to be free */
    uint32_t timeout = 1000000;
    while ((reg_read32(base + MMC_PSTATE) & (MMC_PSTATE_CMDI | MMC_PSTATE_DATI)) && timeout--)
        ;

    /* Clear status */
    reg_write32(base + MMC_STAT, 0xFFFFFFFF);

    /* Set argument */
    reg_write32(base + MMC_ARG, arg);

    /* Set command */
    reg32_t cmd_reg = (cmd << MMC_CMD_INDX_SHIFT) | rsp_type;
    reg_write32(base + MMC_CMD, cmd_reg);

    /* Wait for command complete */
    if (mmc_wait_status(dev, MMC_STAT_CC, 1000000) != 0)
        return -1;

    /* Read response if requested */
    if (rsp && rsp_type != MMC_CMD_RSP_NONE) {
        if (rsp_type == MMC_CMD_RSP_136) {
            rsp[0] = reg_read32(base + MMC_RSP10);
            rsp[1] = reg_read32(base + MMC_RSP32);
            rsp[2] = reg_read32(base + MMC_RSP54);
            rsp[3] = reg_read32(base + MMC_RSP76);
        } else {
            rsp[0] = reg_read32(base + MMC_RSP10);
        }
    }

    /* Clear CC status */
    reg_write32(base + MMC_STAT, MMC_STAT_CC);

    return 0;
}

int mmc_detect_card(mmc_dev_t *dev) {
    uint32_t rsp[4];

    /* CMD0: GO_IDLE_STATE */
    if (mmc_send_cmd(dev, SD_CMD_GO_IDLE_STATE, 0, MMC_CMD_RSP_NONE, (uint32_t *)0) != 0)
        return -1;

    /* CMD8: SEND_IF_COND (SD v2.0 check) */
    int cmd8_result = mmc_send_cmd(dev, SD_CMD_SEND_IF_COND, 0x000001AA,
                                    MMC_CMD_RSP_48, rsp);
    if (cmd8_result == 0 && (rsp[0] & 0xFF) == 0xAA) {
        dev->high_capacity = 1;
    }

    /* ACMD41: SD_SEND_OP_COND (repeat until busy bit set) */
    uint32_t retry = 1000;
    do {
        /* CMD55: APP_CMD */
        mmc_send_cmd(dev, SD_CMD_APP_CMD, 0, MMC_CMD_RSP_48, rsp);

        /* ACMD41: HCS=1 for SDHC support */
        mmc_send_cmd(dev, SD_ACMD_SD_SEND_OP_COND,
                     0x40FF8000, MMC_CMD_RSP_48, rsp);
        retry--;
    } while (!(rsp[0] & (1 << 31)) && retry > 0);

    if (retry == 0)
        return -1;

    if (rsp[0] & (1 << 30))
        dev->high_capacity = 1;

    /* CMD2: ALL_SEND_CID */
    mmc_send_cmd(dev, SD_CMD_ALL_SEND_CID, 0, MMC_CMD_RSP_136, rsp);

    /* CMD3: SEND_RELATIVE_ADDR */
    mmc_send_cmd(dev, SD_CMD_SEND_RELATIVE_ADDR, 0, MMC_CMD_RSP_48, rsp);
    dev->rca = (uint16_t)(rsp[0] >> 16);

    /* Switch to data transfer clock (25MHz) */
    mmc_set_clock(dev, 25000000);

    /* CMD7: SELECT_CARD */
    mmc_send_cmd(dev, SD_CMD_SELECT_CARD, (uint32_t)dev->rca << 16,
                 MMC_CMD_RSP_48B, rsp);

    /* ACMD6: SET_BUS_WIDTH to 4-bit */
    mmc_send_cmd(dev, SD_CMD_APP_CMD, (uint32_t)dev->rca << 16,
                 MMC_CMD_RSP_48, rsp);
    mmc_send_cmd(dev, SD_ACMD_SET_BUS_WIDTH, 2, MMC_CMD_RSP_48, rsp);

    /* Configure 4-bit bus in HCTL */
    reg32_t hctl = reg_read32(dev->base + MMC_HCTL);
    hctl &= ~(0x3 << MMC_HCTL_DTW_SHIFT);
    hctl |= (1 << MMC_HCTL_DTW_SHIFT);  /* 4-bit */
    reg_write32(dev->base + MMC_HCTL, hctl);
    dev->bus_width = 4;

    return 0;
}

int mmc_read_block(mmc_dev_t *dev, uint32_t block, uint8_t *buf) {
    hw_reg32_t base = dev->base;

    /* Set block count and length */
    reg_write32(base + MMC_BLK, (1 << MMC_BLK_NBLK_SHIFT) | MMC_BLOCK_SIZE);

    /* For standard capacity cards, address is byte offset */
    uint32_t addr = dev->high_capacity ? block : (block * MMC_BLOCK_SIZE);

    /* CMD17: READ_SINGLE_BLOCK */
    reg_write32(base + MMC_ARG, addr);
    reg32_t cmd_reg = (SD_CMD_READ_SINGLE_BLOCK << MMC_CMD_INDX_SHIFT)
                    | MMC_CMD_RSP_48B | MMC_CMD_DP;
    reg_write32(base + MMC_CMD, cmd_reg);

    /* Wait for transfer complete */
    if (mmc_wait_status(dev, MMC_STAT_TC, 5000000) != 0)
        return -1;

    /* Read data from FIFO */
    uint32_t *buf32 = (uint32_t *)buf;
    for (int i = 0; i < MMC_BLOCK_SIZE / 4; i++) {
        while (!(reg_read32(base + MMC_PSTATE) & (1 << 4)))  /* BREN */
            ;
        buf32[i] = reg_read32(base + MMC_DATA);
    }

    /* Clear status */
    reg_write32(base + MMC_STAT, 0xFFFFFFFF);

    return 0;
}

int mmc_read_blocks(mmc_dev_t *dev, uint32_t start, uint8_t *buf, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        if (mmc_read_block(dev, start + i, buf + i * MMC_BLOCK_SIZE) != 0)
            return -1;
    }
    return 0;
}
