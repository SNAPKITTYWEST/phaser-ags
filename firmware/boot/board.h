/*
 * OMAP3530 Board Init — Phaser AGS board-specific configuration
 * Modeled on R8A7740 armadillo-800eva board init pattern:
 *   - board_early_init_f: clock gating, pinmux, peripheral enables
 *   - board_init: GPIO setup, Ethernet, I2C PMIC
 *   - board_late_init: environment, boot source selection
 */

#ifndef FIRMWARE_BOOT_BOARD_H
#define FIRMWARE_BOOT_BOARD_H

#include "../common/types.h"
#include "../common/platform.h"

int board_early_init_f(void);
int board_init(void);
int board_late_init(void);
void board_reset(void);

#endif /* FIRMWARE_BOOT_BOARD_H */
