/* PowerPC Universal Bootloader Stage 1 */
#include "common.h"

#define RESET_VECTOR 0xFFF00000
#define STACK_BASE   0x30000000
#define STACK_SIZE   0x8000

__attribute__((section(".reset"))) void reset_entry(void) {
    asm volatile("lis r0, 0x0000; mtmsr r0");
    asm volatile("lis r1, STACK_BASE@h; ori r1, r1, STACK_BASE@l");

    cache_init();
    memory_init();
    ppc_clock_init();
    uart_init(115200);
    uart_puts("Stage 1 Bootloader PowerPC\r\n");

    goto_stage2();
}

void cache_init(void) { asm volatile("isync; li r0,0; mtmsr r0; isync"); }
void memory_init(void) { }
void ppc_clock_init(void) { }
void goto_stage2(void) { void (*stage2)(void) = (void*)0x30010000; stage2(); }
