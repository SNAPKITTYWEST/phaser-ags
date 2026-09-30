/*
 * HAL — UART driver for OMAP3530 (NS16550A-compatible)
 * Supports UART0 (console) and UART1 (debug)
 */

#ifndef FIRMWARE_HAL_UART_H
#define FIRMWARE_HAL_UART_H

#include "../common/types.h"
#include "../common/platform.h"

typedef struct {
    hw_reg32_t base;
    uint32_t   clock_hz;
} uart_dev_t;

void uart_init(uart_dev_t *dev, uint32_t base, uint32_t clock_hz);
void uart_configure(uart_dev_t *dev, uint32_t baud, uint8_t data_bits, uint8_t parity, uint8_t stop_bits);
void uart_putc(uart_dev_t *dev, char c);
char uart_getc(uart_dev_t *dev);
int  uart_try_getc(uart_dev_t *dev);
void uart_puts(uart_dev_t *dev, const char *s);
void uart_put_hex(uart_dev_t *dev, uint32_t val);
void uart_put_hex_byte(uart_dev_t *dev, uint8_t val);
void uart_flush(uart_dev_t *dev);

#endif /* FIRMWARE_HAL_UART_H */
