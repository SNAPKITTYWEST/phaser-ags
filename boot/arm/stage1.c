/* ARM Universal Bootloader Stage 1 - Reset to DRAM Init */
#include "common.h"

#define STACK_BASE 0x20010000
#define STACK_SIZE 0x4000

void __attribute__((section(".vectors"))) vectors[] = {
    (void*)STACK_BASE,
    (void*)reset_handler,
};

void reset_handler(void) {
    asm volatile("cpsid i");
    asm volatile("ldr sp, =0x20010000");

    clock_init();
    sram_init();
    dram_init();
    gpio_init();
    uart_init(115200);
    uart_puts("Stage 1 Bootloader ARM\r\n");

    int boot_source = detect_boot_source();
    void (*stage2_entry)(void) = (void*)(0x30000000);

    if (validate_stage2(stage2_entry)) {
        uart_puts("Loading Stage 2...\r\n");
        stage2_entry();
    } else {
        uart_puts("Stage 2 validation failed\r\n");
        while(1);
    }
}

void clock_init(void) { }
void sram_init(void) { extern char _bss_start, _bss_end; char *p = &_bss_start; while (p < &_bss_end) *p++ = 0; }
void dram_init(void) { }
void gpio_init(void) { }
void uart_init(int baud) { }
void uart_puts(const char *s) { while (*s) uart_putc(*s++); }
int detect_boot_source(void) { return BOOT_SOURCE_NAND; }
int validate_stage2(void *addr) { return 1; }
