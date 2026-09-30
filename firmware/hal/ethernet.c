/*
 * OMAP3530 EMAC + MDIO driver
 * PHY init pattern from IMX6 Platinum platinum_setup_enet()
 */

#include "ethernet.h"
#include "gpio.h"

int eth_init(eth_dev_t *dev, uint32_t mdio_base, uint32_t emac_base, uint8_t phy_addr) {
    dev->mdio_base = (hw_reg32_t)mdio_base;
    dev->emac_base = (hw_reg32_t)emac_base;
    dev->phy_addr = phy_addr;
    dev->link_up = 0;
    dev->link_speed = 0;

    /* Enable EMAC clocks (should be done in board_early_init_f, verify) */
    hw_reg32_t cm = (hw_reg32_t)CM_BASE;
    reg_set32(cm + CM_FCLKEN1_CORE, (1 << 1));   /* EN_EMAC */
    reg_set32(cm + CM_ICLKEN1_CORE, (1 << 1));

    /* Wait for EMAC clock to become active */
    delay_cycles(1000);

    /* Configure MDIO: enable, preamble, clock divider */
    /* MDIO clock = SYSCLK / (2 * (CLKDIV + 1))
       SYSCLK typically 26MHz, target 2.5MHz MDIO → CLKDIV = 4 */
    reg32_t mdio_ctrl = MDIO_CTRL_ENABLE | MDIO_CTRL_PREAMBLE | (4 << 0);
    reg_write32(dev->mdio_base + MDIO_CTRL, mdio_ctrl);

    /* Wait for MDIO to become ready */
    delay_cycles(500);

    return 0;
}

int mdio_read(eth_dev_t *dev, uint8_t phy, uint8_t reg) {
    hw_reg32_t base = dev->mdio_base;

    /* Wait for MDIO to be idle */
    uint32_t timeout = 100000;
    while ((reg_read32(base + MDIO_USERACCESS0) & MDIO_USERACCESS_GO) && timeout--)
        ;

    /* Issue read command */
    reg32_t access = MDIO_USERACCESS_GO
                   | ((reg & 0x1F) << MDIO_USERACCESS_REG_SHIFT)
                   | ((phy & 0x1F) << MDIO_USERACCESS_PHY_SHIFT);

    reg_write32(base + MDIO_USERACCESS0, access);

    /* Wait for completion */
    timeout = 100000;
    while ((reg_read32(base + MDIO_USERACCESS0) & MDIO_USERACCESS_GO) && timeout--)
        ;

    reg32_t result = reg_read32(base + MDIO_USERACCESS0);
    if (!(result & MDIO_USERACCESS_ACK))
        return -1;  /* No ACK from PHY */

    return (int)(result & MDIO_USERACCESS_DATA_MASK);
}

int mdio_write(eth_dev_t *dev, uint8_t phy, uint8_t reg, uint16_t val) {
    hw_reg32_t base = dev->mdio_base;

    uint32_t timeout = 100000;
    while ((reg_read32(base + MDIO_USERACCESS0) & MDIO_USERACCESS_GO) && timeout--)
        ;

    reg32_t access = MDIO_USERACCESS_GO
                   | MDIO_USERACCESS_WRITE
                   | ((reg & 0x1F) << MDIO_USERACCESS_REG_SHIFT)
                   | ((phy & 0x1F) << MDIO_USERACCESS_PHY_SHIFT)
                   | (val & MDIO_USERACCESS_DATA_MASK);

    reg_write32(base + MDIO_USERACCESS0, access);

    timeout = 100000;
    while ((reg_read32(base + MDIO_USERACCESS0) & MDIO_USERACCESS_GO) && timeout--)
        ;

    return 0;
}

/*
 * eth_phy_reset — PHY reset sequence
 * Modeled on IMX6 Platinum platinum_setup_enet():
 *   1. Configure PHY reset GPIO
 *   2. Assert reset (low) while reconfiguring pinmux
 *   3. mdelay(10) while PHY in reset
 *   4. Release reset (high)
 *   5. udelay(100) for PHY startup
 */
int eth_phy_reset(eth_dev_t *dev, gpio_dev_t *gpio, uint8_t pin) {
    /* Assert PHY reset */
    gpio_write(gpio, pin, 0);

    /* Reconfigure EMAC pinmux while PHY is in reset
       (mirrors IMX6: "Reconfigure enet muxing while PHY is in reset") */
    /* Already done in board_early_init_f via pinmux table */

    /* Wait 10ms while PHY in reset (IMX6 Platinum: mdelay(10)) */
    delay_cycles(CPU_CLK_HZ / 100);  /* ~10ms */

    /* Release PHY reset */
    gpio_write(gpio, pin, 1);

    /* Wait 100µs for PHY to come out of reset (IMX6 Platinum: udelay(100)) */
    delay_cycles(CPU_CLK_HZ / 10000);  /* ~100µs */

    return 0;
}

int eth_phy_config(eth_dev_t *dev) {
    int val;

    /* Read PHY ID */
    val = mdio_read(dev, dev->phy_addr, MII_PHYID1);
    if (val < 0) return -1;
    uint16_t phy_id1 = (uint16_t)val;

    val = mdio_read(dev, dev->phy_addr, MII_PHYID2);
    if (val < 0) return -1;
    uint16_t phy_id2 = (uint16_t)val;

    /* Reset PHY (like IMX6: generic phydev->drv->config) */
    mdio_write(dev, dev->phy_addr, MII_BMCR, BMCR_RESET);

    /* Wait for reset to complete */
    uint32_t timeout = 500000;
    do {
        val = mdio_read(dev, dev->phy_addr, MII_BMCR);
    } while ((val >= 0) && (val & BMCR_RESET) && timeout--);

    /* Enable auto-negotiation */
    mdio_write(dev, dev->phy_addr, MII_BMCR, BMCR_ANEN | BMCR_RESTART);

    return 0;
}

int eth_link_check(eth_dev_t *dev) {
    int val = mdio_read(dev, dev->phy_addr, MII_BMSR);
    if (val < 0) {
        dev->link_up = 0;
        return -1;
    }

    dev->link_up = (val & BMSR_LINKST) ? 1 : 0;

    if (dev->link_up) {
        /* Determine speed from ANLPAR or PHY-specific register */
        int lpar = mdio_read(dev, dev->phy_addr, MII_ANLPAR);
        if (lpar > 0) {
            dev->link_speed = (lpar & (BMSR_100TXF >> 8)) ? 100 : 10;
        }
    }

    return dev->link_up;
}

void eth_get_mac(eth_dev_t *dev, uint8_t mac[6]) {
    uint32_t lo = reg_read32(dev->emac_base + EMAC_MACADDRLO);
    uint32_t hi = reg_read32(dev->emac_base + EMAC_MACADDRHI);

    mac[0] = (hi >> 0) & 0xFF;
    mac[1] = (hi >> 8) & 0xFF;
    mac[2] = (lo >> 0) & 0xFF;
    mac[3] = (lo >> 8) & 0xFF;
    mac[4] = (lo >> 16) & 0xFF;
    mac[5] = (lo >> 24) & 0xFF;
}

void eth_set_mac(eth_dev_t *dev, const uint8_t mac[6]) {
    uint32_t lo = ((uint32_t)mac[2] << 0) | ((uint32_t)mac[3] << 8)
                | ((uint32_t)mac[4] << 16) | ((uint32_t)mac[5] << 24);
    uint32_t hi = ((uint32_t)mac[0] << 0) | ((uint32_t)mac[1] << 8);

    reg_write32(dev->emac_base + EMAC_MACADDRHI, hi);
    reg_write32(dev->emac_base + EMAC_MACADDRLO, lo);
}
