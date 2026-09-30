/*
 * Driver — OMAP3530 SDRAM Controller (SDRC)
 * Initializes MT48H32M16LF-7 (256MB mobile SDRAM) from BOM
 * Clock: 266 MHz DDR from clock-tree.json
 */

#ifndef FIRMWARE_DRIVERS_SDRAM_H
#define FIRMWARE_DRIVERS_SDRAM_H

#include "../common/types.h"
#include "../common/platform.h"

int sdram_init(void);
int sdram_test(void);

#endif /* FIRMWARE_DRIVERS_SDRAM_H */
