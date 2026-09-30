/*
 * OMAP3530 Board Init — Phaser AGS
 * Pattern: R8A7740 armadillo-800eva
 */

#include "board.h"
#include "../hal/uart.h"
#include "../hal/gpio.h"
#include "../hal/timer.h"
#include "../hal/interrupt.h"
#include "../hal/clock.h"
#include "../hal/pinmux.h"
#include "../hal/i2c.h"
#include "../drivers/sdram.h"

/* ---- Console and peripherals ---- */
static uart_dev_t console;
static gpio_dev_t gpio1;
static timer_dev_t systimer;
static i2c_dev_t i2c1;

/* ---- OMAP3530 Pad Configuration Table ----
 * Format: { offset, value }
 * offset = register offset from PADCONF_BASE (0x48002000)
 * value = MUX_MODE | PULL | INPUT_ENABLE
 *
 * OMAP3530 CONTROL_PADCONF_xxx offsets:
 *   UART1: 0x0C8 (tx), 0x0CA (rx)
 *   UART2: 0x0D0 (tx), 0x0D2 (rx)
 *   I2C1:  0x18C (scl), 0x18E (sda)
 *   MMC1:  0x114-0x12C (cmd, clk, dat0-7)
 *   GPIO:  various
 *   Ethernet (EMAC): 0x040-0x06C
 */
static const pad_config_t phaser_ags_padconf[] = {
    /* UART1 (console) — Mode0, pull-up, input enable on RX */
    { 0x00C8, MUX_MODE0 | PULL_UP },                    /* uart1_tx */
    { 0x00CA, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* uart1_rx */

    /* UART2 (debug) */
    { 0x00D0, MUX_MODE0 | PULL_UP },                    /* uart2_tx */
    { 0x00D2, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* uart2_rx */

    /* I2C1 — to TPS65950 PMIC */
    { 0x018C, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* i2c1_scl */
    { 0x018E, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* i2c1_sda */

    /* MMC1 */
    { 0x0114, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* mmc1_cmd */
    { 0x0116, MUX_MODE0 | PULL_UP },                    /* mmc1_clk */
    { 0x0118, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* mmc1_dat0 */
    { 0x011A, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* mmc1_dat1 */
    { 0x011C, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* mmc1_dat2 */
    { 0x011E, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* mmc1_dat3 */

    /* Ethernet (EMAC) — Mode0 */
    { 0x0040, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* emac_tx_clk */
    { 0x0042, MUX_MODE0 | PULL_UP },                    /* emac_tx_en */
    { 0x0044, MUX_MODE0 | PULL_UP },                    /* emac_txd0 */
    { 0x0046, MUX_MODE0 | PULL_UP },                    /* emac_txd1 */
    { 0x0048, MUX_MODE0 | PULL_UP },                    /* emac_txd2 */
    { 0x004A, MUX_MODE0 | PULL_UP },                    /* emac_txd3 */
    { 0x004C, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* emac_rx_clk */
    { 0x004E, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* emac_rx_dv */
    { 0x0050, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* emac_rxd0 */
    { 0x0052, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* emac_rxd1 */
    { 0x0054, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* emac_rxd2 */
    { 0x0056, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* emac_rxd3 */
    { 0x0058, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* emac_crs */
    { 0x005A, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* emac_col */
    { 0x005C, MUX_MODE0 | PULL_UP | INPUT_ENABLE },     /* emac_mdio */
    { 0x005E, MUX_MODE0 | PULL_UP },                    /* emac_mdc */

    /* GPIO — status LED, PHY reset */
    { 0x006C, MUX_MODE4 | PULL_UP },                    /* gpio1[8] — status LED */
    { 0x006E, MUX_MODE4 | PULL_UP },                    /* gpio1[9] — PHY reset */
};

#define NUM_PADCONF (sizeof(phaser_ags_padconf) / sizeof(phaser_ags_padconf[0]))

/* ---- TPS65950 PMIC I2C address ---- */
#define TPS65950_I2C_ADDR  0x48

/* ---- Board info ---- */
#define BOARD_NAME    "Phaser AGS Universal"
#define BOARD_ID      0x50414753  /* "PAGS" */

/*
 * board_early_init_f — runs before DRAM is fully up
 * Like R8A7740: MSTPCR clock gating + GPIO pinmux + IICCR
 */
int board_early_init_f(void) {
    /* 1. Enable peripheral clocks (mirrors R8A7740 clrbits_le32 MSTPCR) */
    clock_enable_uart();
    clock_enable_gpio();
    clock_enable_gptimer();
    clock_enable_gpmc();
    clock_enable_sdrc();

    /* Enable I2C1 clock */
    hw_reg32_t cm = (hw_reg32_t)CM_BASE;
    reg_set32(cm + CM_FCLKEN1_CORE, (1 << 15));   /* EN_I2C1 */
    reg_set32(cm + CM_ICLKEN1_CORE, (1 << 15));

    /* Enable EMAC clock */
    reg_set32(cm + CM_FCLKEN1_CORE, (1 << 1));     /* EN_EMAC */
    reg_set32(cm + CM_ICLKEN1_CORE, (1 << 1));

    /* Wait for clocks active */
    delay_cycles(500);

    /* 2. Configure pinmux (mirrors R8A7740 r8a7740_pinmux_init) */
    pinmux_init(phaser_ags_padconf, NUM_PADCONF);

    return 0;
}

/*
 * board_init — runs after DRAM init, sets up GPIO/I2C/Ethernet
 * Like R8A7740 board_init: gpio_request, gpio_direction_output, GETHER enable
 */
int board_init(void) {
    /* 1. UART console */
    uart_init(&console, UART0_BASE, REF_CLK_HZ);
    uart_configure(&console, 115200, 8, 0, 1);
    uart_puts(&console, "\r\n[BOARD] ");
    uart_puts(&console, BOARD_NAME);
    uart_puts(&console, "\r\n");

    /* 2. GPIO init — status LED + PHY reset */
    gpio_init(&gpio1, 1);

    /* Status LED on GPIO1[8] (mirrors R8A7740 GPIO_PORT18 PHY_RST) */
    gpio_set_output(&gpio1, 8);
    gpio_write(&gpio1, 8, 1);     /* LED on = boot in progress */

    /* PHY reset on GPIO1[9] — hold low then release */
    gpio_set_output(&gpio1, 9);
    gpio_write(&gpio1, 9, 0);     /* Assert reset */
    delay_cycles(CPU_CLK_HZ / 100);  /* 10ms */
    gpio_write(&gpio1, 9, 1);     /* Release reset */
    delay_cycles(CPU_CLK_HZ / 50);   /* 20ms PHY startup */

    /* 3. System timer */
    timer_init(&systimer, GPTIMER2_BASE, REF_CLK_HZ);

    /* 4. Interrupt controller */
    intc_init();

    /* 5. I2C1 — PMIC (TPS65950) */
    i2c_init(&i2c1, I2C1_BASE, REF_CLK_HZ, 0x01);

    /* Read PMIC chip ID to verify communication */
    uint8_t pmic_id = 0;
    if (i2c_reg_read(&i2c1, TPS65950_I2C_ADDR, 0x00, &pmic_id) == 0) {
        uart_puts(&console, "[BOARD] PMIC ID: 0x");
        uart_put_hex_byte(&console, pmic_id);
        uart_puts(&console, "\r\n");
    } else {
        uart_puts(&console, "[BOARD] PMIC I2C read failed\r\n");
    }

    /* 6. Verify SDRAM */
    if (sdram_test() != 0) {
        uart_puts(&console, "[BOARD] SDRAM test FAILED\r\n");
        return -1;
    }
    uart_puts(&console, "[BOARD] SDRAM OK\r\n");

    return 0;
}

/*
 * board_late_init — environment, boot source, late GPIO
 * Like R8A7740 board_late_init
 */
int board_late_init(void) {
    uart_puts(&console, "[BOARD] Late init\r\n");

    /* Blink LED 3× to indicate successful init */
    for (int i = 0; i < 3; i++) {
        gpio_write(&gpio1, 8, 1);
        timer_delay_ms(&systimer, 100);
        gpio_write(&gpio1, 8, 0);
        timer_delay_ms(&systimer, 100);
    }
    gpio_write(&gpio1, 8, 1);   /* LED on = ready */

    /* Print memory layout */
    uart_puts(&console, "[BOARD] Memory map:\r\n");
    uart_puts(&console, "  SRAM:   0x00000000 (128KB)\r\n");
    uart_puts(&console, "  DRAM:   0x30000000 (256MB)\r\n");
    uart_puts(&console, "  NOR:    0x08000000 (256MB)\r\n");
    uart_puts(&console, "  NAND:   0x40000000 (512MB)\r\n");

    return 0;
}

/*
 * board_reset — like R8A7740 reset_cpu
 */
void board_reset(void) {
    uart_puts(&console, "[BOARD] Resetting...\r\n");
    uart_flush(&console);

    /* OMAP3530 global warm reset via PRM */
    hw_reg32_t prm = (hw_reg32_t)PRM_BASE;
    reg_write32(prm + 0x08, 0x02);    /* PRM_RSTCTRL.RST_GLOBAL_WARM */

    /* If that didn't work, try cold reset */
    delay_cycles(10000);
    reg_write32(prm + 0x08, 0x01);    /* PRM_RSTCTRL.RST_GLOBAL_COLD */

    while(1);
}
