/*
 * OMAP3530 EMAC (Ethernet MAC) + MDIO driver
 * OMAP3530 has built-in EMAC (10/100) + MDIO for PHY management
 * Modeled on IMX6 Platinum platinum_setup_enet() pattern:
 *   PHY in reset → pinmux → delay → release → MDIO ready → clock enable
 */

#ifndef FIRMWARE_HAL_ETHERNET_H
#define FIRMWARE_HAL_ETHERNET_H

#include "../common/types.h"
#include "../common/platform.h"

/* EMAC base addresses */
#define EMAC_BASE       0x5C030000UL
#define EMAC_WRAPPER    0x5C000000UL
#define MDIO_BASE       0x5C030000UL

/* MDIO register offsets (within EMAC space) */
#define MDIO_CTRL       0x000
#define MDIO_ALIVE      0x008
#define MDIO_LINK       0x00C
#define MDIO_LINKINTRAW 0x010
#define MDIO_LINKINTMASKED 0x014
#define MDIO_USERINTRAW 0x020
#define MDIO_USERINTMASKED 0x024
#define MDIO_USERINTMASKSET 0x028
#define MDIO_USERINTMASKCLR 0x02C
#define MDIO_USERACCESS0 0x030
#define MDIO_USERPHYSEL0 0x034
#define MDIO_USERACCESS1 0x038
#define MDIO_USERPHYSEL1 0x03C

/* MDIO_CTRL bits */
#define MDIO_CTRL_ENABLE    (1 << 6)
#define MDIO_CTRL_PREAMBLE  (1 << 5)
#define MDIO_CTRL_FAULT     (1 << 2)

/* MDIO_USERACCESS bits */
#define MDIO_USERACCESS_GO      (1 << 31)
#define MDIO_USERACCESS_WRITE   (1 << 30)
#define MDIO_USERACCESS_ACK     (1 << 29)
#define MDIO_USERACCESS_REG_SHIFT  21
#define MDIO_USERACCESS_PHY_SHIFT  16
#define MDIO_USERACCESS_DATA_MASK  0xFFFF

/* EMAC registers */
#define EMAC_TXCONTROL     0x004
#define EMAC_RXCONTROL     0x014
#define EMAC_TXINTMASKRAW  0x048
#define EMAC_RXINTMASKRAW  0x068
#define EMAC_MACINDEX      0x0A0
#define EMAC_MACADDRHI     0x0A4
#define EMAC_MACADDRLO     0x0A8
#define EMAC_RXMBPENABLE   0x090
#define EMAC_RXUNICASTSET  0x094
#define EMAC_RXMAXLEN      0x088

typedef struct {
    hw_reg32_t mdio_base;
    hw_reg32_t emac_base;
    uint8_t    phy_addr;
    uint32_t   link_speed;    /* 10 or 100 */
    int        link_up;
} eth_dev_t;

int  eth_init(eth_dev_t *dev, uint32_t mdio_base, uint32_t emac_base, uint8_t phy_addr);
int  mdio_read(eth_dev_t *dev, uint8_t phy, uint8_t reg);
int  mdio_write(eth_dev_t *dev, uint8_t phy, uint8_t reg, uint16_t val);
int  eth_phy_reset(eth_dev_t *dev, gpio_dev_t *gpio, uint8_t pin);
int  eth_phy_config(eth_dev_t *dev);
int  eth_link_check(eth_dev_t *dev);
void eth_get_mac(eth_dev_t *dev, uint8_t mac[6]);
void eth_set_mac(eth_dev_t *dev, const uint8_t mac[6]);

/* Standard MII registers */
#define MII_BMCR       0x00
#define MII_BMSR       0x01
#define MII_PHYID1     0x02
#define MII_PHYID2     0x03
#define MII_ANAR       0x04
#define MII_ANLPAR     0x05
#define MII_ANER       0x06
#define MII_ANNP       0x07
#define MII_CTRL1000   0x09
#define MII_STAT1000   0x0A
#define MII_PHY_CTRL   0x10
#define MII_PHY_STAT   0x11

/* BMCR bits */
#define BMCR_RESET     (1 << 15)
#define BMCR_LOOPBACK  (1 << 14)
#define BMCR_ANEN      (1 << 12)
#define BMCR_SPEED100  (1 << 13)
#define BMCR_CTST      (1 << 11)
#define BMCR_RESTART   (1 << 9)
#define BMCR_PWRDN     (1 << 11)

/* BMSR bits */
#define BMSR_ANEGCAP   (1 << 3)
#define BMSR_LINKST    (1 << 2)
#define BMSR_100TXF    (1 << 8)
#define BMSR_100TXH    (1 << 7)
#define BMSR_10TF      (1 << 6)

#endif /* FIRMWARE_HAL_ETHERNET_H */
