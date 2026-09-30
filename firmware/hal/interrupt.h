/*
 * HAL — Interrupt Controller driver for OMAP3530 AINTC
 * 96 interrupt lines, mapped to ARM IRQ/FIQ
 */

#ifndef FIRMWARE_HAL_INTERRUPT_H
#define FIRMWARE_HAL_INTERRUPT_H

#include "../common/types.h"
#include "../common/platform.h"

#define INTC_NUM_IRQS       96
#define INTC_NUM_MIR_REGS   3    /* 3 × 32 = 96 */

typedef void (*irq_handler_t)(uint8_t irq_num);

void    intc_init(void);
void    intc_enable_irq(uint8_t irq_num);
void    intc_disable_irq(uint8_t irq_num);
void    intc_set_irq_handler(uint8_t irq_num, irq_handler_t handler);
uint8_t intc_get_active_irq(void);
void    intc_ack_irq(void);
void    intc_enable(void);
void    intc_disable(void);

/* Called from ARM IRQ exception handler */
void intc_handle_irq(void);

#endif /* FIRMWARE_HAL_INTERRUPT_H */
