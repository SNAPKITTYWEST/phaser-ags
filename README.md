# Phaser AGS Universal

[![License: AGPL-3.0-or-later](https://img.shields.io/badge/license-AGPL--3.0--or--later-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Chisel](https://img.shields.io/badge/Chisel-6.x-FF6F00?logo=scala)](https://www.chisel-lang.org/)
[![Zig](https://img.shields.io/badge/Zig-0.13-F7A41D?logo=zig)](https://ziglang.org/)
[![Nim](https://img.shields.io/badge/Nim-2.0-FFE953?logo=nim)](https://nim-lang.org/)
[![RISC-V](https://img.shields.io/badge/ISA-RV32I-00ACC1?logo=riscv)](https://riscv.org/)
[![OMAP3530](https://img.shields.io/badge/SoC-OMAP3530-6A1B9A)]()

Full-stack embedded board reconstruction — transistor-level CMOS circuits through synthesizable RISC-V core, kernel, and register macros.

> **Repo:** <https://github.com/SNAPKITTYWEST/phaser-ags>

## Architecture

```
SPICE (BSIM3v3 180nm)          Chisel 6.x (→ Verilog)         Zig (kernel)          Nim (macros)
─────────────────────          ─────────────────────           ────────────          ─────────────
NAND2 CMOS netlist      ──→    Nand2 / Nand3 / Nor2     ──→
Jacobian 2×2 blocks            Inv / And / Or / Xor /
4-corner analysis              Xnor / Mux2 (from Nand2)
                               ↓
NAND3 tridiagonal J    ──→    SR Latch → D Latch →
SR latch eigenvalues           D FF → Register (NAND)
                               ↓
                               Half → Full → RCA-8 →
                               ALU-8 (NAND-only)
                               ↓
                               RegFile / RvAlu (4×RCA-8) /
                               ImmGen / Control / Core
                               ↓  (sbt runMain nand.EmitVerilog)
                               verilog_out/*.v
                                                              ↓
                                                       start.S (boot)
                                                       trap.zig (full ctx save)
                                                       memory.zig (SV32 VM)
                                                       process.zig (preemptive RR)
                                                       syscall.zig (9 syscalls)
                                                       timer.zig (CLINT)
                                                       driver.zig (UART/GPIO/PLIC)
                                                       shell.zig (18 commands)
                                                                              ↓
                                                                       defReg / defCsr
                                                                       omap3530.nim
                                                                       riscv_csr.nim
                                                                       riscv_clint.nim
```

## Directory

| Path | Contents |
|------|----------|
| `circuits/spice/` | NAND2/NAND3/SR-latch SPICE netlists, Jacobian analysis, 4-corner eval |
| `circuits/analysis/` | MNA formulation, device stamps, numerical Jacobian values |
| `circuits/cmos/` | Boolean algebra proofs, NAND universality, W/L sizing |
| `chisel/src/nand/` | Nand2/Nand3/Nor2 primitives + combinational gates from Nand2 |
| `chisel/src/sequential/` | SR Latch → D Latch → D FF → n-bit Register |
| `chisel/src/arithmetic/` | Half Adder → Full Adder → RCA-8 → ALU-8 (NAND-only) |
| `chisel/src/riscv/` | RV32I core: RegFile, ALU, ImmGen, Control, load-use stall |
| `chisel/src/test/` | ChiselTest for all modules |
| `zig/kernel/` | Boot asm, trap framework, SV32 VM, preemptive scheduler, syscalls, shell |
| `nim/regs/` | AST macros for typed MMIO + RISC-V CSR access |

## Build

### Chisel → Verilog

```bash
cd chisel && sbt "runMain nand.EmitVerilog"
# Output: verilog_out/{Nand2,Nand3,InvFromNand,...,Rv32iCore}.v
```

### Chisel tests

```bash
cd chisel && sbt test
```

### Zig kernel

```bash
cd zig && zig build-exe kernel/main.zig \
  -target riscv64-freestanding-none \
  -O ReleaseSmall \
  -linker-script kernel/kernel.ld
```

### QEMU

```bash
qemu-system-riscv64 -machine virt -nographic -bios none -kernel phaser-ags-kernel
```

## Hardware target

| Component | Part | Notes |
|-----------|------|-------|
| SoC | OMAP3530DCAB | ARM Cortex-A8 + C64x DSP |
| SDRAM | MT48H32M16LF-7 | 64 MB via SDRC JEDEC init |
| NOR Flash | JS28F256M29EWH | GPMC CS0 16-bit async |
| Crystal | 26 MHz | DPLL1→600 MHz, DPLL5→266 MHz |
| Boot | SRAM 0x20000000 | 256 KB on-chip |

## NAND gate traceability

Every arithmetic path in the RISC-V ALU traces back to the BSIM3v3 SPICE model:

- `RvAlu` uses 4× `RippleCarryAdder(8)` for 32-bit ADD/SUB
- Each `RippleCarryAdder(8)` chains 8× `FullAdderFromNand`
- Each `FullAdderFromNand` = 2× `HalfAdderFromNand` + `Or2FromNand`
- Each `HalfAdderFromNand` = `Xor2FromNand` (4 Nand2) + `And2FromNand` (2 Nand2)
- **~288 Nand2 gates in the 32-bit add path**, each validated by `nand2_cmos.sp`

## Kernel capabilities

| Subsystem | Implementation |
|-----------|---------------|
| Boot | `start.S`: M-mode entry, BSS zero, stack/GP setup, trap vector install |
| Traps | Full 31-GPR + 4-CSR save/restore, per-code dispatch, context switch via `mv sp,a0` |
| VM | SV32 two-level page tables, map/unmap/translate, `sfence.vma`, `createAddressSpace`/`destroyAddressSpace` |
| Memory | Bitmap page allocator (4 KB), `allocPage`/`allocRange`/`freePage`/`freeRange` |
| Scheduler | Preemptive round-robin, 10-tick quantum, `ksp`-based context switch, page table switch |
| Syscalls | read/write/open/close/yield/getpid/exit/mmap/munmap — 9 fully implemented |
| Devices | `/dev/uart0`, `/dev/null`, `/dev/zero` via per-process fd table + `DevOps` dispatch |
| Timer | CLINT mtime/mtimecmp, safe 64-bit read, tick advance, scheduler callback |
| PLIC | Priority/threshold/enable/claim/complete, external IRQ dispatch table |
| Shell | 18 commands: md, mw, mwb, go, reset, regs, proc, spawn, kill, reap, vm, vmmap, vmtrans, tick, pages, led, echo, help |

## License

[GNU Affero General Public License v3.0 or later](LICENSE) — SPDX: `AGPL-3.0-or-later`

Copyright 2025 Ahmad Ali Parr / SnapKitty
