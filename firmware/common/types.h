/*
 * Common types for Phaser AGS firmware
 * ARM Cortex-A8 (OMAP3530) — 32-bit
 */

#ifndef FIRMWARE_COMMON_TYPES_H
#define FIRMWARE_COMMON_TYPES_H

#include <stdint.h>
#include <stddef.h>

typedef uint32_t reg32_t;
typedef uint16_t reg16_t;
typedef uint8_t  reg8_t;

typedef volatile reg32_t *hw_reg32_t;
typedef volatile reg16_t *hw_reg16_t;
typedef volatile reg8_t  *hw_reg8_t;

static inline void reg_write32(hw_reg32_t addr, reg32_t val) {
    *addr = val;
}

static inline reg32_t reg_read32(hw_reg32_t addr) {
    return *addr;
}

static inline void reg_set32(hw_reg32_t addr, reg32_t mask) {
    *addr |= mask;
}

static inline void reg_clr32(hw_reg32_t addr, reg32_t mask) {
    *addr &= ~mask;
}

static inline void reg_mask32(hw_reg32_t addr, reg32_t mask, reg32_t val) {
    *addr = (*addr & ~mask) | (val & mask);
}

static inline void delay_cycles(uint32_t count) {
    for (volatile uint32_t i = 0; i < count; i++)
        __asm__ volatile("" ::: "memory");
}

#define ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))

#define ALIGN_UP(x, a) (((x) + (a) - 1) & ~((a) - 1))
#define ALIGN_DOWN(x, a) ((x) & ~((a) - 1))

#endif /* FIRMWARE_COMMON_TYPES_H */
