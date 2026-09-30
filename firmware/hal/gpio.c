/*
 * HAL — GPIO driver for OMAP3530
 */

#include "gpio.h"

static hw_reg32_t gpio_bank_base(uint8_t bank) {
    switch (bank) {
        case 1: return (hw_reg32_t)GPIO1_BASE;
        case 2: return (hw_reg32_t)GPIO2_BASE;
        case 3: return (hw_reg32_t)GPIO3_BASE;
        case 4: return (hw_reg32_t)GPIO4_BASE;
        case 5: return (hw_reg32_t)GPIO5_BASE;
        case 6: return (hw_reg32_t)GPIO6_BASE;
        default: return (hw_reg32_t)GPIO1_BASE;
    }
}

void gpio_init(gpio_dev_t *dev, uint8_t bank) {
    dev->bank = bank;
    dev->base = gpio_bank_base(bank);

    /* Enable GPIO module (auto-idle off for reliability) */
    reg_write32(dev->base + GPIO_SYSCONFIG, 0x04);  /* Smart idle */
    delay_cycles(50);

    /* Wait for reset to complete */
    while (!(reg_read32(dev->base + GPIO_SYSSTATUS) & 0x01))
        ;

    /* Disable all GPIO interrupts */
    reg_write32(dev->base + GPIO_IRQENABLE1, 0x00);
    reg_write32(dev->base + GPIO_LEVELDETECT0, 0x00);
    reg_write32(dev->base + GPIO_LEVELDETECT1, 0x00);
    reg_write32(dev->base + GPIO_RISINGDETECT, 0x00);
    reg_write32(dev->base + GPIO_FALLINGDETECT, 0x00);
}

void gpio_set_dir(gpio_dev_t *dev, uint8_t pin, gpio_dir_t dir) {
    reg32_t mask = (1UL << pin);
    if (dir == GPIO_DIR_INPUT)
        reg_set32(dev->base + GPIO_OE, mask);      /* 1 = input */
    else
        reg_clr32(dev->base + GPIO_OE, mask);      /* 0 = output */
}

void gpio_set_output(gpio_dev_t *dev, uint8_t pin) {
    gpio_set_dir(dev, pin, GPIO_DIR_OUTPUT);
}

void gpio_set_input(gpio_dev_t *dev, uint8_t pin) {
    gpio_set_dir(dev, pin, GPIO_DIR_INPUT);
}

void gpio_write(gpio_dev_t *dev, uint8_t pin, int value) {
    reg32_t mask = (1UL << pin);
    if (value)
        reg_write32(dev->base + GPIO_SETDATAOUT, mask);
    else
        reg_write32(dev->base + GPIO_CLEARDATAOUT, mask);
}

int gpio_read(gpio_dev_t *dev, uint8_t pin) {
    return (reg_read32(dev->base + GPIO_DATAIN) >> pin) & 1;
}

void gpio_toggle(gpio_dev_t *dev, uint8_t pin) {
    int val = gpio_read(dev, pin);
    gpio_write(dev, pin, !val);
}

void gpio_set_irq_edge(gpio_dev_t *dev, uint8_t pin, gpio_irq_edge_t edge) {
    reg32_t mask = (1UL << pin);

    /* Clear all edge/level detection for this pin first */
    reg_clr32(dev->base + GPIO_LEVELDETECT0, mask);
    reg_clr32(dev->base + GPIO_LEVELDETECT1, mask);
    reg_clr32(dev->base + GPIO_RISINGDETECT, mask);
    reg_clr32(dev->base + GPIO_FALLINGDETECT, mask);

    switch (edge) {
        case GPIO_IRQ_EDGE_RISING:
            reg_set32(dev->base + GPIO_RISINGDETECT, mask);
            break;
        case GPIO_IRQ_EDGE_FALLING:
            reg_set32(dev->base + GPIO_FALLINGDETECT, mask);
            break;
        case GPIO_IRQ_EDGE_BOTH:
            reg_set32(dev->base + GPIO_RISINGDETECT, mask);
            reg_set32(dev->base + GPIO_FALLINGDETECT, mask);
            break;
        case GPIO_IRQ_LEVEL_HIGH:
            reg_set32(dev->base + GPIO_LEVELDETECT0, mask);
            break;
        case GPIO_IRQ_LEVEL_LOW:
            reg_set32(dev->base + GPIO_LEVELDETECT1, mask);
            break;
        default:
            break;
    }

    /* Enable IRQ for this pin */
    if (edge != GPIO_IRQ_EDGE_NONE)
        reg_set32(dev->base + GPIO_IRQENABLE1, mask);
}

void gpio_clear_irq(gpio_dev_t *dev, uint8_t pin) {
    reg_write32(dev->base + GPIO_IRQSTATUS1, (1UL << pin));
}

uint32_t gpio_get_irq_status(gpio_dev_t *dev) {
    return reg_read32(dev->base + GPIO_IRQSTATUS1);
}
