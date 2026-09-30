/*
 * HAL — OMAP3530 Clock and Power initialization
 */

#include "clock.h"

int clock_init(void) {
    hw_reg32_t cm = (hw_reg32_t)CM_BASE;
    hw_reg32_t prm = (hw_reg32_t)PRM_BASE;

    /* Wait for power sequencing to complete (from power-tree.json) */
    power_seq_wait();

    /* ---- Configure DPLL1 (MPU / CPU) ---- */
    /* Target: 600MHz from 26MHz ref → M=23, N=1 (26×23/1 = 598MHz, ~600) */
    /* DPLL registers are at CM_CLKSEL_DPLL_MPU etc. — simplified for bring-up */

    /* Enable DPLL1 in lock mode — already configured by ROM boot, verify */
    /* On OMAP3530, the ROM bootloader typically leaves DPLL1 at 500MHz.
       We reconfigure for 600MHz. */

    /* DPLL1 M/N values: M = 23, N = 1 → 598 MHz */
    /* CM_CLKSEL1_PLL_MPU offset — OMAP3530-specific */
    reg32_t cm_clksel1_mpu = cm + 0x940;
    reg_mask32(cm_clksel1_mpu, 0x0007FF0F, (23 << 8) | 1);

    /* Wait for DPLL1 to lock (typical <50µs) */
    delay_cycles(50000);

    /* ---- Configure DPLL3 (CORE / peripheral) ---- */
    /* DPLL3 drives L3 interconnect and peripheral clocks.
       Leave at ROM-default for bring-up (usually 166MHz L3). */

    /* ---- Configure DPLL4 (PER / display) ---- */
    /* DPLL4 generates display and peripheral clocks.
       Leave at ROM-default for bring-up. */

    /* ---- Configure DPLL5 (DDR) ---- */
    /* Target: 266MHz DDR clock → M=10, N=1 (26×10/1 = 260MHz) */
    /* DDR2 DPLL — OMAP3530-specific */
    reg32_t cm_clksel5_pll = cm + 0x0F4;
    reg_mask32(cm_clksel5_pll, 0x0007FF0F, (10 << 8) | 1);
    delay_cycles(50000);

    return 0;
}

void clock_enable_uart(void) {
    hw_reg32_t cm = (hw_reg32_t)CM_BASE;

    /* Enable UART1/2 functional and interface clocks */
    reg_set32(cm + CM_FCLKEN1_CORE, (1 << 21) | (1 << 22));  /* UART1, UART2 */
    reg_set32(cm + CM_ICLKEN1_CORE, (1 << 21) | (1 << 22));

    /* Wait for clocks to become active */
    delay_cycles(500);
    while (!(reg_read32(cm + CM_IDLEST1_CORE) & ((1 << 21) | (1 << 22))))
        ;
}

void clock_enable_gpio(void) {
    hw_reg32_t cm = (hw_reg32_t)CM_BASE;

    /* GPIO clocks are in WKUP domain */
    reg_set32(cm + CM_FCLKEN_WKUP, (1 << 4));   /* GPIO1 */
    reg_set32(cm + CM_ICLKEN_WKUP, (1 << 4));

    delay_cycles(500);
}

void clock_enable_gptimer(void) {
    hw_reg32_t cm = (hw_reg32_t)CM_BASE;

    /* GP Timer 1 is in WKUP domain */
    reg_set32(cm + CM_FCLKEN_WKUP, (1 << 2));
    reg_set32(cm + CM_ICLKEN_WKUP, (1 << 2));

    /* GP Timer 2-9 are in PER domain */
    reg32_t cm_fclken_per = cm + 0x500;
    reg32_t cm_iclken_per = cm + 0x510;
    reg_set32(cm_fclken_per, 0x03FF);  /* Timers 2-9 */
    reg_set32(cm_iclken_per, 0x03FF);

    delay_cycles(500);
}

void clock_enable_gpmc(void) {
    hw_reg32_t cm = (hw_reg32_t)CM_BASE;

    /* GPMC functional + interface clocks */
    reg_set32(cm + CM_FCLKEN1_CORE, (1 << 1));
    reg_set32(cm + CM_ICLKEN1_CORE, (1 << 1));

    delay_cycles(500);
    while (!(reg_read32(cm + CM_IDLEST1_CORE) & (1 << 1)))
        ;
}

void clock_enable_sdrc(void) {
    hw_reg32_t cm = (hw_reg32_t)CM_BASE;

    /* SDRC interface clock */
    reg_set32(cm + CM_ICLKEN1_CORE, (1 << 2));

    delay_cycles(500);
    while (!(reg_read32(cm + CM_IDLEST1_CORE) & (1 << 2)))
        ;
}

void power_seq_wait(void) {
    /* Power sequencing from power-tree.json:
       P5V0:  0ms
       P3V3:  10ms
       P1V8:  20ms
       P1V2:  30ms
       P1V0:  50ms
       Total: ~50ms for all rails stable */
    delay_cycles(CPU_CLK_HZ / 20);   /* ~50ms at ~600MHz */
}
