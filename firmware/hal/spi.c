/*
 * OMAP3530 McSPI driver
 */

#include "spi.h"

int spi_init(spi_dev_t *dev, uint32_t base, uint8_t channel,
             uint32_t clock_hz, uint32_t speed_hz, uint8_t mode, uint8_t bpw) {
    dev->base = (hw_reg32_t)base;
    dev->channel = channel;
    dev->clock_hz = clock_hz;
    dev->speed_hz = speed_hz;
    dev->mode = mode;
    dev->bits_per_word = bpw;

    /* Reset McSPI module */
    reg_write32(dev->base + MCSPI_SYSCONFIG, 0x02);
    delay_cycles(100);
    while (!(reg_read32(dev->base + MCSPI_SYSSTATUS) & 0x01))
        ;

    /* Single-channel master mode */
    reg_write32(dev->base + MCSPI_MODULCTRL, MCSPI_MODULCTRL_SINGLE);

    /* Configure channel */
    uint32_t chconf = 0;

    /* Word length: value = (bpw - 1), 0 means 32-bit */
    if (bpw < 32)
        chconf |= ((bpw - 1) << MCSPI_CHCONF_WL_SHIFT);

    /* Clock divider: f_spi = f_input / (2 * (CLKD + 1)) */
    uint32_t clkdiv = (dev->clock_hz / (2 * dev->speed_hz)) - 1;
    if (clkdiv > 0xF) clkdiv = 0xF;
    chconf |= (clkdiv << MCSPI_CHCONF_CLKD_SHIFT);

    /* Clock polarity and phase */
    if (mode & 2) chconf |= MCSPI_CHCONF_POL;
    if (mode & 1) chconf |= MCSPI_CHCONF_PHA;

    /* Enable TX on channel 0, RX enabled */
    chconf &= ~MCSPI_CHCONF_DPE0;   /* DPE0=0: TX enabled on SPIEN0 */
    chconf |= MCSPI_CHCONF_DPE1;    /* DPE1=1: TX disabled on SPIEN1 */
    chconf &= ~MCSPI_CHCONF_IS;     /* IS=0: data line 0 for RX */

    reg_write32(dev->base + MCSPI_CHCONF(dev->channel), chconf);

    /* Disable FIFOs for simple polled mode */
    chconf = reg_read32(dev->base + MCSPI_CHCONF(dev->channel));
    chconf &= ~(MCSPI_CHCONF_FFER | MCSPI_CHCONF_FFEW);
    reg_write32(dev->base + MCSPI_CHCONF(dev->channel), chconf);

    /* Enable channel */
    reg_write32(dev->base + MCSPI_CHCTRL(dev->channel), MCSPI_CHCTRL_EN);

    return 0;
}

void spi_set_speed(spi_dev_t *dev, uint32_t speed_hz) {
    dev->speed_hz = speed_hz;
    uint32_t clkdiv = (dev->clock_hz / (2 * dev->speed_hz)) - 1;
    if (clkdiv > 0xF) clkdiv = 0xF;

    uint32_t chconf = reg_read32(dev->base + MCSPI_CHCONF(dev->channel));
    chconf &= ~(0xF << MCSPI_CHCONF_CLKD_SHIFT);
    chconf |= (clkdiv << MCSPI_CHCONF_CLKD_SHIFT);
    reg_write32(dev->base + MCSPI_CHCONF(dev->channel), chconf);
}

int spi_transfer(spi_dev_t *dev, const uint8_t *tx, uint8_t *rx, uint32_t len) {
    uint32_t ch = dev->channel;

    for (uint32_t i = 0; i < len; i++) {
        /* Force SPIEN active */
        uint32_t chconf = reg_read32(dev->base + MCSPI_CHCONF(ch));
        chconf |= MCSPI_CHCONF_FORCE;
        reg_write32(dev->base + MCSPI_CHCONF(ch), chconf);

        /* Wait for TX empty */
        while (!(reg_read32(dev->base + MCSPI_CHSTAT(ch)) & MCSPI_CHSTAT_TXS))
            ;

        /* Write TX data */
        uint32_t data = tx ? tx[i] : 0xFF;
        reg_write32(dev->base + MCSPI_TX(ch), data);

        /* Wait for RX ready */
        while (!(reg_read32(dev->base + MCSPI_CHSTAT(ch)) & MCSPI_CHSTAT_RXS))
            ;

        /* Read RX data */
        if (rx)
            rx[i] = (uint8_t)(reg_read32(dev->base + MCSPI_RX(ch)) & 0xFF);
        else
            reg_read32(dev->base + MCSPI_RX(ch));  /* Discard */

        /* De-assert SPIEN on last byte */
        if (i == len - 1) {
            chconf &= ~MCSPI_CHCONF_FORCE;
            reg_write32(dev->base + MCSPI_CHCONF(ch), chconf);
        }
    }

    return 0;
}

int spi_write_then_read(spi_dev_t *dev, const uint8_t *tx, uint32_t tx_len,
                        uint8_t *rx, uint32_t rx_len) {
    if (spi_transfer(dev, tx, (uint8_t *)0, tx_len) != 0)
        return -1;
    return spi_transfer(dev, (const uint8_t *)0, rx, rx_len);
}

uint8_t spi_read_reg8(spi_dev_t *dev, uint8_t reg) {
    uint8_t tx = reg | 0x80;   /* Read bit */
    uint8_t rx;
    spi_write_then_read(dev, &tx, 1, &rx, 1);
    return rx;
}

void spi_write_reg8(spi_dev_t *dev, uint8_t reg, uint8_t val) {
    uint8_t tx[2] = { reg & 0x7F, val };
    spi_transfer(dev, tx, (uint8_t *)0, 2);
}
