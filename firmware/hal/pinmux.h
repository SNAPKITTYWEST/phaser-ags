/*
 * OMAP3530 Pin Multiplex / Pad Configuration
 * OMAP3530 control module pad registers at 0x48002000+
 * Modeled on R8A7740 board_early_init_f / r8a7740_pinmux_init pattern
 */

#ifndef FIRMWARE_HAL_PINMUX_H
#define FIRMWARE_HAL_PINMUX_H

#include "../common/types.h"
#include "../common/platform.h"

/*
 * OMAP3530 pad control registers: CONTROL_PADCONF_xxx
 * Each register controls one ball/pad: mux mode [2:0], pull [4:3], input enable [8]
 * Base: 0x48002000 (SCM module), offset varies per pad
 */

#define PADCONF_BASE        0x48002000UL

/* Mux modes per pad */
#define MUX_MODE0  0   /* Primary function */
#define MUX_MODE1  1
#define MUX_MODE2  2
#define MUX_MODE3  3
#define MUX_MODE4  4
#define MUX_MODE7  7   /* Safe mode (GPIO often) */

/* Pull configuration */
#define PULL_DISABLED  (0 << 3)
#define PULL_UP       (1 << 3)
#define PULL_DOWN     (2 << 3)

/* Input enable */
#define INPUT_ENABLE  (1 << 8)

typedef struct {
    uint32_t offset;     /* Offset from PADCONF_BASE */
    uint32_t value;      /* Mux mode + pull + input */
} pad_config_t;

void pinmux_init(const pad_config_t *table, uint32_t count);
void pinmux_set(uint32_t offset, uint32_t value);
uint32_t pinmux_get(uint32_t offset);

#endif /* FIRMWARE_HAL_PINMUX_H */
