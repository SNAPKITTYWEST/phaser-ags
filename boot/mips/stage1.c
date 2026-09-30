/* MIPS Universal Bootloader Stage 1 */
#include "common.h"

#define RESET_VECTOR 0xBFC00000
#define STACK_BASE   0x80010000
#define STACK_SIZE   0x4000

__attribute__((section(".reset"))) void reset_entry(void) {
    asm volatile("mtc0 $0, $12");
    asm volatile("mtc0 $0, $13");
    asm volatile("la $sp, 0x80010000");

    cache_init_mips();
    sdram_init_mips();
    clock_init_mips();
    uart_init(115200);
    uart_puts("Stage 1 Bootloader MIPS\r\n");

    load_stage2();
}

void cache_init_mips(void) { asm volatile("mtc0 $0, $16"); }
void sdram_init_mips(void) { }
void clock_init_mips(void) { }
void load_stage2(void) { void (*stage2)(void) = (void*)0x80020000; stage2(); }
