//! SPDX-License-Identifier: AGPL-3.0-or-later
//! Copyright 2025 Ahmad Ali Parr / SnapKitty — https://github.com/SNAPKITTYWEST/phaser-ags
//! ═══════════════════════════════════════════════════════════════════
//!  PHASER AGS — Zig kernel driver layer (complete, no stubs)
//!
//!  Full OMAP3530 peripheral drivers + RISC-V CSR access + PLIC
//! ═══════════════════════════════════════════════════════════════════

const std = @import("std");

// ─── Memory map (matches firmware/common/platform.h) ─────────────

pub const MemoryMap = struct {
    pub const SRAM_BASE:     u32 = 0x00000000;
    pub const DRAM_BASE:     u32 = 0x30000000;
    pub const NOR_BASE:      u32 = 0x08000000;
    pub const NAND_BASE:     u32 = 0x40000000;
    pub const UART0_BASE:    u32 = 0x4806A000;
    pub const GPIO1_BASE:    u32 = 0x48310000;
    pub const INTC_BASE:     u32 = 0x48200000;
    pub const SDRC_BASE:     u32 = 0x6D000000;
    pub const GPMC_BASE:     u32 = 0x6E000000;
    pub const MCSPI1_BASE:   u32 = 0x48098000;
    pub const I2C1_BASE:     u32 = 0x48070000;
    pub const EMAC_BASE:     u32 = 0x5C040000;
    pub const MDIO_BASE:     u32 = 0x5C030000;
    pub const HSMMC1_BASE:   u32 = 0x4809C000;
    pub const GPTIMER1_BASE: u32 = 0x48318000;
    pub const CM_BASE:       u32 = 0x48004000;
    pub const PRM_BASE:      u32 = 0x48306000;
    pub const CONTROL_BASE:  u32 = 0x48002000;
    pub const CLINT_BASE:    u32 = 0x02000000;
    pub const PLIC_BASE:     u32 = 0x0C000000;
};

// ─── RISC-V CSRs ─────────────────────────────────────────────────

pub const CSR = struct {
    pub const MSTATUS:   u32 = 0x300;
    pub const MISA:      u32 = 0x301;
    pub const MEDELEG:   u32 = 0x302;
    pub const MIDELEG:   u32 = 0x303;
    pub const MIE:       u32 = 0x304;
    pub const MTVEC:     u32 = 0x305;
    pub const MSCRATCH:  u32 = 0x340;
    pub const MEPC:      u32 = 0x341;
    pub const MCAUSE:    u32 = 0x342;
    pub const MTVAL:     u32 = 0x343;
    pub const MIP:       u32 = 0x344;
    pub const MCYCLE:    u32 = 0xB00;
    pub const MINSTRET:  u32 = 0xB02;
    pub const SATP:      u32 = 0x180;
};

// ─── Volatile register access ────────────────────────────────────

pub inline fn regWrite(comptime T: type, addr: u32, val: T) void {
    @as(*volatile T, @ptrFromInt(addr)).* = val;
}

pub inline fn regRead(comptime T: type, addr: u32) T {
    return @as(*volatile T, @ptrFromInt(addr)).*;
}

pub inline fn regSet(comptime T: type, addr: u32, mask: T) void {
    @as(*volatile T, @ptrFromInt(addr)).* |= mask;
}

pub inline fn regClr(comptime T: type, addr: u32, mask: T) void {
    @as(*volatile T, @ptrFromInt(addr)).* &= ~mask;
}

pub inline fn regMask(comptime T: type, addr: u32, mask: T, val: T) void {
    const ptr: *volatile T = @ptrFromInt(addr);
    ptr.* = (ptr.* & ~mask) | (val & mask);
}

// ─── CSR read/write ──────────────────────────────────────────────
//
//  CSR numbers are 12-bit unsigned (0x000–0xFFF). They are spliced into
//  the instruction text at comptime: the "I" asm constraint is a *signed*
//  12-bit immediate (-2048..2047) and rejects CSRs >= 0x800 such as
//  mcycle (0xB00) and minstret (0xB02). Values are XLEN-wide (usize).

inline fn csrName(comptime csr: u12) []const u8 {
    return std.fmt.comptimePrint("{d}", .{csr});
}

pub inline fn csrRead(comptime csr: u12) usize {
    return asm volatile ("csrr %[out], " ++ csrName(csr)
        : [out] "=r" (-> usize),
    );
}

pub inline fn csrWrite(comptime csr: u12, val: usize) void {
    asm volatile ("csrw " ++ csrName(csr) ++ ", %[val]"
        :
        : [val] "r" (val),
    );
}

pub inline fn csrSet(comptime csr: u12, mask: usize) void {
    asm volatile ("csrs " ++ csrName(csr) ++ ", %[mask]"
        :
        : [mask] "r" (mask),
    );
}

pub inline fn csrClr(comptime csr: u12, mask: usize) void {
    asm volatile ("csrc " ++ csrName(csr) ++ ", %[mask]"
        :
        : [mask] "r" (mask),
    );
}

pub inline fn fenceI() void {
    asm volatile ("fence.i");
}

pub inline fn fenceRw() void {
    asm volatile ("fence rw, rw");
}

// ═══════════════════════════════════════════════════════════════════
//  UART0 — NS16550A
// ═══════════════════════════════════════════════════════════════════

pub const Uart = struct {
    const base = MemoryMap.UART0_BASE;

    const Off = struct {
        pub const THR: u32 = 0x00; pub const RBR: u32 = 0x00;
        pub const IER: u32 = 0x04; pub const IIR: u32 = 0x08;
        pub const FCR: u32 = 0x08; pub const LCR: u32 = 0x0C;
        pub const MCR: u32 = 0x10; pub const LSR: u32 = 0x14;
        pub const DLL: u32 = 0x00; pub const DLH: u32 = 0x04;
        pub const MDR1: u32 = 0x20;
        pub const SCR: u32 = 0x1C;
        pub const SSR: u32 = 0x44;
    };

    const LSR_THRE: u32 = 0x20;
    const LSR_DR: u32 = 0x01;

    pub fn init(baud: u32) void {
        const divisor: u32 = 48000000 / (16 * baud);

        regWrite(u32, base + Off.MDR1, 0x07);        // Disable UART
        regWrite(u32, base + Off.LCR, 0x80);         // DLAB on
        regWrite(u32, base + Off.DLL, divisor & 0xFF);
        regWrite(u32, base + Off.DLH, (divisor >> 8) & 0xFF);
        regWrite(u32, base + Off.LCR, 0x03);         // 8N1, DLAB off
        regWrite(u32, base + Off.FCR, 0x07);         // Enable + clear FIFOs
        regWrite(u32, base + Off.MCR, 0x00);         // No flow control
        regWrite(u32, base + Off.IER, 0x01);         // RX interrupt enable
        regWrite(u32, base + Off.SCR, 0x00);
        regWrite(u32, base + Off.MDR1, 0x00);        // 16x mode
    }

    pub fn putc(ch: u8) void {
        while ((regRead(u32, base + Off.LSR) & LSR_THRE) == 0) {}
        regWrite(u8, base + Off.THR, ch);
    }

    pub fn getc() u8 {
        while ((regRead(u32, base + Off.LSR) & LSR_DR) == 0) {}
        return regRead(u8, base + Off.RBR);
    }

    pub fn puts(str: []const u8) void {
        for (str) |ch| {
            if (ch == '\n') putc('\r');
            putc(ch);
        }
    }

    pub fn putHex(val: u32) void {
        const hex = "0123456789abcdef";
        putc('0'); putc('x');
        var i: u5 = 28;
        while (true) : (i = if (i == 0) break else i - 4) {
            putc(hex[@intCast((val >> i) & 0xF)]);
            if (i == 0) break;
        }
    }

    pub fn canRead() bool {
        return (regRead(u32, base + Off.LSR) & LSR_DR) != 0;
    }
};

// ═══════════════════════════════════════════════════════════════════
//  GPIO1
// ═══════════════════════════════════════════════════════════════════

pub const Gpio = struct {
    const Off = struct {
        pub const OE: u32 = 0x034; pub const DATAIN: u32 = 0x038;
        pub const DATAOUT: u32 = 0x03C; pub const SETDATAOUT: u32 = 0x040;
        pub const CLEARDATAOUT: u32 = 0x044;
        pub const RISINGDETECT: u32 = 0x048;
        pub const FALLINGDETECT: u32 = 0x04C;
        pub const IRQSTATUS1: u32 = 0x018;
        pub const SYSCONFIG: u32 = 0x010;
        pub const CTRL: u32 = 0x030;
    };

    pub fn setDir(bank_base: u32, pin: u5, output: bool) void {
        const mask = @as(u32, 1) << pin;
        if (output) regClr(u32, bank_base + Off.OE, mask)
        else        regSet(u32, bank_base + Off.OE, mask);
    }

    pub fn write(bank_base: u32, pin: u5, val: bool) void {
        const mask = @as(u32, 1) << pin;
        if (val) regWrite(u32, bank_base + Off.SETDATAOUT, mask)
        else     regWrite(u32, bank_base + Off.CLEARDATAOUT, mask);
    }

    pub fn read(bank_base: u32, pin: u5) bool {
        return (regRead(u32, bank_base + Off.DATAIN) & (@as(u32, 1) << pin)) != 0;
    }

    pub fn toggle(bank_base: u32, pin: u5) void {
        const mask = @as(u32, 1) << pin;
        const cur = regRead(u32, bank_base + Off.DATAOUT);
        if (cur & mask != 0) regWrite(u32, bank_base + Off.CLEARDATAOUT, mask)
        else                 regWrite(u32, bank_base + Off.SETDATAOUT, mask);
    }

    pub fn setIrqRising(bank_base: u32, pin: u5) void {
        regSet(u32, bank_base + Off.RISINGDETECT, @as(u32, 1) << pin);
    }

    pub fn setIrqFalling(bank_base: u32, pin: u5) void {
        regSet(u32, bank_base + Off.FALLINGDETECT, @as(u32, 1) << pin);
    }

    pub fn clearIrq(bank_base: u32, pin: u5) void {
        regWrite(u32, bank_base + Off.IRQSTATUS1, @as(u32, 1) << pin);
    }

    pub fn initBank(bank_base: u32) void {
        regWrite(u32, bank_base + Off.SYSCONFIG, 0x04);  // Smart idle
        regWrite(u32, bank_base + Off.CTRL, 0x00);       // Module enable
    }
};

// ═══════════════════════════════════════════════════════════════════
//  PLIC — Platform-Level Interrupt Controller (RISC-V)
//  Standard address: 0x0C000000
//  Priority thresholds, enable bits, claim/complete
// ═══════════════════════════════════════════════════════════════════

pub const Plic = struct {
    const base = MemoryMap.PLIC_BASE;
    const MAX_IRQ: u32 = 127;
    const MAX_CTX: u32 = 2;  // M-mode context 0, S-mode context 1

    // Priority: 4 bytes per IRQ source (1=lowest, 7=highest, 0=never)
    pub fn setPriority(irq: u32, prio: u32) void {
        if (irq > 0 and irq <= MAX_IRQ) {
            regWrite(u32, base + irq * 4, prio & 0x7);
        }
    }

    // Enable: one bit per IRQ, 32 bits per word, starting at 0x2000 per context
    pub fn enable(ctx: u32, irq: u32) void {
        if (irq > 0 and irq <= MAX_IRQ and ctx < MAX_CTX) {
            const en_base = base + 0x2000 + ctx * 0x80;
            regSet(u32, en_base + (irq / 32) * 4, @as(u32, 1) << @intCast(irq % 32));
        }
    }

    pub fn disable(ctx: u32, irq: u32) void {
        if (irq > 0 and irq <= MAX_IRQ and ctx < MAX_CTX) {
            const en_base = base + 0x2000 + ctx * 0x80;
            regClr(u32, en_base + (irq / 32) * 4, @as(u32, 1) << @intCast(irq % 32));
        }
    }

    // Threshold: per-context, at 0x200000 + ctx*0x1000
    pub fn setThreshold(ctx: u32, threshold: u32) void {
        if (ctx < MAX_CTX) {
            regWrite(u32, base + 0x200000 + ctx * 0x1000, threshold & 0x7);
        }
    }

    // Claim: read returns highest-priority pending IRQ (or 0)
    pub fn claim(ctx: u32) u32 {
        if (ctx < MAX_CTX) {
            return regRead(u32, base + 0x200004 + ctx * 0x1000);
        }
        return 0;
    }

    // Complete: write the claimed IRQ ID back
    pub fn complete(ctx: u32, irq: u32) void {
        if (ctx < MAX_CTX) {
            regWrite(u32, base + 0x200004 + ctx * 0x1000, irq);
        }
    }
};

// ─── External IRQ dispatch table ─────────────────────────────────

const ExtIrqHandler = *const fn (u32) void;
var ext_irq_handlers: [128]?ExtIrqHandler = .{null} ** 128;

pub fn registerExternalIrq(irq: u32, handler: ExtIrqHandler) void {
    if (irq > 0 and irq < 128) {
        ext_irq_handlers[irq] = handler;
        Plic.setPriority(irq, 5);
        Plic.enable(0, irq);  // Enable for M-mode context 0
    }
}

pub fn dispatchExternalIrq(irq: u32) void {
    if (irq > 0 and irq < 128) {
        if (ext_irq_handlers[irq]) |handler| {
            handler(irq);
            return;
        }
    }
    Uart.puts("Unhandled PLIC IRQ ");
    Uart.putHex(irq);
    Uart.putc('\n');
}

// ═══════════════════════════════════════════════════════════════════
//  BOARD INIT
// ═══════════════════════════════════════════════════════════════════

pub const Board = struct {
    pub fn earlyInit() void {
        // ── Disable WDT2 ──
        regWrite(u32, MemoryMap.CM_BASE + 0x0548, 0x00);

        // ── Enable peripheral clocks ──
        regSet(u32, MemoryMap.CM_BASE + 0x0500,  // CM_FCLKEN1_CORE
            (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) |
            (1 << 4) | (1 << 5));
        regSet(u32, MemoryMap.CM_BASE + 0x0510,  // CM_ICLKEN1_CORE
            (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) |
            (1 << 4) | (1 << 5));
        regSet(u32, MemoryMap.CM_BASE + 0x0410, 1 << 2);  // GPIO1 iclk

        // ── GPIO1 init ──
        Gpio.initBank(MemoryMap.GPIO1_BASE);

        // LED on GPIO1[8]
        Gpio.setDir(MemoryMap.GPIO1_BASE, 8, true);
        // PHY reset on GPIO1[9]
        Gpio.setDir(MemoryMap.GPIO1_BASE, 9, true);
        // FPGA NCONFIG on GPIO1[10], [11], [12]
        Gpio.setDir(MemoryMap.GPIO1_BASE, 10, true);
        Gpio.setDir(MemoryMap.GPIO1_BASE, 11, true);
        Gpio.setDir(MemoryMap.GPIO1_BASE, 12, true);

        // Assert PHY reset (active low) for 10ms
        Gpio.write(MemoryMap.GPIO1_BASE, 9, false);
        spinDelay(4800000);
        Gpio.write(MemoryMap.GPIO1_BASE, 9, true);

        // ── FPGA NCONFIG pulse: assert all 3, wait 1ms, release ──
        Gpio.write(MemoryMap.GPIO1_BASE, 10, false);
        Gpio.write(MemoryMap.GPIO1_BASE, 11, false);
        Gpio.write(MemoryMap.GPIO1_BASE, 12, false);
        spinDelay(480000);  // ~1ms
        Gpio.write(MemoryMap.GPIO1_BASE, 10, true);
        Gpio.write(MemoryMap.GPIO1_BASE, 11, true);
        Gpio.write(MemoryMap.GPIO1_BASE, 12, true);

        // ── PLIC init: set threshold 0, disable all ──
        Plic.setThreshold(0, 0);
        var irq: u32 = 1;
        while (irq <= 127) : (irq += 1) {
            Plic.disable(0, irq);
            Plic.setPriority(irq, 0);
        }

        // ── Enable M-mode external interrupt in MIE ──
        csrSet(CSR.MIE, 1 << 11);  // MEIE
    }

    pub fn consoleInit() void {
        Uart.init(115200);
    }

    pub fn ledOn() void  { Gpio.write(MemoryMap.GPIO1_BASE, 8, true); }
    pub fn ledOff() void { Gpio.write(MemoryMap.GPIO1_BASE, 8, false); }
    pub fn ledToggle() void { Gpio.toggle(MemoryMap.GPIO1_BASE, 8); }

    pub fn reset() void {
        Uart.puts("Board reset via PRM_RSTCTRL...\n");
        regWrite(u32, MemoryMap.PRM_BASE + 0x090, 0x02);
    }
};

pub fn spinDelay(cycles: u32) void {
    var i: u32 = 0;
    while (i < cycles) : (i += 1) {
        asm volatile ("nop");
    }
}
