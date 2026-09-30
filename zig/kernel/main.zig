//! SPDX-License-Identifier: AGPL-3.0-or-later
//! Copyright 2025 Ahmad Ali Parr / SnapKitty � https://github.com/SNAPKITTYWEST/phaser-ags
//! ═══════════════════════════════════════════════════════════════════
//!  PHASER AGS — Zig kernel entry point
//!
//!  Boot sequence for the NAND-derived RV32I core on OMAP3530:
//!    1. start.S: set stack, zero BSS, install trap vector
//!    2. kernelMain: board init → page alloc → VM → timer → shell
//!    3. Shell: interactive over UART, commands for debug/control
//!
//!  Build: zig build-exe main.zig -target riscv64-freestanding-none
//!         -O ReleaseSmall -linker-script kernel.ld
//! ═══════════════════════════════════════════════════════════════════

const std = @import("std");
const driver  = @import("driver.zig");
const trap    = @import("trap.zig");
const memory  = @import("memory.zig");
const timer   = @import("timer.zig");
const process = @import("process.zig");
const shell   = @import("shell.zig");

// ─── Kernel entry (called from start.S after BSS clear) ─────────

export fn kernelMain() callconv(.C) void {
    // ── Phase 1: Board bring-up ──
    driver.Board.earlyInit();
    driver.Board.consoleInit();

    driver.Uart.puts("┌────────────────────────────────────┐\n");
    driver.Uart.puts("│  Phaser AGS Universal Kernel       │\n");
    driver.Uart.puts("│  RV32I on NAND-derived Chisel core │\n");
    driver.Uart.puts("│  Zig driver · Nim register macros  │\n");
    driver.Uart.puts("└────────────────────────────────────┘\n");

    // ── Phase 2: Page allocator ──
    memory.initPageAlloc();

    // ── Phase 3: Trap framework ──
    trap.initDefaults();
    driver.Uart.puts("Trap handlers installed\n");

    // ── Phase 4: Process table ──
    process.init();

    // ── Phase 5: Timer (10ms tick at assumed 10 MHz CLINT) ──
    timer.init(10_000_000, 10);
    timer.setCallback(process.schedTick);
    driver.Uart.puts("Timer: 10 ms ticks, scheduler callback\n");

    // ── Phase 6: Enable interrupts ──
    driver.csrSet(driver.CSR.MIE, 1 << 7);  // MTIE
    driver.csrSet(driver.CSR.MSTATUS, 0x08); // MIE
    driver.Uart.puts("Interrupts enabled\n");

    // ── Phase 7: Kernel shell ──
    driver.Uart.puts("All subsystems up — entering shell\n\n");
    shell.run();
}
