/*
 * HAL — UART driver for OMAP3530 (NS16550A-compatible)
 */

#include "uart.h"

void uart_init(uart_dev_t *dev, uint32_t base, uint32_t clock_hz) {
    dev->base = (hw_reg32_t)base;
    dev->clock_hz = clock_hz;
}

void uart_configure(uart_dev_t *dev, uint32_t baud, uint8_t data_bits, uint8_t parity, uint8_t stop_bits) {
    hw_reg32_t base = dev->base;

    /* Switch to UART mode (disable IrDA / disable modem) */
    reg_write32(base + UART_MDR1, 0x07);   /* Disable UART */
    delay_cycles(100);

    /* Reset TX/RX FIFOs and enable FIFO mode */
    reg_write32(base + UART_FCR, UART_FCR_FIFO_EN | UART_FCR_RXSR | UART_FCR_TXSR);
    delay_cycles(10);

    /* Set DLAB to access divisor registers */
    reg32_t lcr = 0;
    switch (data_bits) {
        case 5:  lcr |= 0x00; break;
        case 6:  lcr |= 0x01; break;
        case 7:  lcr |= 0x02; break;
        case 8:
        default: lcr |= 0x03; break;
    }
    switch (parity) {
        case 0: break;                    /* No parity */
        case 1: lcr |= (1 << 3); break;  /* Odd parity */
        case 2: lcr |= (3 << 3); break;  /* Even parity */
    }
    if (stop_bits == 2)
        lcr |= (1 << 2);

    /* Set DLAB, write divisor, clear DLAB */
    reg_write32(base + UART_LCR, lcr | UART_LCR_DLAB);

    uint16_t divisor = (uint16_t)(dev->clock_hz / (16 * baud));
    reg_write32(base + UART_DLL, divisor & 0xFF);
    reg_write32(base + UART_DLH, (divisor >> 8) & 0xFF);

    /* Clear DLAB — restore normal register access */
    reg_write32(base + UART_LCR, lcr);

    /* No flow control, no interrupts */
    reg_write32(base + UART_IER, 0x00);
    reg_write32(base + UART_MCR, 0x00);

    /* Enable FIFOs with 8-byte trigger */
    reg_write32(base + UART_FCR, UART_FCR_FIFO_EN | (0x3 << 6));

    /* Re-enable UART in 16x mode */
    reg_write32(base + UART_MDR1, 0x00);
}

void uart_putc(uart_dev_t *dev, char c) {
    hw_reg32_t base = dev->base;
    /* Wait for TX holding register empty */
    while (!(reg_read32(base + UART_LSR) & UART_LSR_THRE))
        ;
    reg_write32(base + UART_THR, (reg32_t)c);
}

char uart_getc(uart_dev_t *dev) {
    hw_reg32_t base = dev->base;
    /* Wait for data ready */
    while (!(reg_read32(base + UART_LSR) & UART_LSR_DR))
        ;
    return (char)(reg_read32(base + UART_RBR) & 0xFF);
}

int uart_try_getc(uart_dev_t *dev) {
    hw_reg32_t base = dev->base;
    if (reg_read32(base + UART_LSR) & UART_LSR_DR)
        return (int)(reg_read32(base + UART_RBR) & 0xFF);
    return -1;
}

void uart_puts(uart_dev_t *dev, const char *s) {
    while (*s) {
        if (*s == '\n')
            uart_putc(dev, '\r');
        uart_putc(dev, *s++);
    }
}

void uart_put_hex_byte(uart_dev_t *dev, uint8_t val) {
    static const char hex[] = "0123456789ABCDEF";
    uart_putc(dev, hex[(val >> 4) & 0xF]);
    uart_putc(dev, hex[val & 0xF]);
}

void uart_put_hex(uart_dev_t *dev, uint32_t val) {
    uart_puts(dev, "0x");
    uart_put_hex_byte(dev, (val >> 24) & 0xFF);
    uart_put_hex_byte(dev, (val >> 16) & 0xFF);
    uart_put_hex_byte(dev, (val >> 8) & 0xFF);
    uart_put_hex_byte(dev, val & 0xFF);
}

void uart_flush(uart_dev_t *dev) {
    hw_reg32_t base = dev->base;
    while (!(reg_read32(base + UART_LSR) & UART_LSR_TEMT))
        ;
}
