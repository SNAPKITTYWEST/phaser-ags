# Phaser AGS

Embedded platform definition, firmware and kernel for a TI OMAP3530-based board with an FPGA-hosted RV32I processor core.

| Item | Value |
|---|---|
| Application processor | TI OMAP3530 (ARM Cortex-A8) |
| Soft core | RV32I, Chisel HDL (`chisel/src/riscv/Rv32iCore.scala`) |
| SDRAM | Micron MT48H32M16LF-7 (512 Mbit, x16) |
| NOR flash | JS28F256M29EWH (256 Mbit) |
| Reference clock | 26 MHz crystal oscillator (Seiko Epson) |
| Input power | 12 V, 2 A |
| License | GNU AGPL v3.0 or later |

---

## 1. Repository Layout

| Path | Contents |
|---|---|
| `bom/` | Bill of materials (`complete-bom.json`), variants: Baseband, Upconverter, Debug |
| `hardware-description/` | Device tree source (`device-tree.dts`) |
| `memory/` | Board physical memory map (`memory-map.json`) |
| `clock/` | Clock tree (`clock-tree.json`) |
| `power/` | Power tree and sequencing (`power-tree.json`) |
| `circuits/` | SPICE netlists and analysis for CMOS NAND primitives and derived gates |
| `chisel/` | RV32I core and NAND-derived logic library (Chisel/Scala, sbt) |
| `firmware/` | ARM Cortex-A8 boot firmware: stage 1/2, HAL, flash and SDRAM drivers, linker scripts |
| `boot/` | Stage-1 loaders for ARM, MIPS and PowerPC |
| `zig/` | RV32I kernel (Zig and RISC-V assembly) |
| `nim/` | Register definition macros (OMAP3530, RISC-V CSR, CLINT) |
| `tcl/` | FPGA build scripts |
| `build/` | Firmware Makefile and build script |
| `validation/` | Validation report |

---

## 2. Power

### 2.1 Regulators

| Rail | Topology | Device | V<sub>in</sub> | V<sub>out</sub> | I<sub>max</sub> | Loads |
|---|---|---|---|---|---|---|
| P5V0 | Buck | TPS54060 | 12 V | 5.0 V | 3.0 A | Downstream regulators, debug |
| P3V3 | Buck | TPS62120 | 5.0 V | 3.3 V | 1.2 A | U3, GPIO, UART |
| P1V8 | Buck | TPS62110 | 3.3 V | 1.8 V | 1.0 A | U2, U3 |
| P1V2 | Buck | TPS62100 | 1.8 V | 1.2 V | 2.0 A | U1 |
| P1V0 | LDO | TL1963A-33 | 1.2 V | 1.0 V | 500 mA | U1 core |

Input protection: Schottky diode with 10 µF bulk capacitance.

### 2.2 Power-Up Sequence

| Rail | Delay from P5V0 |
|---|---|
| P5V0 | 0 ms |
| P3V3 | 10 ms |
| P1V8 | 20 ms |
| P1V2 | 30 ms |
| P1V0 | 50 ms |

---

## 3. Clocks

| Clock | Source | Frequency | Destination |
|---|---|---|---|
| REF_CLK | X1 | 26 MHz, ±30 ppm | U1 PLL, U2 clock controller |
| CPU_CLK | U1 PLL (×23) | 598 MHz (nominal 600 MHz) | U1 ARM core |
| DDR_CLK | U1 PLL | 266 MHz | U2 SDRAM |
| UART_CLK | REF_CLK | 26 MHz | UART0, UART1 |
| SPI_CLK | REF_CLK | 26 MHz | SPI0, SPI1 |

The kernel UART driver computes its baud divisor from a 48 MHz functional clock (`zig/kernel/driver.zig`). See section 9.

---

## 4. Memory Maps

### 4.1 Board (ARM Cortex-A8 view)

Source: `memory/memory-map.json`, `firmware/linker/memory.ld`.

| Region | Base | Size | Device | Bus width | Cache policy |
|---|---|---|---|---|---|
| Reset vector | 0xFFF00000 | 256 B | ROM | 32 | — |
| Stage-1 boot | 0x00000000 | 128 KB | SRAM | 32 | WT |
| Stage-2 boot | 0x30000000 | 256 KB | DRAM | 32 | WB |
| Kernel | 0x30040000 | 4 MB | DRAM | 32 | WB |
| NOR flash | 0x08000000 | 256 MB window | NOR | 16 | WT |
| NAND flash | 0x40000000 | 512 MB window | NAND | 8 | — |

### 4.2 RV32I Kernel

Source: `zig/kernel/kernel.ld`, `zig/kernel/driver.zig`.

| Region | Base | Size | Use |
|---|---|---|---|
| CLINT | 0x02000000 | 64 KB | `mtime`, `mtimecmp`, `msip` |
| PLIC | 0x0C000000 | 64 MB | External interrupt controller |
| SRAM | 0x20000000 | 256 KB | Kernel image, stacks, heap; reset PC |
| DRAM | 0x30000000 | 64 MB | Page allocator |
| OMAP3530 L4 peripherals | 0x48000000 | 32 MB | UART, GPIO, INTC, timers |
| SDRC | 0x6D000000 | — | SDRAM controller |
| GPMC | 0x6E000000 | — | NOR/NAND controller |

SRAM layout, low to high addresses:

| Section | Size | Notes |
|---|---|---|
| `.text.boot` | — | `_start`, `trap_vector`; pinned at 0x20000000 |
| `.text`, `.rodata`, `.data`, `.bss` | — | Kernel image |
| `.stack` | 32 KB | Boot and shell stack |
| `.trapstack` | 8 KB | Trap stack for traps taken outside a process |
| Heap | Remainder | Page-aligned, to 0x20040000 |

Link-time assertions enforce: `_start` at 0x20000000, 4-byte alignment of `trap_vector`, 16-byte alignment of both stack tops, and the image fitting within SRAM.

---

## 5. Peripherals

| Peripheral | Base | IRQ | Notes |
|---|---|---|---|
| UART1 (console) | 0x4806A000 | 72 | NS16550-compatible, 115200 8N1 |
| UART2 | 0x4806C000 | 73 | |
| GPIO1 | 0x48310000 | — | See 5.1 |
| INTC | 0x48200000 | — | OMAP3 interrupt controller |
| GPTIMER1 | 0x48318000 | 37 | |
| McSPI1 | 0x48098000 | — | |
| I2C1 | 0x48070000 | — | |
| HSMMC1 | 0x4809C000 | — | |
| EMAC / MDIO | 0x5C040000 / 0x5C030000 | — | |
| CM / PRM / CONTROL | 0x48004000 / 0x48306000 / 0x48002000 | — | Clock, power and pad control |

### 5.1 GPIO1 Assignments

| Pin | Direction | Function |
|---|---|---|
| 8 | Out | Status LED |
| 9 | Out | Ethernet PHY reset, active low |
| 10, 11, 12 | Out | FPGA nCONFIG |

---

## 6. Boot Sequence

### 6.1 ARM Cortex-A8

1. The boot ROM samples SYS_BOOT and loads stage 1 into internal SRAM.
2. Stage 1 (`firmware/boot/stage1.c`, `start.S`) configures the DPLLs, initialises the SDRC and UART, and loads stage 2 from NOR or NAND flash into DRAM at 0x30000000.
3. Stage 2 (`firmware/boot/stage2.c`) initialises board peripherals and provides a serial shell (`firmware/boot/shell.c`).

### 6.2 RV32I Core

1. The core comes out of reset at PC 0x20000000 (`_start`).
2. `start.S` clears `mstatus` and `mie`, loads `mtvec`, `gp` and `sp`, points `mscratch` at the trap stack, zeroes `.bss`, and calls `kernelMain`.
3. `kernelMain` (`zig/kernel/main.zig`) runs early board setup, initialises the console, the page allocator, trap handlers, the process table and a 10 ms CLINT tick, enables machine timer and external interrupts, and starts the kernel shell.

---

## 7. RV32I Kernel

### 7.1 ISA and Privilege

| Item | Value |
|---|---|
| ISA | RV32I + Zicsr + Zifencei |
| ABI | ilp32, soft float |
| Privilege | Machine mode only |
| Code model | medany |
| Integer multiply and divide | Software (compiler-rt) |

### 7.2 Trap Frame

Trap frames hold one XLEN-wide slot per entry. On RV32 a frame is 33 × 4 = 132 bytes, padded to 144 bytes for 16-byte stack alignment. Compile-time assertions in `trap.zig` keep `start.S` and `TrapFrame` in step.

| Slot | Offset (RV32) | Contents |
|---|---|---|
| 0 | 0x00 | `sp` (x2) at the point of the trap; restored last |
| 1 | 0x04 | `ra` (x1) |
| 2–4 | 0x08–0x10 | `t0`–`t2` |
| 5–12 | 0x14–0x30 | `a0`–`a7` |
| 13–24 | 0x34–0x60 | `s0`–`s11` |
| 25–28 | 0x64–0x70 | `t3`–`t6` |
| 29 | 0x74 | `mepc` |
| 30 | 0x78 | `mstatus` |
| 31 | 0x7C | `mcause` |
| 32 | 0x80 | `mtval` |
| — | 0x84–0x8F | Padding |

On trap entry `sp` is swapped with `mscratch`, which holds the trap-stack top for the current context. `trapDispatch` returns the frame to resume, which may belong to a different process. On exit, `mscratch` is set to the top of the resumed frame and `sp` is reloaded from slot 0.

### 7.3 Exceptions and Interrupts

| `mcause` | Event | Handling |
|---|---|---|
| 0, 4, 6 | Misaligned instruction, load or store | Report; advance `mepc` |
| 1, 5, 7 | Access fault | Report; terminate current process |
| 2 | Illegal instruction | Report; advance `mepc` |
| 3 | Breakpoint | Report; advance `mepc` |
| 8, 11 | `ecall` from U or M mode | System call dispatch |
| 12, 13, 15 | Page fault | Report; terminate current process |
| Interrupt 3 | Machine software | Clear MSIP |
| Interrupt 7 | Machine timer | Advance `mtimecmp`; request reschedule |
| Interrupt 11 | Machine external | PLIC claim, dispatch, complete |

On RV32, `mtimecmp` is written as low = 0xFFFFFFFF, then high, then low, as the RISC-V privileged specification requires, so the write cannot raise a spurious interrupt.

### 7.4 Memory Management

| Item | Value |
|---|---|
| Physical allocator | Bitmap, 4 KB pages, over DRAM 0x30000000–0x34000000 |
| Translation | Sv32, two-level, 4 KB pages and 4 MB megapages |
| `satp` | MODE[31] = 1, ASID = 0, PPN[21:0] = root table |
| Per-process address space | Kernel SRAM, CLINT, PLIC, L4 peripherals and DRAM identity-mapped, global |

### 7.5 Processes

| Item | Value |
|---|---|
| Process table | 16 entries |
| Kernel stack | 8 KB per process |
| User stack | 16 KB per process |
| Scheduling | Round-robin, 10-tick quantum, 10 ms tick |
| States | unused, runnable, running, sleeping, zombie |
| File descriptors | 16 per process; 0–2 bound to UART |

### 7.6 System Calls

Number in `a7`, arguments in `a0`–`a2`, result in `a0`.

| No. | Name | Arguments |
|---|---|---|
| 0 | `read` | fd, buf, len |
| 1 | `write` | fd, buf, len |
| 2 | `open` | path, flags |
| 3 | `close` | fd |
| 4 | `yield` | — |
| 5 | `getpid` | — |
| 6 | `exit` | code |
| 7 | `mmap` | addr (ignored), len, prot |
| 8 | `munmap` | addr, len |

Device paths: `/dev/uart0`, `/dev/null`, `/dev/zero`.

### 7.7 Kernel Shell Commands

`md`, `mw`, `mwb`, `go`, `reset`, `regs`, `proc`, `spawn`, `kill`, `reap`, `vm`, `vmmap`, `vmtrans`, `tick`, `pages`, `led`, `echo`, `help`.

---

## 8. Build

### 8.1 RV32I Kernel

Requires Zig 0.13 or 0.14.

```
cd zig
zig build
```

| Output | Description |
|---|---|
| `zig-out/bin/phaser-ags-kernel` | ELF, linked at 0x20000000 |
| `zig-out/bin/phaser-ags-kernel.bin` | Raw image for loading at 0x20000000 |

To override the CPU, for example to enable the M extension:

```
zig build -Dcpu=generic_rv32+m+zicsr+zifencei
```

`zig build run` starts `qemu-system-riscv32 -machine virt`. The QEMU `virt` memory map differs from this board: RAM is at 0x80000000 and the UART at 0x10000000. The target is therefore suitable for debugging with `-s -S` and GDB, but produces no console output.

### 8.2 ARM Firmware

Requires `arm-none-eabi-gcc`.

```
cd build
make
```

Outputs `stage1` and `stage2` as `.elf`, `.bin`, `.hex` and `.sym` in `build/output/`.

### 8.3 RV32I Core

Requires sbt.

```
cd chisel
sbt run
```

Runs `EmitVerilog` to generate Verilog for the RV32I core and logic library. `sbt test` runs the NAND primitive tests.

---

## 9. Known Limitations and Source Discrepancies

| Item | Detail |
|---|---|
| RV32I core CSR support | `Rv32iCore.scala` does not implement CSRs, `ecall` or `mret`. The kernel requires them. |
| Kernel shell preemption | When no process is current, a timer-driven switch to a process does not save the shell context. |
| SDRAM capacity | MT48H32M16LF is 512 Mbit (64 MB). `bom/complete-bom.json` lists 256 MB, and `device-tree.dts` declares a 256 MB memory node. |
| UART1 IRQ | OMAP3530 UART1 is IRQ 72. `device-tree.dts` lists 74. |
| UART functional clock | The driver assumes 48 MHz. `clock/clock-tree.json` lists 26 MHz. |
| CPU clock | 26 MHz × 23 = 598 MHz. `device-tree.dts` declares 600 MHz. |
| ARM linker scripts | `firmware/linker/boot.ld` and `sections.ld` both define `SECTIONS` for the same output sections. |
| Source encoding | Files under `nim/regs/` contain non-UTF-8 bytes. |

---

Copyright 2025 Ahmad Ali Parr / SnapKitty. Licensed under the GNU Affero General Public License v3.0 or later. See `LICENSE`.
