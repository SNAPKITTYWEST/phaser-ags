//! SPDX-License-Identifier: AGPL-3.0-or-later
//! Copyright 2025 Ahmad Ali Parr / SnapKitty — https://github.com/SNAPKITTYWEST/phaser-ags
//! ═══════════════════════════════════════════════════════════════════
//!  PHASER AGS — Process management (complete, no stubs)
//!
//!  - Full PCB with kernel stack, user stack, page table
//!  - Round-robin preemptive scheduler via timer tick
//!  - Context switch through trap frame save/restore
//!  - Process creation with proper initial register state
//!  - Process cleanup (free all resources on exit/kill)
//! ═══════════════════════════════════════════════════════════════════

const std = @import("std");
const driver = @import("driver.zig");
const trap = @import("trap.zig");
const memory = @import("memory.zig");

const MAX_PROCS: usize = 16;
// Page counts are u32 to match memory.allocRange/freeRange (SV32 PAs).
const KSTACK_PAGES: u32 = 2;    // 8 KB kernel stack
const USTACK_PAGES: u32 = 4;    // 16 KB user stack

// ─── Process states ──────────────────────────────────────────────

const ProcState = enum(u8) {
    unused    = 0,
    runnable  = 1,
    running   = 2,
    sleeping  = 3,
    zombie    = 4,
};

// ─── Process Control Block ───────────────────────────────────────

pub const Process = struct {
    pid:        u16,
    state:      ProcState,
    ksp:        usize,            // Saved trap frame pointer (XLEN-wide)
    kstack:     u32,             // Kernel stack base address
    ustack:     u32,             // User stack base address (0 = none)
    page_root:  *memory.PageTable,
    entry:      u32,
    quantum:    u32,             // Ticks remaining in time slice
    total_ticks: u64,           // Total ticks this process has run
    exit_code:  i32,            // Exit code (valid when zombie)
    name:       [16]u8,
    // File descriptor table
    fds:        [16]?FdEntry,
};

pub const FdEntry = struct {
    kind: FdKind,
    dev: ?*const DevOps,
    offset: u64,
    flags: u32,

    pub const FdKind = enum(u8) {
        none = 0,
        device = 1,
        pipe = 2,
        file = 3,
    };
};

pub const DevOps = struct {
    read: *const fn ([]u8) usize,
    write: *const fn ([]const u8) usize,
    close: *const fn () void,
};

// ─── Global process table ────────────────────────────────────────

var procs: [MAX_PROCS]Process = undefined;
var current_pid: u16 = 0;
var next_pid: u16 = 1;

// ─── Initialize process table ────────────────────────────────────

pub fn init() void {
    for (&procs) |*p| {
        p.* = .{
            .pid = 0,
            .state = .unused,
            .ksp = 0,
            .kstack = 0,
            .ustack = 0,
            .page_root = undefined,
            .entry = 0,
            .quantum = 0,
            .total_ticks = 0,
            .exit_code = 0,
            .name = std.mem.zeroes([16]u8),
            .fds = .{null} ** 16,
        };
    }
    driver.Uart.puts("Process table: ");
    driver.Uart.putHex(MAX_PROCS);
    driver.Uart.puts(" slots initialized\n");
}

// ─── Allocate a free PCB slot ────────────────────────────────────

fn allocSlot() ?*Process {
    for (&procs) |*p| {
        if (p.state == .unused) {
            p.pid = next_pid;
            next_pid +|= 1;
            if (next_pid == 0) next_pid = 1;  // skip 0
            return p;
        }
    }
    return null;
}

// ─── Create a new process ────────────────────────────────────────

pub fn create(entry: u32, name: []const u8) ?*Process {
    const proc = allocSlot() orelse {
        driver.Uart.puts("proc: table full\n");
        return null;
    };

    // Allocate kernel stack
    const kstack = memory.allocRange(KSTACK_PAGES) orelse {
        proc.state = .unused;
        driver.Uart.puts("proc: kstack alloc failed\n");
        return null;
    };
    proc.kstack = kstack;

    // Set up initial trap frame at top of kernel stack
    const tf_addr = kstack + KSTACK_PAGES * memory.PAGE_SIZE - @sizeOf(trap.TrapFrame);
    const tf: *trap.TrapFrame = @ptrFromInt(tf_addr);

    // Zero the entire trap frame
    const tf_bytes: [*]u8 = @ptrCast(tf);
    var i: usize = 0;
    while (i < @sizeOf(trap.TrapFrame)) : (i += 1) {
        tf_bytes[i] = 0;
    }

    tf.mepc = entry;
    tf.mstatus = 0x00001880;  // MPP=M (bits 12:11=11), MIE=0 (bit 3)
    // We run everything in M-mode for now, so MPP=M

    // Allocate user stack
    const ustack = memory.allocRange(USTACK_PAGES) orelse {
        memory.freeRange(kstack, KSTACK_PAGES);
        proc.state = .unused;
        driver.Uart.puts("proc: ustack alloc failed\n");
        return null;
    };
    tf.s0 = 0;                         // frame pointer
    tf.sp = ustack + USTACK_PAGES * memory.PAGE_SIZE;  // stack grows down
    proc.ustack = ustack;

    // Create address space
    const root = memory.createAddressSpace() orelse {
        memory.freeRange(kstack, KSTACK_PAGES);
        memory.freeRange(ustack, USTACK_PAGES);
        proc.state = .unused;
        driver.Uart.puts("proc: page table alloc failed\n");
        return null;
    };

    // Map user stack in the process's page table
    var pi: u32 = 0;
    while (pi < USTACK_PAGES) : (pi += 1) {
        const upage = ustack + pi * memory.PAGE_SIZE;
        const uva = upage;  // Identity for M-mode
        if (!memory.mapPage(root, uva, upage, memory.PTE_RW)) {
            driver.Uart.puts("proc: ustack map failed\n");
            // Clean up on failure
            memory.destroyAddressSpace(root);
            memory.freeRange(kstack, KSTACK_PAGES);
            memory.freeRange(ustack, USTACK_PAGES);
            proc.state = .unused;
            return null;
        }
    }

    proc.page_root = root;
    proc.ksp = tf_addr;  // Trap frame is on kernel stack
    proc.entry = entry;
    proc.quantum = DEFAULT_QUANTUM;
    proc.total_ticks = 0;
    proc.exit_code = 0;
    proc.state = .runnable;

    // Copy name
    const len = @min(name.len, 15);
    @memcpy(proc.name[0..len], name[0..len]);
    proc.name[len] = 0;

    // Set up default file descriptors: stdin=0, stdout=1, stderr=2
    // We store the dev ops pointer — it's a global, safe to point to
    proc.fds[0] = FdEntry{ .kind = .device, .dev = &uart_read_ops, .offset = 0, .flags = 0 };
    proc.fds[1] = FdEntry{ .kind = .device, .dev = &uart_write_ops, .offset = 0, .flags = 0 };
    proc.fds[2] = FdEntry{ .kind = .device, .dev = &uart_write_ops, .offset = 0, .flags = 0 };

    driver.Uart.puts("Created proc ");
    driver.Uart.putHex(proc.pid);
    driver.Uart.putc(' ');
    driver.Uart.puts(&proc.name);
    driver.Uart.puts(" entry=");
    driver.Uart.putHex(entry);
    driver.Uart.putc('\n');

    return proc;
}

// ─── UART device operations ──────────────────────────────────────

var uart_read_ops = DevOps{
    .read = uartDevRead,
    .write = uartDevWrite,
    .close = uartDevClose,
};
var uart_write_ops = DevOps{
    .read = uartDevRead,
    .write = uartDevWrite,
    .close = uartDevClose,
};

fn uartDevRead(buf: []u8) usize {
    var i: usize = 0;
    while (i < buf.len) {
        if ((driver.regRead(u32, driver.MemoryMap.UART0_BASE + 0x14) & 0x01) != 0) {
            buf[i] = driver.Uart.getc();
            i += 1;
        } else break;
    }
    return i;
}

fn uartDevWrite(buf: []const u8) usize {
    driver.Uart.puts(buf);
    return buf.len;
}

fn uartDevClose() void {}

// ─── Get current process ─────────────────────────────────────────

pub fn getCurrent() ?*Process {
    if (current_pid == 0) return null;
    for (&procs) |*p| {
        if (p.pid == current_pid and p.state == .running) return p;
    }
    return null;
}

pub fn setCurrentPid(pid: u16) void {
    current_pid = pid;
}

pub fn getByPid(pid: u16) ?*Process {
    for (&procs) |*p| {
        if (p.pid == pid and p.state != .unused) return p;
    }
    return null;
}

// ─── Default time slice ──────────────────────────────────────────

const DEFAULT_QUANTUM: u32 = 10;  // 10 timer ticks

// ─── Round-robin scheduler ───────────────────────────────────────

pub fn schedule() ?*Process {
    // Find the currently running process index to start search after it
    var start_idx: usize = 0;
    if (current_pid != 0) {
        for (&procs, 0..) |p, i| {
            if (p.pid == current_pid) {
                start_idx = @intCast((i + 1) % MAX_PROCS);
                break;
            }
        }
    }

    // Scan for runnable process (round-robin from start_idx)
    var i: usize = 0;
    while (i < MAX_PROCS) : (i += 1) {
        const idx = (start_idx + i) % MAX_PROCS;
        if (procs[idx].state == .runnable) {
            return &procs[idx];
        }
    }

    // All runnable procs exhausted their quanta — refresh
    var found: ?*Process = null;
    for (&procs) |*p| {
        if (p.state == .runnable) {
            p.quantum = DEFAULT_QUANTUM;
            if (found == null) found = p;
        }
    }
    return found;
}

// ─── Scheduler tick — called from timer interrupt ────────────────

pub fn schedTick() void {
    if (getCurrent()) |p| {
        if (p.quantum > 0) p.quantum -= 1;
        p.total_ticks += 1;
    }
}

// ─── Kill a process and free all resources ───────────────────────

pub fn kill(pid: u16) void {
    const p = getByPid(pid) orelse return;

    // Close all open file descriptors
    for (&p.fds) |*fd| {
        if (fd.*) |*entry| {
            if (entry.dev) |dev| {
                dev.close();
            }
            fd.* = null;
        }
    }

    // Free user stack (base recorded at create time; the live sp in the
    // latest trap frame can be anywhere inside the stack, so it cannot be
    // used to recover the base).
    if (p.ustack != 0) {
        memory.freeRange(p.ustack, USTACK_PAGES);
        p.ustack = 0;
    }

    // Free kernel stack
    memory.freeRange(p.kstack, KSTACK_PAGES);

    // Destroy page table and any user pages
    memory.destroyAddressSpace(p.page_root);

    // Mark as zombie (parent could collect exit code)
    p.exit_code = 1;
    p.state = .zombie;

    if (current_pid == pid) {
        current_pid = 0;
    }

    driver.Uart.puts("Killed proc ");
    driver.Uart.putHex(pid);
    driver.Uart.putc('\n');
}

// ─── Exit current process ────────────────────────────────────────

pub fn exit(code: i32) void {
    if (getCurrent()) |p| {
        p.exit_code = code;
        kill(p.pid);
        trap.requestReschedule();
    }
}

// ─── Yield current process ───────────────────────────────────────

pub fn yieldExecution() void {
    if (getCurrent()) |p| {
        p.quantum = 0;  // Force reschedule
    }
    trap.requestReschedule();
}

// ─── Sleep current process ───────────────────────────────────────

pub fn sleep() void {
    if (getCurrent()) |p| {
        p.state = .sleeping;
    }
    trap.requestReschedule();
}

// ─── Wake a sleeping process ─────────────────────────────────────

pub fn wake(pid: u16) void {
    if (getByPid(pid)) |p| {
        if (p.state == .sleeping) {
            p.state = .runnable;
            p.quantum = DEFAULT_QUANTUM;
        }
    }
}

// ─── Reap zombie processes ───────────────────────────────────────

pub fn reapZombies() u32 {
    var count: u32 = 0;
    for (&procs) |*p| {
        if (p.state == .zombie) {
            p.state = .unused;
            p.pid = 0;
            count += 1;
        }
    }
    return count;
}

// ─── Get fd for a process ────────────────────────────────────────

pub fn getFd(proc: *Process, fd: u32) ?*FdEntry {
    if (fd >= 16) return null;
    if (proc.fds[fd] == null) return null;
    return &proc.fds[fd].?;
}

// ─── Allocate a free fd ──────────────────────────────────────────

pub fn allocFd(proc: *Process) ?u32 {
    var i: u32 = 0;
    while (i < 16) : (i += 1) {
        if (proc.fds[i] == null) return i;
    }
    return null;
}

// ─── Dump all processes ──────────────────────────────────────────

pub fn dumpAll() void {
    const state_names: [5][]const u8 = .{ "unused", "runbl", "runng", "sleep", "zombi" };
    driver.Uart.puts("PID  STATE   ENTRY    KSTK     QNT  TICKS  NAME\n");
    for (&procs) |p| {
        if (p.state != .unused) {
            driver.Uart.putHex(p.pid);
            driver.Uart.putc(' ');
            const si = @intFromEnum(p.state);
            if (si < 5) driver.Uart.puts(state_names[si]);
            driver.Uart.putc(' ');
            driver.Uart.putHex(p.entry);
            driver.Uart.putc(' ');
            driver.Uart.putHex(@intCast(p.ksp));
            driver.Uart.putc(' ');
            driver.Uart.putHex(p.quantum);
            driver.Uart.putc(' ');
            driver.Uart.putHex(@truncate(p.total_ticks));
            driver.Uart.putc(' ');
            for (p.name) |ch| {
                if (ch == 0) break;
                driver.Uart.putc(ch);
            }
            driver.Uart.putc('\n');
        }
    }
}
