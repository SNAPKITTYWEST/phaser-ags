//! ═══════════════════════════════════════════════════════════════════
//!  PHASER AGS — Trap framework (complete, no stubs)
//!
//!  Full context save/restore dispatch. Integrates with process.zig
//!  for preemptive context switching on timer tick.
//! ═══════════════════════════════════════════════════════════════════

const std = @import("std");
const driver = @import("driver.zig");

// ─── Trap frame layout (matches start.S offsets exactly) ─────────

pub const TrapFrame = extern struct {
    prev_ctx:  u64,      // 0(sp)   — old sp before csrrw swap
    ra:        u64,      // 8       x1
    t0:        u64,      // 16      x5
    t1:        u64,      // 24      x6
    t2:        u64,      // 32      x7
    a0:        u64,      // 40      x10
    a1:        u64,      // 48      x11
    a2:        u64,      // 56      x12
    a3:        u64,      // 64      x13
    a4:        u64,      // 72      x14
    a5:        u64,      // 80      x15
    a6:        u64,      // 88      x16
    a7:        u64,      // 96      x17
    s0:        u64,      // 104     x8
    s1:        u64,      // 112     x9
    s2:        u64,      // 120     x18
    s3:        u64,      // 128     x19
    s4:        u64,      // 136     x20
    s5:        u64,      // 144     x21
    s6:        u64,      // 152     x22
    s7:        u64,      // 160     x23
    s8:        u64,      // 168     x24
    s9:        u64,      // 176     x25
    s10:       u64,      // 184     x26
    s11:       u64,      // 192     x27
    t3:        u64,      // 200     x28
    t4:        u64,      // 208     x29
    t5:        u64,      // 216     x30
    t6:        u64,      // 224     x31
    mepc:      u64,      // 232
    mstatus:   u64,      // 240
    mcause:    u64,      // 248
    mtval:     u64,      // 256
};

comptime {
    std.debug.assert(@sizeOf(TrapFrame) == 264);
}

// ─── Exception and interrupt codes ───────────────────────────────

pub const Exception = enum(u64) {
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

pub const Interrupt = enum(u64) {
    s_software  = 1,
    m_software  = 3,
    s_timer     = 5,
    m_timer     = 7,
    s_external  = 9,
    m_external  = 11,
    _,
};

// ─── Handler registration ────────────────────────────────────────

const ExceptionHandler = *const fn (*TrapFrame, u64) void;
const InterruptHandler = *const fn (*TrapFrame, u64) void;

var exc_handlers: [16]?ExceptionHandler = .{null} ** 16;
var irq_handlers: [12]?InterruptHandler = .{null} ** 12;

pub fn registerException(code: u64, handler: ExceptionHandler) void {
    if (code < 16) exc_handlers[code] = handler;
}

pub fn registerInterrupt(code: u64, handler: InterruptHandler) void {
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
    const is_irq = (cause >> 63) != 0;
    const code = cause & 0x7FFF_FFFF_FFFF_FFFF;

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

fn dispatchInterrupt(frame: *TrapFrame, code: u64) void {
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

fn dispatchException(frame: *TrapFrame, code: u64) void {
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
    const syscall_num: u64 = frame.a7;
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

fn handleTimerIrq(frame: *TrapFrame, code: u64) void {
    _ = code;
    const timer_mod = @import("timer.zig");
    timer_mod.ackTick();
    timer_mod.advanceCompare();
    // Request reschedule on every tick
    requestReschedule();
}

fn handleSoftwareIrq(frame: *TrapFrame, code: u64) void {
    _ = frame;
    _ = code;
    // Clear MSIP
    driver.regWrite(u32, 0x02000000, 0);
}

fn handleExternalIrq(frame: *TrapFrame, code: u64) void {
    _ = frame;
    _ = code;
    const plic = driver.Plic;
    const irq_id = plic.claim(0);
    if (irq_id != 0) {
        driver.dispatchExternalIrq(irq_id);
        plic.complete(0, irq_id);
    }
}
