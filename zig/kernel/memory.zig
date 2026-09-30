//! SPDX-License-Identifier: AGPL-3.0-or-later
//! Copyright 2025 Ahmad Ali Parr / SnapKitty � https://github.com/SNAPKITTYWEST/phaser-ags
//! ═══════════════════════════════════════════════════════════════════
//!  PHASER AGS — Physical page allocator + SV32 virtual memory
//!  (complete, no stubs)
//!
//!  - Bitmap page allocator with alloc/free/allocRange
//!  - SV32 two-level page tables with map/unmap/translate
//!  - TLB management (sfence.vma)
//!  - Per-process address space creation/teardown
//! ═══════════════════════════════════════════════════════════════════

const std = @import("std");
const driver = @import("driver.zig");

pub const PAGE_SIZE: u32 = 4096;
pub const PAGE_SHIFT: u5 = 12;
pub const PAGE_MASK: u32 = PAGE_SIZE - 1;

// ─── PTE bits ────────────────────────────────────────────────────

pub const PTE_V:  u32 = 1 << 0;
pub const PTE_R:  u32 = 1 << 1;
pub const PTE_W:  u32 = 1 << 2;
pub const PTE_X:  u32 = 1 << 3;
pub const PTE_U:  u32 = 1 << 4;
pub const PTE_G:  u32 = 1 << 5;
pub const PTE_A:  u32 = 1 << 6;
pub const PTE_D:  u32 = 1 << 7;

pub const PTE_RWX: u32 = PTE_R | PTE_W | PTE_X;
pub const PTE_RW:  u32 = PTE_R | PTE_W;
pub const PTE_RX:  u32 = PTE_R | PTE_X;

// ═══════════════════════════════════════════════════════════════════
//  PAGE ALLOCATOR
// ═══════════════════════════════════════════════════════════════════

extern var __pages_start: u8;
extern var __pages_end: u8;

const PageAlloc = struct {
    base: u32,
    total_pages: u32,
    free_count: u32,
    bitmap: [*]u32,
    bitmap_words: u32,
};

var palloc: PageAlloc = undefined;

pub fn init() void {
    const base = @intFromPtr(&__pages_start);
    const end = @intFromPtr(&__pages_end);
    const total = (end - base) / PAGE_SIZE;
    const bitmap_words = (total + 31) / 32;

    palloc = .{
        .base = base,
        .total_pages = total,
        .free_count = total,
        .bitmap = @ptrFromInt(base),
        .bitmap_words = bitmap_words,
    };

    // Zero bitmap (all pages free)
    var i: u32 = 0;
    while (i < bitmap_words) : (i += 1) {
        palloc.bitmap[i] = 0;
    }

    // Reserve pages used by the bitmap itself
    const bitmap_pages = (bitmap_words * 4 + PAGE_SIZE - 1) / PAGE_SIZE;
    i = 0;
    while (i < bitmap_pages) : (i += 1) {
        markAllocated(i);
    }

    driver.Uart.puts("Page allocator: ");
    driver.Uart.putHex(palloc.free_count * PAGE_SIZE);
    driver.Uart.puts(" bytes free, ");
    driver.Uart.putHex(palloc.total_pages);
    driver.Uart.puts(" total pages\n");
}

inline fn markAllocated(idx: u32) void {
    palloc.bitmap[idx / 32] |= @as(u32, 1) << @intCast(idx % 32);
    palloc.free_count -= 1;
}

inline fn markFree(idx: u32) void {
    palloc.bitmap[idx / 32] &= ~(@as(u32, 1) << @intCast(idx % 32));
    palloc.free_count += 1;
}

inline fn isAllocated(idx: u32) bool {
    return (palloc.bitmap[idx / 32] & (@as(u32, 1) << @intCast(idx % 32))) != 0;
}

pub fn allocPage() ?u32 {
    var w: u32 = 0;
    while (w < palloc.bitmap_words) : (w += 1) {
        if (palloc.bitmap[w] == 0xFFFFFFFF) continue;
        var bits = palloc.bitmap[w];
        var bit: u5 = 0;
        while (bit < 32) : (bit += 1) {
            if (bits & 1 == 0) {
                const idx = w * 32 + bit;
                if (idx >= palloc.total_pages) return null;
                markAllocated(idx);
                const addr = palloc.base + idx * PAGE_SIZE;
                zeroPage(addr);
                return addr;
            }
            bits >>= 1;
        }
    }
    driver.Uart.puts("OOM: no free pages\n");
    return null;
}

pub fn allocRange(count: u32) ?u32 {
    if (count == 0) return null;
    if (count == 1) return allocPage();

    var run_start: u32 = 0;
    var run_len: u32 = 0;
    var idx: u32 = 0;
    while (idx < palloc.total_pages) : (idx += 1) {
        if (!isAllocated(idx)) {
            if (run_len == 0) run_start = idx;
            run_len += 1;
            if (run_len >= count) {
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    markAllocated(run_start + i);
                }
                const addr = palloc.base + run_start * PAGE_SIZE;
                zeroRange(addr, count);
                return addr;
            }
        } else {
            run_len = 0;
        }
    }
    driver.Uart.puts("OOM: no contiguous range of ");
    driver.Uart.putHex(count);
    driver.Uart.puts(" pages\n");
    return null;
}

pub fn freePage(addr: u32) void {
    if (addr < palloc.base) return;
    const idx = (addr - palloc.base) / PAGE_SIZE;
    if (idx >= palloc.total_pages) return;
    if (!isAllocated(idx)) return;
    markFree(idx);
}

pub fn freeRange(addr: u32, count: u32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        freePage(addr + i * PAGE_SIZE);
    }
}

pub fn pageCount() u32 {
    return palloc.total_pages;
}

pub fn freePageCount() u32 {
    return palloc.free_count;
}

fn zeroPage(addr: u32) void {
    const ptr: [*]u64 = @ptrFromInt(addr);
    var i: u32 = 0;
    while (i < PAGE_SIZE / 8) : (i += 1) {
        ptr[i] = 0;
    }
}

fn zeroRange(addr: u32, pages: u32) void {
    var i: u32 = 0;
    while (i < pages) : (i += 1) {
        zeroPage(addr + i * PAGE_SIZE);
    }
}

// ═══════════════════════════════════════════════════════════════════
//  SV32 PAGE TABLES
// ═══════════════════════════════════════════════════════════════════

pub const PageTable = [1024]u32;

pub fn allocPageTable() ?*PageTable {
    return @ptrFromInt(allocPage() orelse return null);
}

pub fn freePageTable(pt: *PageTable) void {
    for (pt) |pte| {
        if ((pte & PTE_V) != 0 and !isLeafPte(pte)) {
            const l2_paddr = ptePpn(pte) << PAGE_SHIFT;
            freePage(l2_paddr);
        }
    }
    freePage(@intFromPtr(pt));
}

inline fn isLeafPte(pte: u32) bool {
    return (pte & (PTE_R | PTE_W | PTE_X)) != 0;
}

inline fn ptePpn(pte: u32) u32 {
    return (pte >> 10) & 0x3FFFFF;
}

inline fn makePte(ppn: u32, flags: u32) u32 {
    return (ppn << 10) | flags;
}

// ─── Map a 4KB page ──────────────────────────────────────────────

pub fn mapPage(root: *PageTable, vaddr: u32, paddr: u32, flags: u32) bool {
    const vpn1: u12 = @intCast((vaddr >> 22) & 0x3FF);
    const vpn0: u10 = @intCast((vaddr >> 12) & 0x3FF);

    var l1_pte = root[vpn1];

    if (isLeafPte(l1_pte)) return false;  // megapage conflict

    var l2: *PageTable = undefined;
    if ((l1_pte & PTE_V) == 0) {
        l2 = allocPageTable() orelse return false;
        root[vpn1] = makePte(@intFromPtr(l2) >> PAGE_SHIFT, PTE_V);
    } else {
        l2 = @ptrFromInt(ptePpn(l1_pte) << PAGE_SHIFT);
    }

    const ppn = paddr >> PAGE_SHIFT;
    l2[vpn0] = makePte(ppn, flags | PTE_A | PTE_D);
    flushTlbPage(vaddr);
    return true;
}

// ─── Map a 4MB megapage ──────────────────────────────────────────

pub fn mapMegaPage(root: *PageTable, vaddr: u32, paddr: u32, flags: u32) bool {
    const vpn1: u12 = @intCast((vaddr >> 22) & 0x3FF);
    if ((vaddr & 0x3FFFFF) != 0 or (paddr & 0x3FFFFF) != 0) return false;
    root[vpn1] = makePte(paddr >> PAGE_SHIFT, flags | PTE_A | PTE_D);
    flushTlbPage(vaddr);
    return true;
}

// ─── Unmap a 4KB page ────────────────────────────────────────────

pub fn unmapPage(root: *PageTable, vaddr: u32) ?u32 {
    const vpn1: u12 = @intCast((vaddr >> 22) & 0x3FF);
    const vpn0: u10 = @intCast((vaddr >> 12) & 0x3FF);

    const l1_pte = root[vpn1];
    if ((l1_pte & PTE_V) == 0) return null;
    if (isLeafPte(l1_pte)) return null;

    const l2: *PageTable = @ptrFromInt(ptePpn(l1_pte) << PAGE_SHIFT);
    const l0_pte = l2[vpn0];
    if ((l0_pte & PTE_V) == 0) return null;

    l2[vpn0] = 0;
    flushTlbPage(vaddr);
    return ptePpn(l0_pte) << PAGE_SHIFT;
}

// ─── Unmap a 4MB megapage ────────────────────────────────────────

pub fn unmapMegaPage(root: *PageTable, vaddr: u32) ?u32 {
    const vpn1: u12 = @intCast((vaddr >> 22) & 0x3FF);
    const l1_pte = root[vpn1];
    if ((l1_pte & PTE_V) == 0) return null;
    if (!isLeafPte(l1_pte)) return null;

    root[vpn1] = 0;
    flushTlbPage(vaddr);
    return ptePpn(l1_pte) << PAGE_SHIFT;
}

// ─── Translate virtual → physical ────────────────────────────────

pub fn translate(root: *PageTable, vaddr: u32) ?u32 {
    const vpn1: u12 = @intCast((vaddr >> 22) & 0x3FF);
    const vpn0: u10 = @intCast((vaddr >> 12) & 0x3FF);
    const offset = vaddr & PAGE_MASK;

    const l1_pte = root[vpn1];
    if ((l1_pte & PTE_V) == 0) return null;

    if (isLeafPte(l1_pte)) {
        return (ptePpn(l1_pte) << PAGE_SHIFT) | (vaddr & 0x3FFFFF);
    }

    const l2: *PageTable = @ptrFromInt(ptePpn(l1_pte) << PAGE_SHIFT);
    const l0_pte = l2[vpn0];
    if ((l0_pte & PTE_V) == 0) return null;

    return ptePpn(l0_pte) << PAGE_SHIFT | offset;
}

// ─── Identity-map a range with 4KB pages ─────────────────────────

pub fn identityMap(root: *PageTable, start: u32, end: u32, flags: u32) void {
    var addr = start & ~PAGE_MASK;
    while (addr < end) : (addr += PAGE_SIZE) {
        if (!mapPage(root, addr, addr, flags)) {
            driver.Uart.puts("VM: identity map failed at ");
            driver.Uart.putHex(addr);
            driver.Uart.putc('\n');
            return;
        }
    }
}

// ─── Map a range of virtual → physical ───────────────────────────

pub fn mapRange(root: *PageTable, vaddr: u32, paddr: u32, pages: u32, flags: u32) void {
    var i: u32 = 0;
    while (i < pages) : (i += 1) {
        if (!mapPage(root, vaddr + i * PAGE_SIZE, paddr + i * PAGE_SIZE, flags)) {
            driver.Uart.puts("VM: mapRange failed at page ");
            driver.Uart.putHex(i);
            driver.Uart.putc('\n');
            return;
        }
    }
}

// ─── Unmap a range and optionally free the physical pages ────────

pub fn unmapRange(root: *PageTable, vaddr: u32, pages: u32, free_phys: bool) void {
    var i: u32 = 0;
    while (i < pages) : (i += 1) {
        const va = vaddr + i * PAGE_SIZE;
        if (unmapPage(root, va)) |pa| {
            if (free_phys) freePage(pa);
        }
    }
}

// ─── Create a fresh address space ────────────────────────────────

pub fn createAddressSpace() ?*PageTable {
    const root = allocPageTable() orelse return null;

    // Identity-map kernel code/data in SRAM
    identityMap(root, 0x20000000, 0x20040000, PTE_RWX | PTE_G);
    // CLINT
    identityMap(root, 0x02000000, 0x02010000, PTE_RW | PTE_G);
    // PLIC
    identityMap(root, 0x0C000000, 0x10000000, PTE_RW | PTE_G);
    // OMAP3530 peripherals
    identityMap(root, 0x48000000, 0x4A000000, PTE_RW | PTE_G);
    // DRAM (kernel heap, page tables)
    identityMap(root, 0x30000000, 0x34000000, PTE_RWX | PTE_G);

    return root;
}

// ─── Destroy an address space ────────────────────────────────────

pub fn destroyAddressSpace(root: *PageTable) void {
    for (root, 0..) |pte, vpn1| {
        if ((pte & PTE_V) == 0) continue;
        if (!isLeafPte(pte)) {
            const l2: *PageTable = @ptrFromInt(ptePpn(pte) << PAGE_SHIFT);
            for (l2) |l0_pte| {
                if ((l0_pte & PTE_V) != 0 and (l0_pte & PTE_U) != 0) {
                    freePage(ptePpn(l0_pte) << PAGE_SHIFT);
                }
            }
            freePage(ptePpn(pte) << PAGE_SHIFT);
        } else if ((pte & PTE_U) != 0) {
            freePage(ptePpn(pte) << PAGE_SHIFT);
        }
        root[@intCast(vpn1)] = 0;
    }
    freePage(@intFromPtr(root));
}

// ─── TLB management ──────────────────────────────────────────────

pub fn flushTlbAll() void {
    asm volatile ("sfence.vma zero, zero");
}

pub fn flushTlbPage(vaddr: u32) void {
    asm volatile ("sfence.vma %[addr], zero"
        :
        : [addr] "r" (vaddr),
    );
}

pub fn flushTlbAsid(asid: u32) void {
    asm volatile ("sfence.vma zero, %[asid]"
        :
        : [asid] "r" (asid),
    );
}

// ─── Switch to a page table ──────────────────────────────────────

pub fn switchToPageTable(root: *PageTable) void {
    const satp: u32 = (1 << 31) | (@intFromPtr(root) >> PAGE_SHIFT);
    asm volatile ("sfence.vma zero, zero");
    asm volatile ("csrw satp, %[val]" :: [val] "r" (satp));
    asm volatile ("sfence.vma zero, zero");
}

pub fn disableMmu() void {
    asm volatile ("csrw satp, zero");
    flushTlbAll();
}

pub fn getCurrentRoot() ?*PageTable {
    const satp = asm volatile ("csrr %[out], satp"
        : [out] "=r" (-> u32),
    );
    if ((satp >> 31) == 0) return null;
    return @ptrFromInt((satp & 0x3FFFFF) << PAGE_SHIFT);
}
