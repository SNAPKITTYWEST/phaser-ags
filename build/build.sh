#!/bin/bash
# Firmware Build Script - Phaser AGS Universal Embedded Board
# Generates Stage1 Bootloader ELF/BIN/HEX outputs

set -e

OUTDIR="./output"
LOGDIR="./logs"

# Create directories
mkdir -p "$OUTDIR" "$LOGDIR"

echo "[BUILD] Phaser AGS Stage1 Bootloader"
echo "[BUILD] ================================"
echo "[BUILD] Compiler: arm-none-eabi-gcc"
echo "[BUILD] Linker: arm-none-eabi-ld"
echo "[BUILD] Architecture: ARM Cortex-A8"
echo ""

# Configuration
CC="arm-none-eabi-gcc"
LD="arm-none-eabi-ld"
OBJCOPY="arm-none-eabi-objcopy"
NM="arm-none-eabi-nm"

FIRMWARE_SRC="../boot/arm/stage1.c"
LINKER_SCRIPT="../firmware/linker/boot.ld"
FIRMWARE_OBJ="$OUTDIR/stage1.o"
FIRMWARE_ELF="$OUTDIR/stage1.elf"
FIRMWARE_BIN="$OUTDIR/stage1.bin"
FIRMWARE_HEX="$OUTDIR/stage1.hex"
FIRMWARE_MAP="$OUTDIR/stage1.map"
FIRMWARE_SYM="$OUTDIR/stage1.sym"
COMPILE_LOG="$LOGDIR/compile.log"

# Toolchain flags
CFLAGS="-mcpu=cortex-a8 -mfpu=neon -mfloat-abi=hard"
CFLAGS="$CFLAGS -Wall -Wextra -Werror"
CFLAGS="$CFLAGS -nostdlib -ffunction-sections -fdata-sections"
CFLAGS="$CFLAGS -O2 -g3"

LDFLAGS="-T$LINKER_SCRIPT"
LDFLAGS="$LDFLAGS --gc-sections --cref"
LDFLAGS="$LDFLAGS -Map=$FIRMWARE_MAP"

echo "[COMPILE] Source: $FIRMWARE_SRC"
echo "[COMPILE] Flags: $CFLAGS"
echo ""

# Check if compiler exists
if ! command -v $CC &> /dev/null; then
    echo "[ERROR] Compiler not found: $CC"
    echo "[ERROR] Install ARM EABI toolchain (gcc-arm-embedded)"
    exit 1
fi

# Compile
echo "[COMPILE] Compiling bootloader..."
$CC $CFLAGS -c "$FIRMWARE_SRC" -o "$FIRMWARE_OBJ" 2>&1 | tee "$COMPILE_LOG"

if [ ! -f "$FIRMWARE_OBJ" ]; then
    echo "[ERROR] Compilation failed"
    exit 1
fi

OBJ_SIZE=$(stat -f%z "$FIRMWARE_OBJ" 2>/dev/null || stat -c%s "$FIRMWARE_OBJ" 2>/dev/null || echo "0")
echo "[COMPILE] Object file: $OBJ_SIZE bytes"
echo ""

# Link
echo "[LINK] Linking bootloader..."
echo "[LINK] Linker script: $LINKER_SCRIPT"
echo "[LINK] Flags: $LDFLAGS"

$LD $LDFLAGS -o "$FIRMWARE_ELF" "$FIRMWARE_OBJ" 2>&1 | tee -a "$COMPILE_LOG"

if [ ! -f "$FIRMWARE_ELF" ]; then
    echo "[ERROR] Linking failed"
    exit 1
fi

ELF_SIZE=$(stat -f%z "$FIRMWARE_ELF" 2>/dev/null || stat -c%s "$FIRMWARE_ELF" 2>/dev/null || echo "0")
echo "[LINK] ELF size: $ELF_SIZE bytes"
echo ""

# Generate binaries
echo "[GENERATE] Creating binary outputs..."
$OBJCOPY -O binary "$FIRMWARE_ELF" "$FIRMWARE_BIN"
$OBJCOPY -O ihex "$FIRMWARE_ELF" "$FIRMWARE_HEX"
$NM -n "$FIRMWARE_ELF" > "$FIRMWARE_SYM"

if [ ! -f "$FIRMWARE_BIN" ]; then
    echo "[ERROR] Binary generation failed"
    exit 1
fi

BIN_SIZE=$(stat -f%z "$FIRMWARE_BIN" 2>/dev/null || stat -c%s "$FIRMWARE_BIN" 2>/dev/null || echo "0")
echo "[GENERATE] Binary size: $BIN_SIZE bytes"
echo "[GENERATE] Output files:"
echo "[GENERATE]   ELF:  $FIRMWARE_ELF"
echo "[GENERATE]   BIN:  $FIRMWARE_BIN"
echo "[GENERATE]   HEX:  $FIRMWARE_HEX"
echo "[GENERATE]   MAP:  $FIRMWARE_MAP"
echo "[GENERATE]   SYM:  $FIRMWARE_SYM"
echo ""

# Validation
MAX_SIZE=131072  # 128KB
if [ "$BIN_SIZE" -gt "$MAX_SIZE" ]; then
    echo "[ERROR] Bootloader exceeds max size: $BIN_SIZE > $MAX_SIZE"
    exit 1
fi

echo "[VALIDATE] Size check passed: $BIN_SIZE <= $MAX_SIZE"
echo ""

# Summary
echo "=========================================="
echo "BUILD SUCCESSFUL"
echo "=========================================="
echo "Project:  phaser-ags-universal"
echo "Target:   ARM Cortex-A8 (OMAP3530)"
echo "Output:   $OUTDIR/"
echo "Firmware: stage1.elf ($ELF_SIZE bytes)"
echo "Binary:   stage1.bin ($BIN_SIZE bytes)"
echo "==========================================="

# Save build info
BUILD_INFO="$LOGDIR/build-info.txt"
cat > "$BUILD_INFO" << EOF
Build Date: $(date)
Project: phaser-ags-universal
Architecture: ARM Cortex-A8
Firmware Size: $BIN_SIZE bytes
ELF Size: $ELF_SIZE bytes
Compiler: $CC
Status: SUCCESS
EOF

echo "[INFO] Build info saved: $BUILD_INFO"
