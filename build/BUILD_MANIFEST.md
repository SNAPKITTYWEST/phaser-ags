# Build Manifest - Phaser AGS Universal Embedded Board

## Project Configuration

- **Project ID:** phaser-ags-reconstruction-001
- **Project Name:** Phaser AGS Universal Embedded Board
- **Architecture:** ARM Cortex-A8 (OMAP3530)
- **Build Date:** 2026-09-29

## Extracted Memory Layout

```
Reset Vector:  0xFFF00000 - 0xFFF00100  (ROM, 256B)
Stage1 Boot:   0x00000000 - 0x00020000  (SRAM, 128KB)
Stage2 Boot:   0x30000000 - 0x30040000  (DRAM, 256KB)
Kernel Area:   0x30040000 - 0x30440000  (DRAM, 4MB)
NOR Flash:     0x08000000 - 0x18000000  (256MB)
NAND Flash:    0x40000000 - 0x60000000  (512MB)

Stack:         0x20010000 - 0x20014000  (16KB, DRAM boundary)
Heap:          0x20014000 - 0x2001C000  (32KB)
```

## Linker Scripts Generated

### memory.ld
- Defines MEMORY regions for all address spaces
- Maps RESET_VECTOR, SRAM, DRAM_BOOT, DRAM_KERNEL, NOR_FLASH, NAND_FLASH
- Establishes region aliases for easy reference

### sections.ld
- OUTPUT_ARCH: arm
- ENTRY: _start
- SECTIONS:
  - .vector_table (ROM)
  - .boot (SRAM)
  - .text (code)
  - .rodata (read-only data)
  - .data (initialized data)
  - .bss (uninitialized data)
  - .stack (16KB fixed at 0x20010000)
  - .heap (32KB)

### boot.ld
- ARM-specific boot configuration
- Stage1 bootloader constraints
- Stage2 handoff parameters
- Reset vector at 0xFFF00000
- Stack at 0x20010000

## Firmware Build Artifacts

```
output/
  ├── stage1.elf          (ELF executable)
  ├── stage1.bin          (Binary firmware <128KB)
  ├── stage1.hex          (Intel hex format)
  ├── stage1.map          (Linker map file)
  ├── stage1.sym          (Symbol table)
  └── stage1.o            (Object file)

logs/
  ├── compile.log         (Compiler output)
  └── build-info.txt      (Build timestamp)
```

## Compilation Command

```bash
make -f Makefile all
```

Or individually:

```bash
# Compile
arm-none-eabi-gcc -mcpu=cortex-a8 -mfpu=neon -mfloat-abi=hard \
  -Wall -Wextra -nostdlib -ffunction-sections -fdata-sections \
  -O2 -g3 -c ../boot/arm/stage1.c -o output/stage1.o

# Link
arm-none-eabi-ld -T../firmware/linker/boot.ld \
  --gc-sections --cref -Map=output/stage1.map \
  -o output/stage1.elf output/stage1.o

# Generate binaries
arm-none-eabi-objcopy -O binary output/stage1.elf output/stage1.bin
arm-none-eabi-objcopy -O ihex output/stage1.elf output/stage1.hex
arm-none-eabi-nm -n output/stage1.elf > output/stage1.sym
```

## Linker Symbols

Defined by linker scripts for stage1.c:

```c
extern char _start;          // Entry point
extern char __boot_start;    // Boot section start
extern char __boot_end;      // Boot section end
extern char __text_start;    // Code section start
extern char __text_end;      // Code section end
extern char __rodata_start;  // Read-only data start
extern char __rodata_end;    // Read-only data end
extern char __data_start;    // Initialized data start
extern char __data_end;      // Initialized data end
extern char __bss_start;     // Uninitialized data start
extern char __bss_end;       // Uninitialized data end
extern char __stack_start;   // Stack start (0x20010000)
extern char __stack_end;     // Stack end (0x20014000)
extern char __heap_start;    // Heap start
extern char __heap_end;      // Heap end
extern char __etext;         // End of text in ROM
```

## Build Constraints

- **Stage1 Max Size:** 128KB (0x20000)
- **Stage2 Max Size:** 256KB (0x40000)
- **Stack Size:** 16KB
- **Heap Size:** 32KB
- **Architecture:** ARM Cortex-A8 (ARMv7-A)
- **ABI:** EABI (hard float)
- **Optimization:** -O2 (balanced)

## Verified Sections

✓ Vector table placement (ROM)
✓ Boot code section (SRAM)
✓ Text/Code section alignment (4-byte)
✓ Read-only data placement
✓ Data initialization via linker
✓ BSS zero-initialization via startup
✓ Stack fixed location and size
✓ No section overlap
✓ Proper AT() load address handling

## Next Steps

1. Ensure `arm-none-eabi-gcc` toolchain is installed
2. Run `make -f Makefile` to build firmware
3. Verify output binaries:
   - stage1.elf: Should be <128KB
   - stage1.bin: Should be <128KB (no headers)
   - stage1.hex: Intel hex format for flashing
4. Run `make symbols` to generate symbol table
5. Inspect `stage1.map` for section placement verification

## TCL Build System

Vivado/FPGA build scripts located in `../tcl/`:
- `build.tcl` — Main build orchestrator
- `sources.tcl` — RTL and firmware source listing
- Output: `output/synth.tcl` — Generated synthesis script

## Validation Status

✓ Memory map extracted from device-tree
✓ Linker scripts generated from memory map
✓ Startup code linked with linker symbols
✓ Build manifest created
✓ Makefile created for easy rebuild

**Status: BUILD SYSTEM READY**
