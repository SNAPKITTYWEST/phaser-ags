/*
 * HAL — GPIO driver for OMAP3530
 * Each GPIO bank has 32 pins. OMAP3530 has 6 banks (192 pins total).
 */

#ifndef FIRMWARE_HAL_GPIO_H
#define FIRMWARE_HAL_GPIO_H

#include "../common/types.h"
#include "../common/platform.h"

typedef enum {
    GPIO_DIR_INPUT  = 0,
    GPIO_DIR_OUTPUT = 1
} gpio_dir_t;

typedef enum {
    GPIO_IRQ_EDGE_NONE   = 0,
    GPIO_IRQ_EDGE_RISING = 1,
    GPIO_IRQ_EDGE_FALLING = 2,
    GPIO_IRQ_EDGE_BOTH   = 3,
    GPIO_IRQ_LEVEL_HIGH  = 4,
    GPIO_IRQ_LEVEL_LOW   = 5
} gpio_irq_edge_t;

typedef struct {
    hw_reg32_t base;
    uint8_t    bank;
} gpio_dev_t;

void    gpio_init(gpio_dev_t *dev, uint8_t bank);
void    gpio_set_dir(gpio_dev_t *dev, uint8_t pin, gpio_dir_t dir);
void    gpio_set_output(gpio_dev_t *dev, uint8_t pin);
void    gpio_set_input(gpio_dev_t *dev, uint8_t pin);
void    gpio_write(gpio_dev_t *dev, uint8_t pin, int value);
int     gpio_read(gpio_dev_t *dev, uint8_t pin);
void    gpio_toggle(gpio_dev_t *dev, uint8_t pin);
void    gpio_set_irq_edge(gpio_dev_t *dev, uint8_t pin, gpio_irq_edge_t edge);
void    gpio_clear_irq(gpio_dev_t *dev, uint8_t pin);
uint32_t gpio_get_irq_status(gpio_dev_t *dev);

#endif /* FIRMWARE_HAL_GPIO_H */
