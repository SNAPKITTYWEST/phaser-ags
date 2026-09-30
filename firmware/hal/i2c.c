/*
 * OMAP3530 I2C driver
 */

#include "i2c.h"

static int i2c_wait_status(i2c_dev_t *dev, uint32_t mask, uint32_t timeout) {
    hw_reg32_t base = dev->base;
    while (timeout--) {
        uint32_t stat = reg_read32(base + I2C_STAT);
        if (stat & mask)
            return (int)stat;
    }
    return -1;
}

static void i2c_reset(i2c_dev_t *dev) {
    hw_reg32_t base = dev->base;

    /* Soft reset */
    reg_write32(base + I2C_SYSC, 0x02);
    delay_cycles(100);
    while (!(reg_read32(base + I2C_SYSS) & 0x01))
        ;
}

int i2c_init(i2c_dev_t *dev, uint32_t base, uint32_t clock_hz, uint16_t own_addr) {
    dev->base = (hw_reg32_t)base;
    dev->clock_hz = clock_hz;
    dev->own_addr = own_addr;

    i2c_reset(dev);

    /* Set own address */
    reg_write32(dev->base + I2C_OA, own_addr);

    /* Default to 100kHz */
    i2c_set_speed(dev, 100000);

    /* Enable I2C */
    reg_write32(dev->base + I2C_CON, I2C_CON_EN);

    return 0;
}

void i2c_set_speed(i2c_dev_t *dev, uint32_t speed_hz) {
    hw_reg32_t base = dev->base;

    /* Disable I2C while changing speed */
    reg_clr32(base + I2C_CON, I2C_CON_EN);

    /* Prescaler: f_i2c = f_sys / (PSC+1), target ~12MHz internal */
    uint32_t psc = (dev->clock_hz / 12000000UL) - 1;
    if (psc > 0xFF) psc = 0xFF;

    /* SCLL/SCLH: SCL = f_i2c / (SCLL + SCLH + 7)
       For 100kHz: 12MHz / 100kHz = 120 cycles per bit period
       SCLL ≈ 60-7 = 53, SCLH ≈ 60-7 = 53 */
    uint32_t scll = 53;
    uint32_t sclh = 53;

    if (speed_hz >= 400000) {
        /* Fast mode: 400kHz: 12MHz / 400kHz = 30 cycles */
        psc = (dev->clock_hz / 19200000UL) - 1;
        if (psc > 0xFF) psc = 0xFF;
        scll = 9;
        sclh = 6;
    }

    reg_write32(base + I2C_PSC, psc);
    reg_write32(base + I2C_SCLL, scll);
    reg_write32(base + I2C_SCLH, sclh);

    /* Re-enable */
    reg_set32(base + I2C_CON, I2C_CON_EN);
}

int i2c_probe(i2c_dev_t *dev, uint8_t addr) {
    hw_reg32_t base = dev->base;

    /* Wait for bus free */
    if (reg_read32(base + I2C_STAT) & I2C_STAT_BB)
        return -1;

    /* Set target address */
    reg_write32(base + I2C_SA, addr);
    reg_write32(base + I2C_CNT, 0);

    /* Start condition, master transmit, stop */
    reg_write32(base + I2C_CON,
        I2C_CON_EN | I2C_CON_MST | I2C_CON_TRX | I2C_CON_STT | I2C_CON_STP);

    int result = i2c_wait_status(dev, I2C_STAT_ARDY, 500000);
    if (result < 0) return -1;

    /* Clear status */
    reg_write32(base + I2C_STAT, 0xFFFF);

    /* Check for NACK */
    if (result & I2C_STAT_NACK)
        return -1;

    return 0;
}

int i2c_read(i2c_dev_t *dev, uint8_t addr, uint8_t *buf, uint32_t len) {
    hw_reg32_t base = dev->base;

    if (reg_read32(base + I2C_STAT) & I2C_STAT_BB)
        return -1;

    reg_write32(base + I2C_SA, addr);
    reg_write32(base + I2C_CNT, len);

    /* Master receive */
    reg_write32(base + I2C_CON,
        I2C_CON_EN | I2C_CON_MST | I2C_CON_STT | I2C_CON_STP);

    for (uint32_t i = 0; i < len; i++) {
        int stat = i2c_wait_status(dev, I2C_STAT_RRDY, 500000);
        if (stat < 0) return -1;
        buf[i] = (uint8_t)(reg_read32(base + I2C_DATA) & 0xFF);
        reg_write32(base + I2C_STAT, I2C_STAT_RRDY);
    }

    reg_write32(base + I2C_STAT, 0xFFFF);
    return 0;
}

int i2c_write(i2c_dev_t *dev, uint8_t addr, const uint8_t *buf, uint32_t len) {
    hw_reg32_t base = dev->base;

    if (reg_read32(base + I2C_STAT) & I2C_STAT_BB)
        return -1;

    reg_write32(base + I2C_SA, addr);
    reg_write32(base + I2C_CNT, len);

    /* Master transmit */
    reg_write32(base + I2C_CON,
        I2C_CON_EN | I2C_CON_MST | I2C_CON_TRX | I2C_CON_STT);

    for (uint32_t i = 0; i < len; i++) {
        int stat = i2c_wait_status(dev, I2C_STAT_XRDY, 500000);
        if (stat < 0) return -1;
        if (stat & I2C_STAT_NACK) {
            reg_write32(base + I2C_CON, I2C_CON_EN | I2C_CON_STP);
            return -1;
        }
        reg_write32(base + I2C_DATA, buf[i]);
        reg_write32(base + I2C_STAT, I2C_STAT_XRDY);
    }

    /* Send stop */
    reg_set32(base + I2C_CON, I2C_CON_STP);
    reg_write32(base + I2C_STAT, 0xFFFF);
    return 0;
}

int i2c_reg_read(i2c_dev_t *dev, uint8_t addr, uint8_t reg, uint8_t *val) {
    /* Write register address, then read */
    if (i2c_write(dev, addr, &reg, 1) != 0)
        return -1;
    return i2c_read(dev, addr, val, 1);
}

int i2c_reg_write(i2c_dev_t *dev, uint8_t addr, uint8_t reg, uint8_t val) {
    uint8_t buf[2] = { reg, val };
    return i2c_write(dev, addr, buf, 2);
}
