# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright 2025 Ahmad Ali Parr / SnapKitty — https://github.com/SNAPKITTYWEST/phaser-ags
# ═══════════════════════════════════════════════════════════════════
#  PHASER AGS — RV32I boot assembly
#
#  Boot sequence + trap entry/exit with context switch, M-mode only.
#
#  XLEN-generic: register slots are REGBYTES wide (4 on RV32, 8 on
#  RV64), selected by the compiler-defined __riscv_xlen. The layout
#  MUST match trap.TrapFrame (checked by a comptime assert there).
#
#  mscratch invariant: while running, mscratch = top of the trap stack
#  for the current context (kernel trap stack, or a process's kernel
#  stack). The interrupted sp is saved in frame.sp and restored last.
# ═══════════════════════════════════════════════════════════════════

#if __riscv_xlen == 64
#  define REG_S sd
#  define REG_L ld
#  define REGBYTES 8
#elif __riscv_xlen == 32
#  define REG_S sw
#  define REG_L lw
#  define REGBYTES 4
#else
#  error "unsupported __riscv_xlen"
#endif

# Slot index → byte offset
#define OFF(n) ((n) * REGBYTES)

# 33 live slots, frame rounded up to 16 bytes (psABI stack alignment):
#   RV32: 33*4 = 132 → 144     RV64: 33*8 = 264 → 272
#define FRAME_SLOTS 33
#define FRAME_SIZE  (((FRAME_SLOTS * REGBYTES) + 15) & ~15)

# Slot map (index):
#   0 sp(x2)  1 ra(x1)  2 t0  3 t1  4 t2  5 a0 ... 12 a7
#  13 s0  14 s1  15 s2 ... 24 s11  25 t3  26 t4  27 t5  28 t6
#  29 mepc  30 mstatus  31 mcause  32 mtval

    .section .text.boot, "ax"
    .globl _start
    .type  _start, @function
    .align 2

_start:
    # ── M-mode entry: disable all interrupts ──
    csrw    mstatus, zero
    csrw    mie, zero

    # ── Install trap vector (direct mode, low 2 bits = 0) ──
    la      t0, trap_vector
    csrw    mtvec, t0

    # ── Global pointer for linker relaxation ──
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    # ── Boot/shell stack ──
    la      sp, __stack_top

    # ── Trap stack for the kernel context (separate from sp) ──
    la      t0, __trap_stack_top
    csrw    mscratch, t0

    # ── Zero BSS (bounds are 16-byte aligned by kernel.ld) ──
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    REG_S   zero, 0(t0)
    addi    t0, t0, REGBYTES
    j       1b
2:

    # ── Flush instruction cache ──
    fence.i

    # ── Enter Zig kernel ──
    call    kernelMain

    # ── kernelMain must not return; halt if it does ──
3:  wfi
    j       3b
    .size _start, . - _start

# ═══════════════════════════════════════════════════════════════════
#  TRAP VECTOR — full context save/restore + context switch
# ═══════════════════════════════════════════════════════════════════

    .section .text.trap, "ax"
    .globl trap_vector
    .type  trap_vector, @function
    .align 2

trap_vector:
    # sp ← trap stack top, mscratch ← interrupted sp
    csrrw   sp, mscratch, sp
    addi    sp, sp, -FRAME_SIZE

    REG_S   x1,  OFF(1)(sp)
    REG_S   x5,  OFF(2)(sp)
    REG_S   x6,  OFF(3)(sp)
    REG_S   x7,  OFF(4)(sp)
    REG_S   x10, OFF(5)(sp)
    REG_S   x11, OFF(6)(sp)
    REG_S   x12, OFF(7)(sp)
    REG_S   x13, OFF(8)(sp)
    REG_S   x14, OFF(9)(sp)
    REG_S   x15, OFF(10)(sp)
    REG_S   x16, OFF(11)(sp)
    REG_S   x17, OFF(12)(sp)
    REG_S   x8,  OFF(13)(sp)
    REG_S   x9,  OFF(14)(sp)
    REG_S   x18, OFF(15)(sp)
    REG_S   x19, OFF(16)(sp)
    REG_S   x20, OFF(17)(sp)
    REG_S   x21, OFF(18)(sp)
    REG_S   x22, OFF(19)(sp)
    REG_S   x23, OFF(20)(sp)
    REG_S   x24, OFF(21)(sp)
    REG_S   x25, OFF(22)(sp)
    REG_S   x26, OFF(23)(sp)
    REG_S   x27, OFF(24)(sp)
    REG_S   x28, OFF(25)(sp)
    REG_S   x29, OFF(26)(sp)
    REG_S   x30, OFF(27)(sp)
    REG_S   x31, OFF(28)(sp)

    # ── Interrupted sp (parked in mscratch by the swap) ──
    csrr    t0, mscratch
    REG_S   t0, OFF(0)(sp)

    # ── CSRs ──
    csrr    t0, mepc
    REG_S   t0, OFF(29)(sp)
    csrr    t0, mstatus
    REG_S   t0, OFF(30)(sp)
    csrr    t0, mcause
    REG_S   t0, OFF(31)(sp)
    csrr    t0, mtval
    REG_S   t0, OFF(32)(sp)

    # ── trapDispatch(frame) → frame to resume (may differ) ──
    mv      a0, sp
    call    trapDispatch
    mv      sp, a0

    # ── Restore CSRs ──
    REG_L   t0, OFF(29)(sp)
    csrw    mepc, t0
    REG_L   t0, OFF(30)(sp)
    csrw    mstatus, t0

    # ── Re-arm mscratch: the resumed context's trap stack top is
    #    directly above its frame. ──
    addi    t0, sp, FRAME_SIZE
    csrw    mscratch, t0

    REG_L   x1,  OFF(1)(sp)
    REG_L   x5,  OFF(2)(sp)
    REG_L   x6,  OFF(3)(sp)
    REG_L   x7,  OFF(4)(sp)
    REG_L   x10, OFF(5)(sp)
    REG_L   x11, OFF(6)(sp)
    REG_L   x12, OFF(7)(sp)
    REG_L   x13, OFF(8)(sp)
    REG_L   x14, OFF(9)(sp)
    REG_L   x15, OFF(10)(sp)
    REG_L   x16, OFF(11)(sp)
    REG_L   x17, OFF(12)(sp)
    REG_L   x8,  OFF(13)(sp)
    REG_L   x9,  OFF(14)(sp)
    REG_L   x18, OFF(15)(sp)
    REG_L   x19, OFF(16)(sp)
    REG_L   x20, OFF(17)(sp)
    REG_L   x21, OFF(18)(sp)
    REG_L   x22, OFF(19)(sp)
    REG_L   x23, OFF(20)(sp)
    REG_L   x24, OFF(21)(sp)
    REG_L   x25, OFF(22)(sp)
    REG_L   x26, OFF(23)(sp)
    REG_L   x27, OFF(24)(sp)
    REG_L   x28, OFF(25)(sp)
    REG_L   x29, OFF(26)(sp)
    REG_L   x30, OFF(27)(sp)
    REG_L   x31, OFF(28)(sp)

    # ── sp last: it is the base register for every load above ──
    REG_L   sp,  OFF(0)(sp)
    mret

    .size trap_vector, . - trap_vector
