/* SPDX-License-Identifier: AGPL-3.0-or-later */
/* Copyright 2025 Ahmad Ali Parr / SnapKitty � https://github.com/SNAPKITTYWEST/phaser-ags */
## ═══════════════════════════════════════════════════════════════════
##  PHASER AGS — RV32I kernel linker script
##
##  Memory map (matches Chisel Rv32iCore boot address 0x20000000):
##    SRAM  @ 0x20000000  (256 KB — on-chip, boot)
##    DRAM  @ 0x30000000  (64 MB  — MT48H32M16LF-7 via SDRC)
##    MMIO  @ 0x48000000  (OMAP3530 peripheral space)
##
##  Kernel loaded at SRAM base, uses DRAM for heap/page alloc.
## ═══════════════════════════════════════════════════════════════════

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    SRAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 0x00040000   /* 256 KB */
    DRAM  (rwx) : ORIGIN = 0x30000000, LENGTH = 0x04000000   /* 64 MB  */
    MMIO  (rw)  : ORIGIN = 0x48000000, LENGTH = 0x20000000   /* 512 MB */
}

SECTIONS
{
    /* ── Boot vectors in SRAM ── */
    .text.boot : {
        *(.text.boot)
        *(.text.trap)
    } > SRAM

    /* ── Main kernel code ── */
    .text : {
        *(.text .text.*)
    } > SRAM

    /* ── Read-only data ── */
    .rodata : ALIGN(16) {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > SRAM

    /* ── Initialized data ── */
    .data : ALIGN(16) {
        *(.data .data.*)
        *(.sdata .sdata.*)
        PROVIDE(__global_pointer$ = . + 0x800);
    } > SRAM

    /* ── BSS (zeroed by start.S) ── */
    .bss : ALIGN(16) {
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        __bss_end = .;
    } > SRAM

    /* ── Stack grows down from end of SRAM ── */
    .stack (NOLOAD) : ALIGN(16) {
        __stack_bottom = .;
        . = . + 0x8000;    /* 32 KB stack */
        __stack_top = .;
    } > SRAM

    /* ── Kernel heap in SRAM (remaining space) ── */
    .heap (NOLOAD) : ALIGN(4096) {
        __heap_start = .;
        . = ORIGIN(SRAM) + LENGTH(SRAM);
        __heap_end = .;
    } > SRAM

    /* ── Page-allocatable DRAM ── */
    .pages (NOLOAD) : ALIGN(4096) {
        __pages_start = .;
        . = ORIGIN(DRAM) + LENGTH(DRAM);
        __pages_end = .;
    } > DRAM

    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
        *(.note.*)
    }
}
