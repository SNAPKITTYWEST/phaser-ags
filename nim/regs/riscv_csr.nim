## ═══════════════════════════════════════════════════════════════════
##  PHASER AGS — RISC-V CSR register map via Nim AST macros
##
##  All standard RISC-V privileged CSRs with typed accessors.
##  The defCsr macro generates csrr/csrw/csrs/csrc inline assembly
##  procs at compile time — zero overhead, fully typed.
##
##  These CSRs control the NAND-derived RV32I core's trap handling,
##  interrupt enables, performance counters, and machine state.
## ═══════════════════════════════════════════════════════════════════

import ./macros

# ─── Machine-level CSRs ──────────────────────────────────────────

defCsrBlock RvCsr:
  # Machine Information
  defCsr mvendorid,  0xF11    # Vendor ID
  defCsr marchid,    0xF12    # Architecture ID
  defCsr mimpid,     0xF13    # Implementation ID
  defCsr mhartid,    0xF14    # Hardware thread ID

  # Machine Trap Setup
  defCsr mstatus,    0x300    # Machine status
  defCsr misa,       0x301    # ISA and extensions
  defCsr medeleg,    0x302    # Exception delegation
  defCsr mideleg,    0x303    # Interrupt delegation
  defCsr mie,        0x304    # Interrupt enable
  defCsr mtvec,      0x305    # Trap vector base
  defCsr mcounteren, 0x306   # Counter enable

  # Machine Trap Handling
  defCsr mscratch,   0x340    # Scratch register
  defCsr mepc,       0x341    # Exception PC
  defCsr mcause,     0x342    # Exception cause
  defCsr mtval,      0x343    # Trap value
  defCsr mip,        0x344    # Interrupt pending

  # Machine Protection (PMP) — 16 entries
  defCsr pmpcfg0,    0x3A0
  defCsr pmpcfg1,    0x3A1
  defCsr pmpcfg2,    0x3A2
  defCsr pmpcfg3,    0x3A3
  defCsr pmpaddr0,   0x3B0
  defCsr pmpaddr1,   0x3B1
  defCsr pmpaddr2,   0x3B2
  defCsr pmpaddr3,   0x3B3
  defCsr pmpaddr4,   0x3B4
  defCsr pmpaddr5,   0x3B5
  defCsr pmpaddr6,   0x3B6
  defCsr pmpaddr7,   0x3B7
  defCsr pmpaddr8,   0x3B8
  defCsr pmpaddr9,   0x3B9
  defCsr pmpaddr10,  0x3BA
  defCsr pmpaddr11,  0x3BB
  defCsr pmpaddr12,  0x3BC
  defCsr pmpaddr13,  0x3BD
  defCsr pmpaddr14,  0x3BE
  defCsr pmpaddr15,  0x3BF

  # Machine Counters/Timers
  defCsr mcycle,     0xB00    # Cycle counter
  defCsr minstret,   0xB02    # Instructions retired
  defCsr mhpmcounter3,  0xB03
  defCsr mhpmcounter4,  0xB04
  defCsr mhpmevent3,  0x323   # Performance event selector
  defCsr mhpmevent4,  0x324

  # Debug
  defCsr dcsr,       0x7B0    # Debug status/control
  defCsr dpc,        0x7B1    # Debug PC
  defCsr dscratch0,  0x7B2    # Debug scratch
  defCsr dscratch1,  0x7B3

# ═══════════════════════════════════════════════════════════════════
#  Helper procs for common CSR bit manipulations
# ═══════════════════════════════════════════════════════════════════

proc enableMie*() {.inline.} =
  ## Enable machine-level interrupts (MSTATUS.MIE = 1)
  set_mstatus(0x00000008'u32)

proc disableMie*() {.inline.} =
  ## Disable machine-level interrupts
  clear_mstatus(0x00000008'u32)

proc enableSie*() {.inline.} =
  ## Enable supervisor interrupts (MSTATUS.SIE = 1)
  set_mstatus(0x00000002'u32)

proc setMtvecDirect*(addr: uint32) {.inline.} =
  ## Set trap vector to direct mode (all traps → addr)
  write_mtvec(addr)

proc setMtvecVectored*(addr: uint32) {.inline.} =
  ## Set trap vector to vectored mode (base + 4×cause)
  write_mtvec(addr or 1'u32)

proc isInterrupt*(cause: uint32): bool {.inline.} =
  ## Check if mcause is interrupt (MSB set)
  (cause and 0x80000000'u32) != 0

proc exceptionCode*(cause: uint32): uint32 {.inline.} =
  ## Extract exception code from mcause
  cause and 0x7FFFFFFF'u32

proc saveContext*(): uint32 {.inline.} =
  ## Save context pointer to mscratch, return old value
  let old = read_mscratch()
  write_mscratch(result)
  return old

proc restoreContext*(val: uint32) {.inline.} =
  ## Restore context pointer from mscratch
  write_mscratch(val)
