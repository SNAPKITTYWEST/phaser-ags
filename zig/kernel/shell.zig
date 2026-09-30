//! SPDX-License-Identifier: AGPL-3.0-or-later
//! Copyright 2025 Ahmad Ali Parr / SnapKitty � https://github.com/SNAPKITTYWEST/phaser-ags
//! ═══════════════════════════════════════════════════════════════════
//!  PHASER AGS — Kernel shell (complete, no stubs)
//!
//!  All commands fully implemented. Process management, VM control,
//!  memory inspection, register dumps, system reset.
//! ═══════════════════════════════════════════════════════════════════

const std = @import("std");
const driver = @import("driver.zig");
const process = @import("process.zig");
const memory = @import("memory.zig");
const timer = @import("timer.zig");

const MAX_LINE: usize = 128;
var line_buf: [MAX_LINE]u8 = undefined;
var line_len: usize = 0;

// ─── Read a line with editing ────────────────────────────────────

fn readLine() []const u8 {
    line_len = 0;
    while (true) {
        const ch = driver.Uart.getc();
        if (ch == '\r' or ch == '\n') {
            driver.Uart.puts("\r\n");
            line_buf[line_len] = 0;
            return line_buf[0..line_len];
        } else if (ch == 0x08 or ch == 0x7F) {
            if (line_len > 0) {
                line_len -= 1;
                driver.Uart.puts("\x08 \x08");
            }
        } else if (ch == 0x15) {  // Ctrl-U: kill line
            while (line_len > 0) {
                line_len -= 1;
                driver.Uart.puts("\x08 \x08");
            }
        } else if (line_len < MAX_LINE - 1) {
            line_buf[line_len] = ch;
            line_len += 1;
            driver.Uart.putc(ch);
        }
    }
}

// ─── Hex parser ──────────────────────────────────────────────────

fn parseHex(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var val: u32 = 0;
    var i: usize = 0;
    if (s.len > 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X')) i = 2;
    while (i < s.len) : (i += 1) {
        val <<= 4;
        switch (s[i]) {
            '0'...'9' => val |= s[i] - '0',
            'a'...'f' => val |= s[i] - 'a' + 10,
            'A'...'F' => val |= s[i] - 'A' + 10,
            else => return null,
        }
    }
    return val;
}

fn parseDec(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var val: u32 = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') return null;
        val = val * 10 + (ch - '0');
    }
    return val;
}

// ─── Tokenize ────────────────────────────────────────────────────

fn tokenize(input: []const u8) [5][]const u8 {
    var tokens: [5][]const u8 = .{""} ** 5;
    var ti: usize = 0;
    var start: usize = 0;
    var in_token = false;
    for (input, 0..) |ch, i| {
        if (ch == ' ' or ch == '\t' or ch == 0) {
            if (in_token) {
                if (ti < 5) tokens[ti] = input[start..i];
                ti += 1;
                in_token = false;
            }
        } else if (!in_token) {
            start = i;
            in_token = true;
        }
    }
    if (in_token and ti < 5) tokens[ti] = input[start..line_len];
    return tokens;
}

// ─── Commands ────────────────────────────────────────────────────

fn cmdMd(tokens: [5][]const u8) void {
    const addr = parseHex(tokens[1]) orelse { driver.Uart.puts("md <addr> [count]\n"); return; };
    const count = if (tokens[2].len > 0) parseHex(tokens[2]) orelse 16 else 16;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const a = addr + i * 4;
        if (a < 0x02000000 or (a >= 0x48000000 and a < 0x4A000000) or a >= 0x20000000) {
            const val = driver.regRead(u32, a);
            if (i % 4 == 0) {
                driver.Uart.putc('\n');
                driver.Uart.putHex(a);
                driver.Uart.puts(": ");
            }
            driver.Uart.putHex(val);
            driver.Uart.putc(' ');
        } else {
            driver.Uart.puts("??? ");
        }
    }
    driver.Uart.putc('\n');
}

fn cmdMw(tokens: [5][]const u8) void {
    const addr = parseHex(tokens[1]) orelse { driver.Uart.puts("mw <addr> <value>\n"); return; };
    const val = parseHex(tokens[2]) orelse { driver.Uart.puts("mw <addr> <value>\n"); return; };
    driver.regWrite(u32, addr, val);
    driver.Uart.putHex(addr);
    driver.Uart.puts(" <- ");
    driver.Uart.putHex(val);
    driver.Uart.putc('\n');
}

fn cmdMwb(tokens: [5][]const u8) void {
    const addr = parseHex(tokens[1]) orelse { driver.Uart.puts("mwb <addr> <byte>\n"); return; };
    const val = parseHex(tokens[2]) orelse { driver.Uart.puts("mwb <addr> <byte>\n"); return; };
    driver.regWrite(u8, addr, @intCast(val & 0xFF));
    driver.Uart.putHex(addr);
    driver.Uart.puts(" <- ");
    driver.Uart.putHex(val & 0xFF);
    driver.Uart.putc('\n');
}

fn cmdGo(tokens: [5][]const u8) void {
    const addr = parseHex(tokens[1]) orelse { driver.Uart.puts("go <addr>\n"); return; };
    driver.Uart.puts("Jump to ");
    driver.Uart.putHex(addr);
    driver.Uart.puts(" (disabling interrupts)...\n");
    driver.csrClr(driver.CSR.MSTATUS, 0x08);
    const fn_ptr: *const fn () callconv(.C) void = @ptrFromInt(addr);
    fn_ptr();
    driver.csrSet(driver.CSR.MSTATUS, 0x08);
    driver.Uart.puts("Returned from ");
    driver.Uart.putHex(addr);
    driver.Uart.putc('\n');
}

fn cmdReset() void {
    driver.Board.reset();
}

fn cmdRegs() void {
    const csrs = .{
        .{ "mstatus",  0x300 }, .{ "misa",     0x301 },
        .{ "mie",       0x304 }, .{ "mtvec",     0x305 },
        .{ "mscratch",  0x340 }, .{ "mepc",      0x341 },
        .{ "mcause",    0x342 }, .{ "satp",      0x180 },
        .{ "mcycle",    0xB00 }, .{ "minstret",  0xB02 },
        .{ "mip",       0x344 },
    };
    inline for (csrs) |csr| {
        const val = driver.csrRead(csr[1]);
        driver.Uart.puts(csr[0]);
        driver.Uart.puts(": ");
        driver.Uart.putHex(val);
        driver.Uart.putc('\n');
    }
}

fn cmdProc() void {
    process.dumpAll();
}

fn cmdSpawn(tokens: [5][]const u8) void {
    const addr = parseHex(tokens[1]) orelse { driver.Uart.puts("spawn <entry_addr> [name]\n"); return; };
    const name = if (tokens[2].len > 0) tokens[2] else "user";
    if (process.create(addr, name)) |p| {
        driver.Uart.puts("Spawned proc ");
        driver.Uart.putHex(p.pid);
        driver.Uart.putc('\n');
    } else {
        driver.Uart.puts("Spawn failed\n");
    }
}

fn cmdKill(tokens: [5][]const u8) void {
    const pid = parseHex(tokens[1]) orelse parseDec(tokens[1]) orelse { driver.Uart.puts("kill <pid>\n"); return; };
    process.kill(@intCast(pid));
}

fn cmdVm(tokens: [5][]const u8) void {
    if (tokens[1].len >= 2 and tokens[1][0] == 'o' and tokens[1][1] == 'n') {
        if (memory.getCurrentRoot()) |root| {
            driver.Uart.puts("VM: already enabled, root=");
            driver.Uart.putHex(@intFromPtr(root));
            driver.Uart.putc('\n');
            return;
        }
        const root = memory.createAddressSpace() orelse {
            driver.Uart.puts("VM: alloc failed\n");
            return;
        };
        memory.switchToPageTable(root);
        driver.Uart.puts("SV32 enabled, root=");
        driver.Uart.putHex(@intFromPtr(root));
        driver.Uart.putc('\n');
    } else {
        memory.disableMmu();
        driver.Uart.puts("VM: disabled\n");
    }
}

fn cmdVmMap(tokens: [5][]const u8) void {
    const vaddr = parseHex(tokens[1]) orelse { driver.Uart.puts("vmmap <vaddr> <paddr> <flags>\n"); return; };
    const paddr = parseHex(tokens[2]) orelse { driver.Uart.puts("vmmap <vaddr> <paddr> <flags>\n"); return; };
    const flags = if (tokens[3].len > 0) parseHex(tokens[3]) orelse 7 else 7;

    const root = memory.getCurrentRoot() orelse {
        driver.Uart.puts("VM not enabled\n");
        return;
    };

    if (memory.mapPage(root, vaddr, paddr, flags)) {
        driver.Uart.puts("Mapped ");
        driver.Uart.putHex(vaddr);
        driver.Uart.puts(" -> ");
        driver.Uart.putHex(paddr);
        driver.Uart.puts(" flags=");
        driver.Uart.putHex(flags);
        driver.Uart.putc('\n');
    } else {
        driver.Uart.puts("Map failed\n");
    }
}

fn cmdVmTranslate(tokens: [5][]const u8) void {
    const vaddr = parseHex(tokens[1]) orelse { driver.Uart.puts("vmtrans <vaddr>\n"); return; };
    const root = memory.getCurrentRoot() orelse {
        driver.Uart.puts("VM not enabled\n");
        return;
    };
    if (memory.translate(root, vaddr)) |pa| {
        driver.Uart.putHex(vaddr);
        driver.Uart.puts(" -> ");
        driver.Uart.putHex(pa);
        driver.Uart.putc('\n');
    } else {
        driver.Uart.puts("Translation failed (not mapped)\n");
    }
}

fn cmdTick() void {
    const ticks = timer.getTickCount();
    driver.Uart.puts("Timer ticks: ");
    driver.Uart.putHex(@intCast(ticks));
    driver.Uart.putc('\n');
}

fn cmdPages() void {
    driver.Uart.puts("Pages: ");
    driver.Uart.putHex(memory.pageCount());
    driver.Uart.puts(" total, ");
    driver.Uart.putHex(memory.freePageCount());
    driver.Uart.puts(" free (");
    driver.Uart.putHex(memory.freePageCount() * memory.PAGE_SIZE);
    driver.Uart.puts(" bytes)\n");
}

fn cmdReap() void {
    const count = process.reapZombies();
    driver.Uart.puts("Reaped ");
    driver.Uart.putHex(count);
    driver.Uart.puts(" zombie(s)\n");
}

fn cmdLed(tokens: [5][]const u8) void {
    if (tokens[1].len == 0) { driver.Uart.puts("led <on|off|toggle>\n"); return; }
    if (std.mem.eql(u8, tokens[1], "on"))     driver.Board.ledOn()
    else if (std.mem.eql(u8, tokens[1], "off"))    driver.Board.ledOff()
    else if (std.mem.eql(u8, tokens[1], "toggle")) driver.Board.ledToggle()
    else driver.Uart.puts("led <on|off|toggle>\n");
}

fn cmdEcho(tokens: [5][]const u8) void {
    var i: usize = 1;
    while (i < 5 and tokens[i].len > 0) : (i += 1) {
        if (i > 1) driver.Uart.putc(' ');
        driver.Uart.puts(tokens[i]);
    }
    driver.Uart.putc('\n');
}

fn cmdHelp() void {
    driver.Uart.puts(
        \\md <addr> [n]       Memory display (32-bit)
        \\mw <addr> <val>     Memory write (32-bit)
        \\mwb <addr> <byte>   Memory write (8-bit)
        \\go <addr>           Jump to address
        \\reset               Board reset
        \\regs                Dump RISC-V CSRs
        \\proc                List processes
        \\spawn <addr> [name] Create process
        \\kill <pid>          Kill process
        \\reap                Reap zombie processes
        \\vm <on|off>         SV32 MMU toggle
        \\vmmap <va> <pa> <f> Map a page
        \\vmtrans <va>        Translate VA→PA
        \\tick                Timer tick count
        \\pages               Page allocator status
        \\led <on|off|tog>    LED control
        \\echo <text>         Print text
        \\help                This message
        \\
    );
}

// ─── Main shell loop ─────────────────────────────────────────────

pub fn run() void {
    driver.Uart.puts("phaser-ags> ");

    while (true) {
        const line = readLine();
        if (line.len == 0) {
            driver.Uart.puts("phaser-ags> ");
            continue;
        }

        const tokens = tokenize(line);
        if (tokens[0].len == 0) {
            driver.Uart.puts("phaser-ags> ");
            continue;
        }

        const cmd = tokens[0];

        if (std.mem.eql(u8, cmd, "md"))       cmdMd(tokens)
        else if (std.mem.eql(u8, cmd, "mw"))      cmdMw(tokens)
        else if (std.mem.eql(u8, cmd, "mwb"))     cmdMwb(tokens)
        else if (std.mem.eql(u8, cmd, "go"))       cmdGo(tokens)
        else if (std.mem.eql(u8, cmd, "reset"))    cmdReset()
        else if (std.mem.eql(u8, cmd, "regs"))     cmdRegs()
        else if (std.mem.eql(u8, cmd, "proc"))     cmdProc()
        else if (std.mem.eql(u8, cmd, "spawn"))    cmdSpawn(tokens)
        else if (std.mem.eql(u8, cmd, "kill"))     cmdKill(tokens)
        else if (std.mem.eql(u8, cmd, "vm"))       cmdVm(tokens)
        else if (std.mem.eql(u8, cmd, "vmmap"))    cmdVmMap(tokens)
        else if (std.mem.eql(u8, cmd, "vmtrans"))  cmdVmTranslate(tokens)
        else if (std.mem.eql(u8, cmd, "tick"))     cmdTick()
        else if (std.mem.eql(u8, cmd, "pages"))    cmdPages()
        else if (std.mem.eql(u8, cmd, "reap"))     cmdReap()
        else if (std.mem.eql(u8, cmd, "led"))      cmdLed(tokens)
        else if (std.mem.eql(u8, cmd, "echo"))     cmdEcho(tokens)
        else if (std.mem.eql(u8, cmd, "help"))     cmdHelp()
        else {
            driver.Uart.puts("Unknown: ");
            driver.Uart.puts(cmd);
            driver.Uart.puts(" (type 'help' for commands)\n");
        }

        driver.Uart.puts("phaser-ags> ");
    }
}
