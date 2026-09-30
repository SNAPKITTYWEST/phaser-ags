/*
 * OMAP3530 McSPI (Multi-Channel SPI) driver
 * OMAP3530 has 4 McSPI controllers. Used for:
 *   McSPI1: Flash, sensor
 *   McSPI2: FPGA configuration (like IMX6 ECSPI for FPGA)
 * Modeled on IMX6 Platinum ECSPI1/2 pinmux + setup pattern
 */

#ifndef FIRMWARE_HAL_SPI_H
#define FIRMWARE_HAL_SPI_H

#include "../common/types.h"
#include "../common/platform.h"

#define MCSPI1_BASE     0x48098000UL
#define MCSPI2_BASE     0x4809A000UL
#define MCSPI3_BASE     0x480B8000UL
#define MCSPI4_BASE     0x480BA000UL

/* McSPI register offsets */
#define MCSPI_REVISION  0x000
#define MCSPI_SYSCONFIG 0x010
#define MCSPI_SYSSTATUS 0x014
#define MCSPI_IRQSTATUS 0x018
#define MCSPI_IRQENABLE 0x01C
#define MCSPI_SYST      0x024
#define MCSPI_MODULCTRL 0x028

/* Per-channel registers (ch 0-3, stride 0x14) */
#define MCSPI_CHCONF(ch)  (0x02C + (ch) * 0x14)
#define MCSPI_CHSTAT(ch)  (0x030 + (ch) * 0x14)
#define MCSPI_CHCTRL(ch)  (0x034 + (ch) * 0x14)
#define MCSPI_TX(ch)      (0x038 + (ch) * 0x14)
#define MCSPI_RX(ch)      (0x03C + (ch) * 0x14)

/* MCSPI_MODULCTRL bits */
#define MCSPI_MODULCTRL_SINGLE   (1 << 0)   /* Single-channel mode */

/* MCSPI_CHCONF bits */
#define MCSPI_CHCONF_CLKD_SHIFT  2           /* Clock divider [5:2] */
#define MCSPI_CHCONF_POL         (1 << 1)    /* Clock polarity */
#define MCSPI_CHCONF_PHA         (1 << 0)    /* Clock phase */
#define MCSPI_CHCONF_DPE0        (1 << 16)   /* Data enable for channel 0 (0=TX enabled) */
#define MCSPI_CHCONF_DPE1        (1 << 17)
#define MCSPI_CHCONF_IS          (1 << 18)   /* Input select */
#define MCSPI_CHCONF_WL_SHIFT    6           /* Word length [11:6], 0 = 32-bit, N = N+1 bits */
#define MCSPI_CHCONF_FFER        (1 << 27)   /* FIFO enable for RX */
#define MCSPI_CHCONF_FFEW        (1 << 28)   /* FIFO enable for TX */
#define MCSPI_CHCONF_FORCE       (1 << 20)   /* SPIEN force */
#define MCSPI_CHCONF_TURBO       (1 << 25)   /* Turbo mode */

/* MCSPI_CHSTAT bits */
#define MCSPI_CHSTAT_TXS         (1 << 1)    /* TX empty */
#define MCSPI_CHSTAT_RXS         (1 << 0)    /* RX ready */

/* MCSPI_CHCTRL bits */
#define MCSPI_CHCTRL_EN          (1 << 0)    /* Channel enable */

/* SPI modes (CPOL/CPHA) */
#define SPI_MODE_0  0   /* CPOL=0, CPHA=0 */
#define SPI_MODE_1  1   /* CPOL=0, CPHA=1 */
#define SPI_MODE_2  2   /* CPOL=1, CPHA=0 */
#define SPI_MODE_3  3   /* CPOL=1, CPHA=1 */

typedef struct {
    hw_reg32_t base;
    uint8_t    channel;      /* 0-3 */
    uint32_t   clock_hz;     /* Input clock (REF_CLK or L3) */
    uint32_t   speed_hz;     /* Desired SPI clock */
    uint8_t    mode;         /* SPI_MODE_x */
    uint8_t    bits_per_word;
} spi_dev_t;

int  spi_init(spi_dev_t *dev, uint32_t base, uint8_t channel,
              uint32_t clock_hz, uint32_t speed_hz, uint8_t mode, uint8_t bpw);
void spi_set_speed(spi_dev_t *dev, uint32_t speed_hz);
int  spi_transfer(spi_dev_t *dev, const uint8_t *tx, uint8_t *rx, uint32_t len);
int  spi_write_then_read(spi_dev_t *dev, const uint8_t *tx, uint32_t tx_len,
                         uint8_t *rx, uint32_t rx_len);
uint8_t spi_read_reg8(spi_dev_t *dev, uint8_t reg);
void   spi_write_reg8(spi_dev_t *dev, uint8_t reg, uint8_t val);

#endif /* FIRMWARE_HAL_SPI_H */
