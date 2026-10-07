//! SPDX-License-Identifier: AGPL-3.0-or-later
//! Copyright 2025 Ahmad Ali Parr / SnapKitty — https://github.com/SNAPKITTYWEST/phaser-ags
//! ═══════════════════════════════════════════════════════════════════
//!  PHASER AGS — Trap framework (complete, no stubs)
//!
//!  Full context save/restore dispatch. Integrates with process.zig
//!  for preemptive context switching on timer tick.
//! ═══════════════════════════════════════════════════════════════════

const std = @import("std");
const driver = @import("driver.zig");

// ─── Trap frame layout (matches start.S slot map exactly) ────────
//
//  One slot per XLEN register (usize = 4 bytes on RV32, 8 on RV64),
//  33 live slots, padded to a 16-byte multiple (psABI stack alignment):
//    RV32: 132 → 144 bytes      RV64: 264 → 272 bytes

const FRAME_SLOTS = 33;
pub const FRAME_SIZE = std.mem.alignForward(usize, FRAME_SLOTS * @sizeOf(usize), 16);
const PAD_SLOTS = (FRAME_SIZE - FRAME_SLOTS * @sizeOf(usize)) / @sizeOf(usize);

pub const TrapFrame = extern struct {
    sp:        usize,    // slot 0   x2 — interrupted sp (restored last)
    ra:        usize,    // slot 1   x1
    t0:        usize,    // slot 2   x5
    t1:        usize,    // slot 3   x6
    t2:        usize,    // slot 4   x7
    a0:        usize,    // slot 5   x10
    a1:        usize,    // slot 6   x11
    a2:        usize,    // slot 7   x12
    a3:        usize,    // slot 8   x13
    a4:        usize,    // slot 9   x14
    a5:        usize,    // slot 10  x15
    a6:        usize,    // slot 11  x16
    a7:        usize,    // slot 12  x17
    s0:        usize,    // slot 13  x8
    s1:        usize,    // slot 14  x9
    s2:        usize,    // slot 15  x18
    s3:        usize,    // slot 16  x19
    s4:        usize,    // slot 17  x20
    s5:        usize,    // slot 18  x21
    s6:        usize,    // slot 19  x22
    s7:        usize,    // slot 20  x23
    s8:        usize,    // slot 21  x24
    s9:        usize,    // slot 22  x25
    s10:       usize,    // slot 23  x26
    s11:       usize,    // slot 24  x27
    t3:        usize,    // slot 25  x28
    t4:        usize,    // slot 26  x29
    t5:        usize,    // slot 27  x30
    t6:        usize,    // slot 28  x31
    mepc:      usize,    // slot 29
    mstatus:   usize,    // slot 30
    mcause:    usize,    // slot 31
    mtval:     usize,    // slot 32
    _pad:      [PAD_SLOTS]usize,
};

comptime {
    const W = @sizeOf(usize);
    std.debug.assert(@sizeOf(TrapFrame) == FRAME_SIZE);
    std.debug.assert(FRAME_SIZE % 16 == 0);
    std.debug.assert(@offsetOf(TrapFrame, "sp") == 0 * W);
    std.debug.assert(@offsetOf(TrapFrame, "ra") == 1 * W);
    std.debug.assert(@offsetOf(TrapFrame, "a0") == 5 * W);
    std.debug.assert(@offsetOf(TrapFrame, "a7") == 12 * W);
    std.debug.assert(@offsetOf(TrapFrame, "s0") == 13 * W);
    std.debug.assert(@offsetOf(TrapFrame, "t6") == 28 * W);
    std.debug.assert(@offsetOf(TrapFrame, "mepc") == 29 * W);
    std.debug.assert(@offsetOf(TrapFrame, "mtval") == 32 * W);
}

/// mcause: interrupt flag is the MSB of XLEN (bit 31 on RV32, 63 on RV64).
const MCAUSE_IRQ_BIT: std.math.Log2Int(usize) = @bitSizeOf(usize) - 1;
const MCAUSE_CODE_MASK: usize = std.math.maxInt(usize) >> 1;

// ─── Exception and interrupt codes ───────────────────────────────

pub const Exception = enum(usize) {
    instr_misaligned   = 0,
    instr_access       = 1,
    illegal_instr      = 2,
    breakpoint         = 3,
    load_misaligned    = 4,
    load_access        = 5,
    store_misaligned   = 6,
    store_access       = 7,
    ecall_u            = 8,
    ecall_s            = 9,
    ecall_m            = 11,
    instr_page_fault   = 12,
    load_page_fault    = 13,
    store_page_fault   = 15,
    _,
};

pub const Interrupt = enum(usize) {
    s_software  = 1,
    m_software  = 3,
    s_timer     = 5,
    m_timer     = 7,
    s_external  = 9,
    m_external  = 11,
    _,
};

// ─── Handler registration ────────────────────────────────────────

const ExceptionHandler = *const fn (*TrapFrame, usize) void;
const InterruptHandler = *const fn (*TrapFrame, usize) void;

var exc_handlers: [16]?ExceptionHandler = .{null} ** 16;
var irq_handlers: [12]?InterruptHandler = .{null} ** 12;

pub fn registerException(code: usize, handler: ExceptionHandler) void {
    if (code < 16) exc_handlers[code] = handler;
}

pub fn registerInterrupt(code: usize, handler: InterruptHandler) void {
    if (code > 0 and code < 12) irq_handlers[code] = handler;
}

// ─── Reschedule flag (set by timer, checked by dispatch) ─────────

var need_reschedule: bool = false;

pub fn requestReschedule() void {
    need_reschedule = true;
}

// ─── Main dispatch — called from start.S ─────────────────────────

export fn trapDispatch(frame: *TrapFrame) *TrapFrame {
    const cause = frame.mcause;
    const is_irq = (cause >> MCAUSE_IRQ_BIT) != 0;
    const code = cause & MCAUSE_CODE_MASK;

    if (is_irq) {
        dispatchInterrupt(frame, code);
    } else {
        dispatchException(frame, code);
    }

    // ── Preemptive context switch ──
    if (need_reschedule) {
        need_reschedule = false;
        return doContextSwitch(frame);
    }

    return frame;
}

// ─── Interrupt dispatch ──────────────────────────────────────────

fn dispatchInterrupt(frame: *TrapFrame, code: usize) void {
    if (code < 12 and irq_handlers[code] != null) {
        irq_handlers[code].?(frame, code);
        return;
    }

    switch (@as(Interrupt, @enumFromInt(code))) {
        .m_timer => defaultTimerHandler(frame),
        .m_software => defaultSoftwareHandler(frame),
        .m_external => defaultExternalHandler(frame),
        else => {
            driver.Uart.puts("UNHANDLED IRQ ");
            driver.Uart.putHex(@intCast(code));
            driver.Uart.putc('\n');
        },
    }
}

// ─── Exception dispatch ──────────────────────────────────────────

fn dispatchException(frame: *TrapFrame, code: usize) void {
    if (code < 16 and exc_handlers[code] != null) {
        exc_handlers[code].?(frame, code);
        return;
    }

    switch (@as(Exception, @enumFromInt(code))) {
        .ecall_m       => handleEcall(frame),
        .ecall_u       => handleEcall(frame),
        .illegal_instr => handleIllegal(frame),
        .instr_page_fault,
        .load_page_fault,
        .store_page_fault => handlePageFault(frame),
        .instr_misaligned,
        .load_misaligned,
        .store_misaligned => handleMisalign(frame),
        .instr_access,
        .load_access,
        .store_access => handleAccessFault(frame),
        .breakpoint => handleBreakpoint(frame),
        else => {
            driver.Uart.puts("UNHANDLED EXC ");
            driver.Uart.putHex(@intCast(code));
            driver.Uart.puts(" at ");
            driver.Uart.putHex(@intCast(frame.mepc));
            driver.Uart.putc('\n');
            frame.mepc += 4;
        },
    }
}

// ─── Default interrupt handlers ──────────────────────────────────

fn defaultTimerHandler(frame: *TrapFrame) void {
    // Acknowledge: CLINT mtimecmp already set by timer.zig
    // Deactivate in MIP by clearing MTIP (done by writing mtimecmp)
    _ = frame;

    // Increment tick count
    const timer_mod = @import("timer.zig");
    timer_mod.ackTick();
}

fn defaultSoftwareHandler(frame: *TrapFrame) void {
    _ = frame;
    // Clear MSIP in CLINT
    driver.regWrite(u32, 0x02000000, 0);
}

fn defaultExternalHandler(frame: *TrapFrame) void {
    _ = frame;
    // Claim interrupt from PLIC
    const plic = @import("driver.zig").Plic;
    const irq_id = plic.claim(0);
    if (irq_id != 0) {
        // Dispatch to registered external IRQ handlers
        driver.dispatchExternalIrq(irq_id);
        plic.complete(0, irq_id);
    }
}

// ─── Exception handlers ──────────────────────────────────────────

fn handleEcall(frame: *TrapFrame) void {
    const syscall_num: usize = frame.a7;
    const result = @import("syscall.zig").dispatch(syscall_num, frame);
    frame.a0 = result;
    frame.mepc += 4;  // Skip the ecall instruction
}

fn handleIllegal(frame: *TrapFrame) void {
    driver.Uart.puts("ILLEGAL INSTR at ");
    driver.Uart.putHex(@intCast(frame.mepc));
    driver.Uart.puts(" mtval=");
    driver.Uart.putHex(@intCast(frame.mtval));
    driver.Uart.putc('\n');
    frame.mepc += 4;
}

fn handlePageFault(frame: *TrapFrame) void {
    driver.Uart.puts("PAGE FAULT at ");
    driver.Uart.putHex(@intCast(frame.mepc));
    driver.Uart.puts(" addr=");
    driver.Uart.putHex(@intCast(frame.mtval));
    driver.Uart.putc('\n');
    // Kill the offending process if one exists
    const proc = @import("process.zig");
    if (proc.getCurrent()) |p| {
        driver.Uart.puts("Killing proc ");
        driver.Uart.putHex(p.pid);
        driver.Uart.putc('\n');
        proc.kill(p.pid);
        requestReschedule();
    } else {
        frame.mepc += 4;
    }
}

fn handleMisalign(frame: *TrapFrame) void {
    driver.Uart.puts("MISALIGNED at ");
    driver.Uart.putHex(@intCast(frame.mepc));
    driver.Uart.puts(" addr=");
    driver.Uart.putHex(@intCast(frame.mtval));
    driver.Uart.putc('\n');
    frame.mepc += 4;
}

fn handleAccessFault(frame: *TrapFrame) void {
    driver.Uart.puts("ACCESS FAULT at ");
    driver.Uart.putHex(@intCast(frame.mepc));
    driver.Uart.puts(" addr=");
    driver.Uart.putHex(@intCast(frame.mtval));
    driver.Uart.putc('\n');
    const proc = @import("process.zig");
    if (proc.getCurrent()) |p| {
        proc.kill(p.pid);
        requestReschedule();
    } else {
        frame.mepc += 4;
    }
}

fn handleBreakpoint(frame: *TrapFrame) void {
    driver.Uart.puts("BREAKPOINT at ");
    driver.Uart.putHex(@intCast(frame.mepc));
    driver.Uart.putc('\n');
    frame.mepc += 4;
}

// ─── Context switch ──────────────────────────────────────────────

fn doContextSwitch(frame: *TrapFrame) *TrapFrame {
    const proc = @import("process.zig");

    // Save current process state
    if (proc.getCurrent()) |cur| {
        cur.ksp = @intFromPtr(frame);
        if (cur.state == .running) {
            cur.state = .runnable;
        }
    }

    // Pick next process
    const next = proc.schedule() orelse {
        // Nothing to run — return current frame (idle)
        return frame;
    };

    // Switch address space if page tables differ
    const cur = proc.getCurrent();
    if (cur == null or cur.?.page_root != next.page_root) {
        @import("memory.zig").switchToPageTable(next.page_root);
    }

    next.state = .running;
    proc.setCurrentPid(next.pid);

    // Return the new process's saved trap frame
    return @ptrFromInt(next.ksp);
}

// ─── Install default handlers at boot ────────────────────────────

pub fn initDefaults() void {
    // Register all exception handlers
    registerException(@intFromEnum(Exception.ecall_m), handleEcall);
    registerException(@intFromEnum(Exception.ecall_u), handleEcall);
    registerException(@intFromEnum(Exception.illegal_instr), handleIllegal);
    registerException(@intFromEnum(Exception.instr_page_fault), handlePageFault);
    registerException(@intFromEnum(Exception.load_page_fault), handlePageFault);
    registerException(@intFromEnum(Exception.store_page_fault), handlePageFault);
    registerException(@intFromEnum(Exception.instr_misaligned), handleMisalign);
    registerException(@intFromEnum(Exception.load_misaligned), handleMisalign);
    registerException(@intFromEnum(Exception.store_misaligned), handleMisalign);
    registerException(@intFromEnum(Exception.instr_access), handleAccessFault);
    registerException(@intFromEnum(Exception.load_access), handleAccessFault);
    registerException(@intFromEnum(Exception.store_access), handleAccessFault);
    registerException(@intFromEnum(Exception.breakpoint), handleBreakpoint);

    // Timer interrupt handler
    registerInterrupt(@intFromEnum(Interrupt.m_timer), handleTimerIrq);
    registerInterrupt(@intFromEnum(Interrupt.m_software), handleSoftwareIrq);
    registerInterrupt(@intFromEnum(Interrupt.m_external), handleExternalIrq);
}

fn handleTimerIrq(frame: *TrapFrame, code: usize) void {
    _ = frame;
    _ = code;
    const timer_mod = @import("timer.zig");
    timer_mod.ackTick();
    timer_mod.advanceCompare();
    // Request reschedule on every tick
    requestReschedule();
}

fn handleSoftwareIrq(frame: *TrapFrame, code: usize) void {
    _ = frame;
    _ = code;
    // Clear MSIP
    driver.regWrite(u32, 0x02000000, 0);
}

fn handleExternalIrq(frame: *TrapFrame, code: usize) void {
    _ = frame;
    _ = code;
    const plic = driver.Plic;
    const irq_id = plic.claim(0);
    if (irq_id != 0) {
        driver.dispatchExternalIrq(irq_id);
        plic.complete(0, irq_id);
    }
}
