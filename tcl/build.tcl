#!/usr/bin/tclsh
# Universal Embedded Board Build System
# Orchestrates complete firmware + bitstream build

set BUILD_DIR [file dirname [info script]]
set PROJECT_ROOT [file dirname $BUILD_DIR]
set PROJECT_NAME "phaser-ags-universal"
set BUILD_CONFIG "Release"

proc log {msg} {
    puts "\[BUILD\] $msg"
    flush stdout
}

proc error_exit {msg} {
    puts "\[ERROR\] $msg" stderr
    flush stderr
    exit 1
}

# ==============================================================================
# 1. CONFIGURE BUILD
# ==============================================================================

log "Configuring build system..."

set LINKER_SCRIPT "$PROJECT_ROOT/firmware/linker/boot.ld"
set FIRMWARE_SRC "$PROJECT_ROOT/boot/arm/stage1.c"
set OUTPUT_DIR "$BUILD_DIR/output"
set LOG_DIR "$BUILD_DIR/logs"

# Create output directories
file mkdir $OUTPUT_DIR
file mkdir $LOG_DIR

# ==============================================================================
# 2. COMPILE FIRMWARE
# ==============================================================================

log "Stage 1: Compiling firmware..."

set COMPILE_LOG "$LOG_DIR/compile.log"
set FIRMWARE_ELF "$OUTPUT_DIR/stage1.elf"
set FIRMWARE_BIN "$OUTPUT_DIR/stage1.bin"
set FIRMWARE_HEX "$OUTPUT_DIR/stage1.hex"
set FIRMWARE_MAP "$OUTPUT_DIR/stage1.map"

# ARM cross-compiler flags
set CC "arm-none-eabi-gcc"
set OBJCOPY "arm-none-eabi-objcopy"
set NM "arm-none-eabi-nm"

set CFLAGS "-mcpu=cortex-a8 -mfpu=neon -mfloat-abi=hard"
set CFLAGS "$CFLAGS -Wall -Wextra -Werror"
set CFLAGS "$CFLAGS -nostdlib -ffunction-sections -fdata-sections"
set CFLAGS "$CFLAGS -O2 -g3"

set LDFLAGS "-Wl,--gc-sections"
set LDFLAGS "$LDFLAGS -T\"$LINKER_SCRIPT\""
set LDFLAGS "$LDFLAGS -Wl,-Map=\"$FIRMWARE_MAP\""

# Compile
log "Invoking compiler: $CC"
set compile_cmd "$CC $CFLAGS -c \"$FIRMWARE_SRC\" -o $OUTPUT_DIR/stage1.o 2>&1 | tee $COMPILE_LOG"
set result [catch {eval exec sh -c $compile_cmd} output]

if {$result != 0} {
    error_exit "Compilation failed:\n$output"
}
log "Compilation successful"

# Link
log "Linking firmware..."
set link_cmd "$CC $CFLAGS $LDFLAGS $OUTPUT_DIR/stage1.o -o \"$FIRMWARE_ELF\" 2>&1 | tee -a $COMPILE_LOG"
set result [catch {eval exec sh -c $link_cmd} output]

if {$result != 0} {
    error_exit "Linking failed:\n$output"
}
log "Linking successful"

# Generate binaries
log "Generating binary outputs..."
catch {exec $OBJCOPY -O binary "$FIRMWARE_ELF" "$FIRMWARE_BIN"}
catch {exec $OBJCOPY -O ihex "$FIRMWARE_ELF" "$FIRMWARE_HEX"}
catch {exec $NM -n "$FIRMWARE_ELF" > "$OUTPUT_DIR/stage1.sym"}

log "Firmware outputs:"
log "  ELF:  $FIRMWARE_ELF"
log "  BIN:  $FIRMWARE_BIN"
log "  HEX:  $FIRMWARE_HEX"
log "  MAP:  $FIRMWARE_MAP"
log "  SYM:  $OUTPUT_DIR/stage1.sym"

# ==============================================================================
# 3. VERIFICATION
# ==============================================================================

log "Stage 2: Verifying build outputs..."

if {![file exists $FIRMWARE_ELF]} {
    error_exit "ELF file not generated: $FIRMWARE_ELF"
}

set elf_size [file size $FIRMWARE_ELF]
log "ELF size: $elf_size bytes"

if {![file exists $FIRMWARE_BIN]} {
    error_exit "Binary file not generated: $FIRMWARE_BIN"
}

set bin_size [file size $FIRMWARE_BIN]
log "Binary size: $bin_size bytes"

# Check size constraints
set MAX_STAGE1_SIZE 0x20000
if {$bin_size > $MAX_STAGE1_SIZE} {
    error_exit "Stage1 bootloader exceeds max size: $bin_size > $MAX_STAGE1_SIZE"
}
log "Size check passed: $bin_size <= $MAX_STAGE1_SIZE"

# ==============================================================================
# 4. TCL SYNTHESIS (if Vivado available)
# ==============================================================================

log "Stage 3: TCL synthesis configuration..."

set SYNTH_TCL "$BUILD_DIR/output/synth.tcl"
set f [open $SYNTH_TCL w]
puts $f "# Auto-generated synthesis script for Vivado"
puts $f "# Project: $PROJECT_NAME"
puts $f ""
puts $f "# Create project"
puts $f "create_project $PROJECT_NAME $BUILD_DIR/project -part xc7z020clg484-1"
puts $f ""
puts $f "# Add RTL sources"
puts $f "add_files -fileset sources_1 $PROJECT_ROOT/rtl/top.v"
puts $f "add_files -fileset sources_1 $PROJECT_ROOT/rtl/cpu.v"
puts $f ""
puts $f "# Add constraints"
puts $f "add_files -fileset constrs_1 $PROJECT_ROOT/constraints/board.xdc"
puts $f ""
puts $f "# Add firmware ROM initialization"
puts $f "add_files -fileset constrs_1 \"$FIRMWARE_BIN\""
puts $f "set_property SCOPED_TO_REF {boot_rom} \[get_files \"$FIRMWARE_BIN\"\]"
puts $f ""
puts $f "# Run synthesis"
puts $f "synth_design -top top -part xc7z020clg484-1"
puts $f ""
puts $f "# Run place & route"
puts $f "opt_design"
puts $f "place_design"
puts $f "route_design"
puts $f ""
puts $f "# Generate bitstream"
puts $f "write_bitstream -force $BUILD_DIR/output/design.bit"
puts $f ""
puts $f "# Exit"
puts $f "quit"
close $f

log "Synthesis script: $SYNTH_TCL"

# ==============================================================================
# 5. BUILD SUMMARY
# ==============================================================================

log ""
log "========== BUILD COMPLETE =========="
log "Project: $PROJECT_NAME"
log "Config:  $BUILD_CONFIG"
log "Output:  $OUTPUT_DIR"
log "Logs:    $LOG_DIR"
log ""
log "Artifacts:"
log "  - $FIRMWARE_ELF"
log "  - $FIRMWARE_BIN ($bin_size bytes)"
log "  - $FIRMWARE_HEX"
log "  - $FIRMWARE_MAP"
log "======================================="

# Save build info
set build_info_file "$LOG_DIR/build-info.txt"
set f [open $build_info_file w]
puts $f "Build Date: [clock format [clock seconds]]"
puts $f "Project: $PROJECT_NAME"
puts $f "Config: $BUILD_CONFIG"
puts $f "Firmware Size: $bin_size bytes"
puts $f "Status: SUCCESS"
close $f

log "Build info saved: $build_info_file"
