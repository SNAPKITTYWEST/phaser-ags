/*
 * HAL — OMAP3530 Clock and Power initialization
 * Configures PLLs and enables peripheral clocks from 26MHz reference
 * PLL config: 26MHz × 23 = 598MHz CPU, 26MHz × 10 = 260MHz DDR
 */

#ifndef FIRMWARE_HAL_CLOCK_H
#define FIRMWARE_HAL_CLOCK_H

#include "../common/types.h"
#include "../common/platform.h"

int  clock_init(void);
void clock_enable_uart(void);
void clock_enable_gpio(void);
void clock_enable_gptimer(void);
void clock_enable_gpmc(void);
void clock_enable_sdrc(void);
void power_seq_wait(void);

#endif /* FIRMWARE_HAL_CLOCK_H */
