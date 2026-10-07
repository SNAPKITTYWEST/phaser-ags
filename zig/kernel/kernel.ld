/* SPDX-License-Identifier: AGPL-3.0-or-later */
/* Copyright 2025 Ahmad Ali Parr / SnapKitty — https://github.com/SNAPKITTYWEST/phaser-ags */
/* ═══════════════════════════════════════════════════════════════════
 *  PHASER AGS — RV32I kernel linker script
 *
 *  Memory map (matches Chisel Rv32iCore reset PC 0x20000000):
 *    SRAM  @ 0x20000000  (256 KB — on-chip, boot)
 *    DRAM  @ 0x30000000  (64 MB  — MT48H32M16LF-7 via SDRC)
 *    MMIO  @ 0x48000000  (OMAP3530 peripheral space — not a link region)
 *
 *  SRAM layout (low → high):
 *    .text.boot  _start + trap_vector, pinned at ORIGIN(SRAM)
 *    .text / .rodata / .data / .bss
 *    .stack      32 KB boot/shell stack           (__stack_top)
 *    .trapstack   8 KB trap stack for kernel ctx  (__trap_stack_top)
 *    heap        page-aligned remainder of SRAM   (__heap_start/__heap_end)
 *
 *  DRAM is handed whole to the page allocator (__pages_start/__pages_end).
 *
 *  NOTE: linker scripts accept only C-style comments.
 * ═══════════════════════════════════════════════════════════════════ */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    SRAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 0x00040000   /* 256 KB */
    DRAM  (rwx) : ORIGIN = 0x30000000, LENGTH = 0x04000000   /* 64 MB  */
}

__stack_size      = 0x8000;   /* 32 KB */
__trap_stack_size = 0x2000;   /*  8 KB */

SECTIONS
{
    /* ── Boot entry + trap vector: first bytes of SRAM = reset PC ──
       KEEP: nothing references these by symbol from Zig, so they
       must survive --gc-sections. mtvec requires 4-byte alignment. */
    .text.boot ORIGIN(SRAM) : ALIGN(4) {
        KEEP(*(.text.boot))
        . = ALIGN(4);
        KEEP(*(.text.trap))
    } > SRAM

    /* ── Main kernel code ── */
    .text : ALIGN(4) {
        *(.text .text.*)
    } > SRAM

    /* ── Read-only data ── */
    .rodata : ALIGN(16) {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > SRAM

    /* ── Initialized data (+ small data, addressed via gp) ── */
    .data : ALIGN(16) {
        *(.data .data.*)
        . = ALIGN(8);
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.*)
    } > SRAM

    /* ── BSS (zeroed by start.S, word at a time) ── */
    .bss (NOLOAD) : ALIGN(16) {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(16);
        __bss_end = .;
    } > SRAM

    /* ── Boot / shell stack (grows down) ── */
    .stack (NOLOAD) : ALIGN(16) {
        __stack_bottom = .;
        . += __stack_size;
        __stack_top = .;
    } > SRAM

    /* ── Trap stack for traps taken outside any process context.
          Kept separate from .stack so a trap frame never lands on
          top of the interrupted code's live stack. ── */
    .trapstack (NOLOAD) : ALIGN(16) {
        __trap_stack_bottom = .;
        . += __trap_stack_size;
        __trap_stack_top = .;
    } > SRAM

    /DISCARD/ : {
        *(.eh_frame .eh_frame_hdr)
        *(.comment)
        *(.note .note.*)
    }
}

/* ── Heap: page-aligned remainder of SRAM ── */
__heap_start = ALIGN(__trap_stack_top, 4096);
__heap_end   = ORIGIN(SRAM) + LENGTH(SRAM);

/* ── Page allocator owns all of DRAM ── */
__pages_start = ORIGIN(DRAM);
__pages_end   = ORIGIN(DRAM) + LENGTH(DRAM);

/* ── Invariants ── */
ASSERT(_start == ORIGIN(SRAM), "_start must sit at the reset PC (ORIGIN(SRAM))")
ASSERT((trap_vector & 3) == 0, "trap_vector must be 4-byte aligned for mtvec direct mode")
ASSERT((__stack_top & 15) == 0, "__stack_top must be 16-byte aligned (RISC-V psABI)")
ASSERT((__trap_stack_top & 15) == 0, "__trap_stack_top must be 16-byte aligned")
ASSERT(__heap_start <= __heap_end, "SRAM overflow: kernel image + stacks exceed 256 KB")
ASSERT((__pages_start & 4095) == 0, "__pages_start must be page aligned")
