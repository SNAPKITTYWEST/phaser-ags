/*
 * HAL — Timer driver for OMAP3530 GP Timers
 * Uses 26 MHz reference clock
 */

#ifndef FIRMWARE_HAL_TIMER_H
#define FIRMWARE_HAL_TIMER_H

#include "../common/types.h"
#include "../common/platform.h"

typedef struct {
    hw_reg32_t base;
    uint32_t   clock_hz;
} timer_dev_t;

void     timer_init(timer_dev_t *dev, uint32_t base, uint32_t clock_hz);
void     timer_start(timer_dev_t *dev);
void     timer_stop(timer_dev_t *dev);
void     timer_set_period_ms(timer_dev_t *dev, uint32_t ms);
void     timer_set_period_us(timer_dev_t *dev, uint32_t us);
uint32_t timer_get_count(timer_dev_t *dev);
void     timer_reset(timer_dev_t *dev);
int      timer_expired(timer_dev_t *dev);
void     timer_clear_irq(timer_dev_t *dev);
void     timer_enable_irq(timer_dev_t *dev);
void     timer_delay_ms(timer_dev_t *dev, uint32_t ms);
void     timer_delay_us(timer_dev_t *dev, uint32_t us);

#endif /* FIRMWARE_HAL_TIMER_H */
