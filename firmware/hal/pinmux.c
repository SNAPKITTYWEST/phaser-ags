/*
 * OMAP3530 Pin Multiplex Configuration
 */

#include "pinmux.h"

void pinmux_init(const pad_config_t *table, uint32_t count) {
    hw_reg32_t base = (hw_reg32_t)PADCONF_BASE;
    for (uint32_t i = 0; i < count; i++) {
        reg_write32(base + table[i].offset, table[i].value);
    }
}

void pinmux_set(uint32_t offset, uint32_t value) {
    hw_reg32_t base = (hw_reg32_t)PADCONF_BASE;
    reg_write32(base + offset, value);
}

uint32_t pinmux_get(uint32_t offset) {
    hw_reg32_t base = (hw_reg32_t)PADCONF_BASE;
    return reg_read32(base + offset);
}
