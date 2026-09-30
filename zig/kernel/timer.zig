//! ═══════════════════════════════════════════════════════════════════
//!  PHASER AGS — RISC-V timer + CLINT (complete, no stubs)
//!  Full tick management with scheduler callback and compare setup.
//! ═══════════════════════════════════════════════════════════════════

const std = @import("std");
const driver = @import("driver.zig");

const CLINT_BASE: u32 = 0x02000000;
const MTIME_OFF:  u32 = 0xBFF8;
const MTIMECMP_OFF: u32 = 0x4000;

inline fn clintRead64(offset: u32) u64 {
    const lo = driver.regRead(u32, CLINT_BASE + offset);
    const hi = driver.regRead(u32, CLINT_BASE + offset + 4);
    return @as(u64, hi) << 32 | @as(u64, lo);
}

inline fn clintWrite64(offset: u32, val: u64) void {
    driver.regWrite(u32, CLINT_BASE + offset + 4, @intCast(val >> 32));
    driver.regWrite(u32, CLINT_BASE + offset, @intCast(val & 0xFFFFFFFF));
}

pub fn getTime() u64 {
    var lo: u32 = undefined;
    var hi: u32 = undefined;
    while (true) {
        hi = driver.regRead(u32, CLINT_BASE + MTIME_OFF + 4);
        lo = driver.regRead(u32, CLINT_BASE + MTIME_OFF);
        const hi2 = driver.regRead(u32, CLINT_BASE + MTIME_OFF + 4);
        if (hi == hi2) break;
    }
    return @as(u64, hi) << 32 | @as(u64, lo);
}

pub fn setCompare(val: u64) void {
    clintWrite64(MTIMECMP_OFF, val);
}

var tick_interval: u64 = 0;
var tick_count: u64 = 0;
var timer_callback: ?*const fn () void = null;

pub fn init(freq_hz: u64, tick_ms: u64) void {
    tick_interval = (freq_hz * tick_ms) / 1000;
    if (tick_interval == 0) tick_interval = 1;
    tick_count = 0;

    const now = getTime();
    setCompare(now + tick_interval);

    driver.csrSet(driver.CSR.MIE, 1 << 7);  // MTIE

    driver.Uart.puts("Timer: ");
    driver.Uart.putHex(@intCast(tick_interval));
    driver.Uart.puts(" ticks/irq (");
    driver.Uart.putHex(@intCast(tick_ms));
    driver.Uart.puts(" ms @ ");
    driver.Uart.putHex(@intCast(freq_hz));
    driver.Uart.puts(" Hz)\n");
}

pub fn setCallback(cb: *const fn () void) void {
    timer_callback = cb;
}

pub fn getTickCount() u64 {
    return tick_count;
}

pub fn getTickInterval() u64 {
    return tick_interval;
}

pub fn ackTick() void {
    tick_count += 1;
}

pub fn advanceCompare() void {
    const now = getTime();
    setCompare(now + tick_interval);
    if (timer_callback) |cb| {
        cb();
    }
}
