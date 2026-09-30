/*
 * OMAP3530 I2C driver
 * OMAP3530 has 4 I2C controllers (I2C1-4), NS-compatible
 * Used for: PMIC communication (TPS65950), EEPROM, sensors
 * Modeled on R8A7740 I2C0/I2C1 MSTPCR gating pattern
 */

#ifndef FIRMWARE_HAL_I2C_H
#define FIRMWARE_HAL_I2C_H

#include "../common/types.h"
#include "../common/platform.h"

#define I2C1_BASE  0x48070000UL
#define I2C2_BASE  0x48072000UL
#define I2C3_BASE  0x48060000UL
#define I2C4_BASE  0x48350000UL

/* I2C register offsets */
#define I2C_REV     0x00
#define I2C_IE      0x04
#define I2C_STAT    0x08
#define I2C_WE      0x0C
#define I2C_SYSS    0x10
#define I2C_BUF     0x14
#define I2C_CNT     0x18
#define I2C_DATA    0x1C
#define I2C_SYSC    0x20
#define I2C_CON     0x24
#define I2C_OA      0x28
#define I2C_SA      0x2C
#define I2C_PSC     0x30
#define I2C_SCLL    0x34
#define I2C_SCLH    0x38
#define I2C_SYSTEST 0x3C
#define I2C_BUFSTAT 0x40
#define I2C_OA1     0x44
#define I2C_OA2     0x48
#define I2C_OA3     0x4C
#define I2C_ACTOA   0x50
#define I2C_SBLOCK  0x54

/* I2C_CON bits */
#define I2C_CON_EN      (1 << 15)
#define I2C_CON_STB     (1 << 11)
#define I2C_CON_MST     (1 << 10)
#define I2C_CON_TRX     (1 << 9)
#define I2C_CON_XA      (1 << 8)
#define I2C_CON_STT     (1 << 0)
#define I2C_CON_STP     (1 << 1)

/* I2C_STAT bits */
#define I2C_STAT_NACK   (1 << 1)
#define I2C_STAT_XRDY   (1 << 4)
#define I2C_STAT_RRDY   (1 << 3)
#define I2C_STAT_ARDY   (1 << 2)
#define I2C_STAT_BB     (1 << 12)
#define I2C_STAT_XUDF   (1 << 10)
#define I2C_STAT_ROVR   (1 << 11)

typedef struct {
    hw_reg32_t base;
    uint32_t   clock_hz;
    uint16_t   own_addr;
} i2c_dev_t;

int  i2c_init(i2c_dev_t *dev, uint32_t base, uint32_t clock_hz, uint16_t own_addr);
void i2c_set_speed(i2c_dev_t *dev, uint32_t speed_hz);
int  i2c_probe(i2c_dev_t *dev, uint8_t addr);
int  i2c_read(i2c_dev_t *dev, uint8_t addr, uint8_t *buf, uint32_t len);
int  i2c_write(i2c_dev_t *dev, uint8_t addr, const uint8_t *buf, uint32_t len);
int  i2c_reg_read(i2c_dev_t *dev, uint8_t addr, uint8_t reg, uint8_t *val);
int  i2c_reg_write(i2c_dev_t *dev, uint8_t addr, uint8_t reg, uint8_t val);

#endif /* FIRMWARE_HAL_I2C_H */
