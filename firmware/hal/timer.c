/*
 * HAL — Timer driver for OMAP3530 GP Timers
 */

#include "timer.h"

void timer_init(timer_dev_t *dev, uint32_t base, uint32_t clock_hz) {
    dev->base = (hw_reg32_t)base;
    dev->clock_hz = clock_hz;

    timer_stop(dev);

    /* Soft reset */
    reg_write32(dev->base + GPTIMER_TIOCP_CFG, 0x02);
    delay_cycles(50);
    while (!(reg_read32(dev->base + GPTIMER_TISTAT) & 0x01))
        ;

    /* Clear any pending IRQ */
    reg_write32(dev->base + GPTIMER_TISR, 0x07);

    /* No prescaler (1:1 from source clock) */
    reg_write32(dev->base + GPTIMER_TCLR, 0x00);

    /* Start from 0 */
    reg_write32(dev->base + GPTIMER_TCRR, 0x00000000);
    reg_write32(dev->base + GPTIMER_TLDR, 0x00000000);
}

void timer_start(timer_dev_t *dev) {
    reg_set32(dev->base + GPTIMER_TCLR, GPTIMER_TCLR_ST);
}

void timer_stop(timer_dev_t *dev) {
    reg_clr32(dev->base + GPTIMER_TCLR, GPTIMER_TCLR_ST);
}

void timer_set_period_ms(timer_dev_t *dev, uint32_t ms) {
    uint32_t ticks = (dev->clock_hz / 1000UL) * ms;
    reg32_t load = 0xFFFFFFFFUL - ticks + 1;
    reg_write32(dev->base + GPTIMER_TLDR, load);
    reg_write32(dev->base + GPTIMER_TCRR, load);
    /* Enable auto-reload */
    reg_set32(dev->base + GPTIMER_TCLR, GPTIMER_TCLR_AR);
}

void timer_set_period_us(timer_dev_t *dev, uint32_t us) {
    uint32_t ticks = (dev->clock_hz / 1000000UL) * us;
    reg32_t load = 0xFFFFFFFFUL - ticks + 1;
    reg_write32(dev->base + GPTIMER_TLDR, load);
    reg_write32(dev->base + GPTIMER_TCRR, load);
    reg_set32(dev->base + GPTIMER_TCLR, GPTIMER_TCLR_AR);
}

uint32_t timer_get_count(timer_dev_t *dev) {
    return reg_read32(dev->base + GPTIMER_TCRR);
}

void timer_reset(timer_dev_t *dev) {
    reg_write32(dev->base + GPTIMER_TCRR, 0x00000000);
    /* Trigger reload on next overflow */
    reg_write32(dev->base + GPTIMER_TTGR, 0x00);
}

int timer_expired(timer_dev_t *dev) {
    return (reg_read32(dev->base + GPTIMER_TISR) & 0x01) != 0;
}

void timer_clear_irq(timer_dev_t *dev) {
    reg_write32(dev->base + GPTIMER_TISR, 0x07);
}

void timer_enable_irq(timer_dev_t *dev) {
    reg_write32(dev->base + GPTIMER_TIER, 0x01);   /* Overflow IRQ */
    reg_write32(dev->base + GPTIMER_TWER, 0x01);   /* Wake-up on overflow */
}

void timer_delay_ms(timer_dev_t *dev, uint32_t ms) {
    timer_stop(dev);
    timer_set_period_ms(dev, ms);
    timer_clear_irq(dev);
    timer_start(dev);
    while (!timer_expired(dev))
        ;
    timer_stop(dev);
    timer_clear_irq(dev);
}

void timer_delay_us(timer_dev_t *dev, uint32_t us) {
    timer_stop(dev);
    timer_set_period_us(dev, us);
    timer_clear_irq(dev);
    timer_start(dev);
    while (!timer_expired(dev))
        ;
    timer_stop(dev);
    timer_clear_irq(dev);
}
