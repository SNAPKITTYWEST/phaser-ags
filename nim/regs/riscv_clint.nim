## ═══════════════════════════════════════════════════════════════════
##  PHASER AGS — RISC-V CLINT register map (Nim AST macros)
##
##  Core Local Interruptor for the NAND-derived RV32I core.
##  Provides mtime (free-running counter) and mtimecmp (timer compare).
##  Standard RISC-V address: 0x02000000
## ═══════════════════════════════════════════════════════════════════

import ./macros

defRegBlock Clint, 0x02000000:
  defReg msip0,     0x0000, u32, rw:
    defField pending, 0, 1      # Software interrupt pending for hart 0
  defReg msip1,     0x0004, u32, rw:
    defField pending, 0, 1      # Software interrupt pending for hart 1
  defReg mtimecmp0l, 0x4000, u32, rw   # mtimecmp low 32 bits (hart 0)
  defReg mtimecmp0h, 0x4004, u32, rw   # mtimecmp high 32 bits (hart 0)
  defReg mtimecmp1l, 0x4008, u32, rw   # mtimecmp low 32 bits (hart 1)
  defReg mtimecmp1h, 0x400C, u32, rw   # mtimecmp high 32 bits (hart 1)
  defReg mtimel,    0xBFF8, u32, ro    # mtime low 32 bits
  defReg mtimeh,    0xBFFC, u32, ro    # mtime high 32 bits

# ─── Helper procs for 64-bit CLINT access ────────────────────────

proc readMtime*(): uint64 {.inline.} =
  ## Read 64-bit mtime counter (must read low then high to avoid rollover)
  var lo, hi: uint32
  while true:
    hi = mtimeh()
    lo = mtimel()
    let hi2 = mtimeh()
    if hi == hi2: break
    # Rollover happened between reads, retry
  uint64(hi) shl 32 or uint64(lo)

proc writeMtimecmp*(val: uint64) {.inline.} =
  ## Write 64-bit mtimecmp (write high first to avoid spurious IRQ)
  write_mtimecmp0h(uint32(val shr 32))
  write_mtimecmp0l(uint32(val and 0xFFFFFFFF'u32))

proc setTimerInterval*(ticks: uint64) {.inline.} =
  ## Set next timer interrupt `ticks` from now
  let now = readMtime()
  writeMtimecmp(now + ticks)

proc triggerSoftwareIrq*() {.inline.} =
  ## Trigger software interrupt on hart 0
  write_msip0(0x00000001'u32)

proc clearSoftwareIrq*() {.inline.} =
  ## Clear software interrupt on hart 0
  write_msip0(0x00000000'u32)
