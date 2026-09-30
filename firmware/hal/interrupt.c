/*
 * HAL — Interrupt Controller driver for OMAP3530 AINTC
 */

#include "interrupt.h"

static irq_handler_t irq_handlers[INTC_NUM_IRQS];

void intc_init(void) {
    hw_reg32_t base = (hw_reg32_t)INTC_BASE;

    /* Soft reset */
    reg_write32(base + INTC_SYSCONFIG, 0x02);
    delay_cycles(100);
    while (!(reg_read32(base + INTC_SYSSTATUS) & 0x01))
        ;

    /* Mask all interrupts */
    for (int i = 0; i < INTC_NUM_MIR_REGS; i++) {
        reg_write32(base + INTC_MIR_SET(i), 0xFFFFFFFF);
    }

    /* Clear all handler pointers */
    for (int i = 0; i < INTC_NUM_IRQS; i++) {
        irq_handlers[i] = (irq_handler_t)0;
    }

    /* No priority threshold (all priorities pass) */
    reg_write32(base + INTC_THRESHOLD, 0x00);

    /* Enable protection (only privileged access) */
    reg_write32(base + INTC_PROTECTION, 0x01);
}

void intc_enable_irq(uint8_t irq_num) {
    hw_reg32_t base = (hw_reg32_t)INTC_BASE;
    int bank = irq_num / 32;
    int bit  = irq_num % 32;
    reg_write32(base + INTC_MIR_CLEAR(bank), (1UL << bit));
}

void intc_disable_irq(uint8_t irq_num) {
    hw_reg32_t base = (hw_reg32_t)INTC_BASE;
    int bank = irq_num / 32;
    int bit  = irq_num % 32;
    reg_write32(base + INTC_MIR_SET(bank), (1UL << bit));
}

void intc_set_irq_handler(uint8_t irq_num, irq_handler_t handler) {
    if (irq_num < INTC_NUM_IRQS)
        irq_handlers[irq_num] = handler;
}

uint8_t intc_get_active_irq(void) {
    hw_reg32_t base = (hw_reg32_t)INTC_BASE;
    return (uint8_t)(reg_read32(base + INTC_SIR_IRQ) & 0x7F);
}

void intc_ack_irq(void) {
    hw_reg32_t base = (hw_reg32_t)INTC_BASE;
    reg_write32(base + INTC_CONTROL, 0x01);
}

void intc_enable(void) {
    __asm__ volatile("cpsie i" ::: "memory");
}

void intc_disable(void) {
    __asm__ volatile("cpsid i" ::: "memory");
}

void intc_handle_irq(void) {
    uint8_t irq = intc_get_active_irq();
    if (irq < INTC_NUM_IRQS && irq_handlers[irq]) {
        irq_handlers[irq](irq);
    }
    intc_ack_irq();
}
