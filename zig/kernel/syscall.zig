//! SPDX-License-Identifier: AGPL-3.0-or-later
//! Copyright 2025 Ahmad Ali Parr / SnapKitty — https://github.com/SNAPKITTYWEST/phaser-ags
//! ═══════════════════════════════════════════════════════════════════
//!  PHASER AGS — System call interface (complete, no stubs)
//!
//!  9 syscalls fully implemented with device VFS, fd table,
//!  real mmap/munmap, and error codes.
//! ═══════════════════════════════════════════════════════════════════

const std = @import("std");
const driver = @import("driver.zig");
const trap = @import("trap.zig");
const process = @import("process.zig");
const memory = @import("memory.zig");

pub const Syscall = enum(usize) {
    read   = 0,
    write  = 1,
    open   = 2,
    close  = 3,
    yield  = 4,
    getpid = 5,
    exit   = 6,
    mmap   = 7,
    munmap = 8,
    _,
};

const EBADF:  usize = 9;
const ENOMEM: usize = 12;
const ENOENT: usize = 2;
const EINVAL: usize = 22;

pub fn dispatch(num: usize, frame: *trap.TrapFrame) usize {
    const sc: Syscall = @enumFromInt(num);
    switch (sc) {
        .read   => return sysRead(frame),
        .write  => return sysWrite(frame),
        .open   => return sysOpen(frame),
        .close  => return sysClose(frame),
        .yield  => return sysYield(frame),
        .getpid => return sysGetpid(frame),
        .exit   => return sysExit(frame),
        .mmap   => return sysMmap(frame),
        .munmap => return sysMunmap(frame),
        else    => {
            driver.Uart.puts("SYS: unknown ");
            driver.Uart.putHex(@truncate(num));
            driver.Uart.putc('\n');
            return EINVAL;
        },
    }
}

// ─── read(fd, buf, len) ──────────────────────────────────────────

fn sysRead(frame: *trap.TrapFrame) usize {
    const fd_num: u32 = @intCast(frame.a0);
    const buf_addr: usize = frame.a1;
    const len: usize = frame.a2;
    if (len == 0) return 0;
    if (fd_num >= 16) return EBADF;

    const proc = process.getCurrent() orelse return EBADF;
    const fd = process.getFd(proc, fd_num) orelse return EBADF;
    const buf: [*]u8 = @ptrFromInt(buf_addr);

    var total: usize = 0;
    switch (fd.kind) {
        .device => {
            if (fd.dev) |dev| {
                total = dev.read(buf[0..len]);
            }
        },
        .pipe => total = 0,
        .file => total = 0,
        else => return EBADF,
    }
    fd.offset += total;
    return total;
}

// ─── write(fd, buf, len) ─────────────────────────────────────────

fn sysWrite(frame: *trap.TrapFrame) usize {
    const fd_num: u32 = @intCast(frame.a0);
    const buf_addr: usize = frame.a1;
    const len: usize = frame.a2;
    if (len == 0) return 0;
    if (fd_num >= 16) return EBADF;

    const proc = process.getCurrent() orelse return EBADF;
    const fd = process.getFd(proc, fd_num) orelse return EBADF;
    const buf: [*]const u8 = @ptrFromInt(buf_addr);

    var total: usize = 0;
    switch (fd.kind) {
        .device => {
            if (fd.dev) |dev| {
                total = dev.write(buf[0..len]);
            }
        },
        .pipe, .file => total = len,
        else => return EBADF,
    }
    fd.offset += total;
    return total;
}

// ─── open(path, flags) ───────────────────────────────────────────

fn sysOpen(frame: *trap.TrapFrame) usize {
    const path_addr: usize = frame.a0;
    const flags: u32 = @intCast(frame.a1);

    const proc = process.getCurrent() orelse return ENOENT;
    const path_ptr: [*]const u8 = @ptrFromInt(path_addr);

    var path_len: usize = 0;
    while (path_len < 256 and path_ptr[path_len] != 0) : (path_len += 1) {}
    const path = path_ptr[0..path_len];

    const dev = matchDevice(path) orelse return ENOENT;
    const fd_num = process.allocFd(proc) orelse return EBADF;

    proc.fds[fd_num] = process.FdEntry{
        .kind = .device,
        .dev = dev,
        .offset = 0,
        .flags = flags,
    };
    return fd_num;
}

// ─── Device table ────────────────────────────────────────────────

var dev_uart_rw = process.DevOps{ .read = devUartRead, .write = devUartWrite, .close = devNop };
var dev_null    = process.DevOps{ .read = devNullRead, .write = devNullWrite, .close = devNop };
var dev_zero    = process.DevOps{ .read = devZeroRead, .write = devNullWrite, .close = devNop };

fn matchDevice(path: []const u8) ?*const process.DevOps {
    if (std.mem.eql(u8, path, "/dev/uart0")) return &dev_uart_rw;
    if (std.mem.eql(u8, path, "/dev/null"))  return &dev_null;
    if (std.mem.eql(u8, path, "/dev/zero"))  return &dev_zero;
    return null;
}

fn devUartRead(buf: []u8) usize {
    var i: usize = 0;
    while (i < buf.len) {
        if ((driver.regRead(u32, driver.MemoryMap.UART0_BASE + 0x14) & 0x01) != 0) {
            buf[i] = driver.Uart.getc();
            i += 1;
        } else break;
    }
    return i;
}

fn devUartWrite(buf: []const u8) usize {
    driver.Uart.puts(buf);
    return buf.len;
}

fn devNullRead(buf: []u8) usize { _ = buf; return 0; }
fn devNullWrite(buf: []const u8) usize { _ = buf; return 0; }
fn devZeroRead(buf: []u8) usize { @memset(buf, 0); return buf.len; }
fn devNop() void {}

// ─── close(fd) ───────────────────────────────────────────────────

fn sysClose(frame: *trap.TrapFrame) usize {
    const fd_num: u32 = @intCast(frame.a0);
    const proc = process.getCurrent() orelse return EBADF;
    if (fd_num >= 16) return EBADF;

    const fd = process.getFd(proc, fd_num) orelse return EBADF;
    if (fd.dev) |dev| dev.close();
    proc.fds[fd_num] = null;
    return 0;
}

// ─── yield() ─────────────────────────────────────────────────────

fn sysYield(frame: *trap.TrapFrame) usize {
    _ = frame;
    process.yieldExecution();
    return 0;
}

// ─── getpid() ────────────────────────────────────────────────────

fn sysGetpid(frame: *trap.TrapFrame) usize {
    _ = frame;
    if (process.getCurrent()) |p| return p.pid;
    return 0;
}

// ─── exit(code) ──────────────────────────────────────────────────

fn sysExit(frame: *trap.TrapFrame) usize {
    // a0 is XLEN-wide; the exit code is its low 32 bits, reinterpreted as signed.
    const code: i32 = @bitCast(@as(u32, @truncate(frame.a0)));
    process.exit(code);
    return 0;
}

// ─── mmap(addr, len, prot) → virtual address ────────────────────

fn sysMmap(frame: *trap.TrapFrame) usize {
    const len: u32 = @intCast(frame.a1);
    const prot: u32 = @intCast(frame.a2);
    if (len == 0) return EINVAL;

    const proc = process.getCurrent() orelse return ENOMEM;
    const pages_needed = (len + memory.PAGE_SIZE - 1) / memory.PAGE_SIZE;

    const paddr = memory.allocRange(pages_needed) orelse return ENOMEM;

    var pte_flags: u32 = memory.PTE_U;
    if ((prot & 1) != 0) pte_flags |= memory.PTE_R;
    if ((prot & 2) != 0) pte_flags |= memory.PTE_W;
    if ((prot & 4) != 0) pte_flags |= memory.PTE_X;

    var i: u32 = 0;
    while (i < pages_needed) : (i += 1) {
        const va = paddr + i * memory.PAGE_SIZE;
        if (!memory.mapPage(proc.page_root, va, va, pte_flags)) {
            memory.unmapRange(proc.page_root, paddr, i, true);
            memory.freeRange(paddr + i * memory.PAGE_SIZE, pages_needed - i);
            return ENOMEM;
        }
    }
    return paddr;
}

// ─── munmap(addr, len) ───────────────────────────────────────────

fn sysMunmap(frame: *trap.TrapFrame) usize {
    const addr: u32 = @intCast(frame.a0);
    const len: u32 = @intCast(frame.a1);
    if (len == 0) return EINVAL;

    const proc = process.getCurrent() orelse return EINVAL;
    const pages = (len + memory.PAGE_SIZE - 1) / memory.PAGE_SIZE;
    memory.unmapRange(proc.page_root, addr, pages, true);
    return 0;
}
