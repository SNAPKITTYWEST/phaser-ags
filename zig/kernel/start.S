# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright 2025 Ahmad Ali Parr / SnapKitty � https://github.com/SNAPKITTYWEST/phaser-ags
# ═══════════════════════════════════════════════════════════════════
#  PHASER AGS — RV32I boot assembly (complete, no stubs)
#
#  Full boot sequence + trap entry/exit with context switch.
#  Supports M-mode operation with per-process kernel stacks.
#  Context switch: trapDispatch returns the frame pointer to
#  restore (may differ from entry if a switch occurred).
# ═══════════════════════════════════════════════════════════════════

    .section .text.boot, "ax"
    .globl _start
    .type  _start, @function

_start:
    # ── M-mode entry: disable all interrupts ──
    csrw    mstatus, zero
    csrw    mie, zero
    csrw    mideleg, zero
    csrw    medeleg, zero

    # ── Install trap vector ──
    la      t0, trap_vector
    csrw    mtvec, t0

    # ── Kernel stack ──
    la      sp, __stack_top

    # ── Global pointer for linker relaxation ──
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    # ── Zero BSS ──
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       1b
2:

    # ── Set initial mscratch to kernel stack top ──
    #    (first trap uses this as the context save area)
    csrw    mscratch, sp

    # ── Flush instruction cache ──
    fence.i

    # ── Enter Zig kernel ──
    call    kernelMain

    # ── kernelMain must not return; halt if it does ──
3:  wfi
    j       3b
    .size _start, . - _start

# ═══════════════════════════════════════════════════════════════════
#  TRAP VECTOR — Full context save/restore + context switch
#
#  Layout on kernel stack (264 bytes):
#    [0]     prev_ctx   — previous mscratch (for nested traps)
#    [8]     x1  ra       [16]  x5  t0       [24]  x6  t1
#    [32]    x7  t2       [40]  x10 a0       [48]  x11 a1
#    [56]    x12 a2       [64]  x13 a3       [72]  x14 a4
#    [80]    x15 a5       [88]  x16 a6       [96]  x17 a7
#    [104]   x8  s0/fp    [112] x9  s1       [120] x18 s2
#    [128]   x19 s3       [136] x20 s4       [144] x21 s5
#    [152]   x22 s6       [160] x23 s7       [168] x24 s8
#    [176]   x25 s9       [184] x26 s10      [192] x27 s11
#    [200]   x28 t3       [208] x29 t4       [216] x30 t5
#    [224]   x31 t6       [232] mepc         [240] mstatus
#    [248]   mcause       [256] mtval
# ═══════════════════════════════════════════════════════════════════

    .section .text.trap, "ax"
    .globl trap_vector
    .type  trap_vector, @function

trap_vector:
    # ── Swap sp with mscratch ──
    #    If trap from M-mode: sp was kernel sp, mscratch = same
    #    If first trap: mscratch = initial stack, sp = whatever
    csrrw   sp, mscratch, sp

    # ── Allocate trap frame on kernel stack ──
    addi    sp, sp, -264

    # ── Save all integer registers ──
    sd      x1,  8(sp)
    sd      x5,  16(sp)
    sd      x6,  24(sp)
    sd      x7,  32(sp)
    sd      x10, 40(sp)
    sd      x11, 48(sp)
    sd      x12, 56(sp)
    sd      x13, 64(sp)
    sd      x14, 72(sp)
    sd      x15, 80(sp)
    sd      x16, 88(sp)
    sd      x17, 96(sp)
    sd      x8,  104(sp)
    sd      x9,  112(sp)
    sd      x18, 120(sp)
    sd      x19, 128(sp)
    sd      x20, 136(sp)
    sd      x21, 144(sp)
    sd      x22, 152(sp)
    sd      x23, 160(sp)
    sd      x24, 168(sp)
    sd      x25, 176(sp)
    sd      x26, 184(sp)
    sd      x27, 192(sp)
    sd      x28, 200(sp)
    sd      x29, 208(sp)
    sd      x30, 216(sp)
    sd      x31, 224(sp)

    # ── Save CSRs ──
    csrr    t0, mepc
    sd      t0, 232(sp)
    csrr    t0, mstatus
    sd      t0, 240(sp)
    csrr    t0, mcause
    sd      t0, 248(sp)
    csrr    t0, mtval
    sd      t0, 256(sp)

    # ── Save previous mscratch (was in sp before csrrw) ──
    #    The old sp (pre-swap) is now in mscratch.
    csrr    t0, mscratch
    sd      t0, 0(sp)

    # ── Set mscratch to current kernel stack ──
    csrw    mscratch, sp

    # ── Call Zig trap handler ──
    mv      a0, sp
    call    trapDispatch

    # ── a0 = trap frame pointer to restore ──
    #    May differ from entry sp if context switch occurred
    mv      sp, a0

    # ── Restore CSRs ──
    ld      t0, 232(sp)
    csrw    mepc, t0
    ld      t0, 240(sp)
    csrw    mstatus, t0

    # ── Restore previous mscratch ──
    ld      t0, 0(sp)
    csrw    mscratch, t0

    # ── Restore all integer registers ──
    ld      x1,  8(sp)
    ld      x5,  16(sp)
    ld      x6,  24(sp)
    ld      x7,  32(sp)
    ld      x10, 40(sp)
    ld      x11, 48(sp)
    ld      x12, 56(sp)
    ld      x13, 64(sp)
    ld      x14, 72(sp)
    ld      x15, 80(sp)
    ld      x16, 88(sp)
    ld      x17, 96(sp)
    ld      x8,  104(sp)
    ld      x9,  112(sp)
    ld      x18, 120(sp)
    ld      x19, 128(sp)
    ld      x20, 136(sp)
    ld      x21, 144(sp)
    ld      x22, 152(sp)
    ld      x23, 160(sp)
    ld      x24, 168(sp)
    ld      x25, 176(sp)
    ld      x26, 184(sp)
    ld      x27, 192(sp)
    ld      x28, 200(sp)
    ld      x29, 208(sp)
    ld      x30, 216(sp)
    ld      x31, 224(sp)

    # ── Deallocate trap frame ──
    addi    sp, sp, 264

    # ── Return from trap ──
    mret

    .size trap_vector, . - trap_vector
