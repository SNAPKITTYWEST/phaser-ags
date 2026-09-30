# Phaser AGS Universal Embedded Board — Full Firmware Build
# ARM Cortex-A8 (OMAP3530) — arm-none-eabi-gcc

PROJECT := phaser-ags-universal
ARCH    := arm
CPU     := cortex-a8
OUTDIR  := ./output

# ---- Toolchain ----
CC      := arm-none-eabi-gcc
LD      := arm-none-eabi-ld
OBJCOPY := arm-none-eabi-objcopy
NM      := arm-none-eabi-nm
SIZE    := arm-none-eabi-size

# ---- Source directories ----
FIRMWARE_DIR := ../firmware
COMMON_DIR   := $(FIRMWARE_DIR)/common
HAL_DIR      := $(FIRMWARE_DIR)/hal
DRIVER_DIR   := $(FIRMWARE_DIR)/drivers
BOOT_DIR     := $(FIRMWARE_DIR)/boot

# ---- HAL sources ----
HAL_SRC := $(HAL_DIR)/uart.c \
           $(HAL_DIR)/gpio.c \
           $(HAL_DIR)/timer.c \
           $(HAL_DIR)/interrupt.c \
           $(HAL_DIR)/clock.c

# ---- Driver sources ----
DRIVER_SRC := $(DRIVER_DIR)/sdram.c \
              $(DRIVER_DIR)/nor_flash.c \
              $(DRIVER_DIR)/nand_flash.c

# ---- Boot sources ----
STAGE1_SRC := $(BOOT_DIR)/stage1.c
STAGE2_SRC := $(BOOT_DIR)/stage2.c

# ---- Include paths ----
INCLUDES := -I$(COMMON_DIR) \
            -I$(HAL_DIR) \
            -I$(DRIVER_DIR) \
            -I$(BOOT_DIR)

# ---- Linker scripts ----
STAGE1_LD := $(FIRMWARE_DIR)/linker/boot.ld
STAGE2_LD := $(FIRMWARE_DIR)/linker/boot.ld

# ---- Compiler flags ----
CFLAGS := -mcpu=$(CPU) -mfpu=neon -mfloat-abi=hard
CFLAGS += -Wall -Wextra -Werror
CFLAGS += -nostdlib -nostartfiles -ffreestanding
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -O2 -g3
CFLAGS += $(INCLUDES)

# ---- Linker flags ----
LDFLAGS_COMMON := --gc-sections --cref

LDFLAGS_STAGE1 := -T$(STAGE1_LD) $(LDFLAGS_COMMON) -Map=$(OUTDIR)/stage1.map
LDFLAGS_STAGE2 := -T$(STAGE2_LD) $(LDFLAGS_COMMON) -Map=$(OUTDIR)/stage2.map

# ---- Output files ----
STAGE1_ELF := $(OUTDIR)/stage1.elf
STAGE1_BIN := $(OUTDIR)/stage1.bin
STAGE1_HEX := $(OUTDIR)/stage1.hex
STAGE1_SYM := $(OUTDIR)/stage1.sym

STAGE2_ELF := $(OUTDIR)/stage2.elf
STAGE2_BIN := $(OUTDIR)/stage2.bin
STAGE2_HEX := $(OUTDIR)/stage2.hex
STAGE2_SYM := $(OUTDIR)/stage2.sym

# ---- Object file lists ----
STAGE1_OBJ := $(OUTDIR)/stage1.o $(OUTDIR)/hal_uart.o $(OUTDIR)/hal_gpio.o \
              $(OUTDIR)/hal_timer.o $(OUTDIR)/hal_interrupt.o $(OUTDIR)/hal_clock.o \
              $(OUTDIR)/drv_sdram.o $(OUTDIR)/drv_nor.o $(OUTDIR)/drv_nand.o

STAGE2_OBJ := $(OUTDIR)/stage2.o $(OUTDIR)/hal_uart2.o $(OUTDIR)/hal_gpio2.o \
              $(OUTDIR)/hal_timer2.o $(OUTDIR)/hal_interrupt2.o $(OUTDIR)/hal_clock2.o \
              $(OUTDIR)/drv_sdram2.o $(OUTDIR)/drv_nor2.o $(OUTDIR)/drv_nand2.o

.PHONY: all stage1 stage2 clean symbols info

all: stage1 stage2

# ---- Create output directory ----
$(OUTDIR):
	@mkdir -p $@
	@echo "[BUILD] Created $(OUTDIR)"

# ---- HAL object files (Stage 1) ----
$(OUTDIR)/hal_uart.o: $(HAL_DIR)/uart.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/hal_gpio.o: $(HAL_DIR)/gpio.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/hal_timer.o: $(HAL_DIR)/timer.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/hal_interrupt.o: $(HAL_DIR)/interrupt.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/hal_clock.o: $(HAL_DIR)/clock.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

# ---- Driver object files (Stage 1) ----
$(OUTDIR)/drv_sdram.o: $(DRIVER_DIR)/sdram.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/drv_nor.o: $(DRIVER_DIR)/nor_flash.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/drv_nand.o: $(DRIVER_DIR)/nand_flash.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

# ---- HAL object files (Stage 2 — same sources, different output names) ----
$(OUTDIR)/hal_uart2.o: $(HAL_DIR)/uart.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/hal_gpio2.o: $(HAL_DIR)/gpio.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/hal_timer2.o: $(HAL_DIR)/timer.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/hal_interrupt2.o: $(HAL_DIR)/interrupt.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/hal_clock2.o: $(HAL_DIR)/clock.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/drv_sdram2.o: $(DRIVER_DIR)/sdram.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/drv_nor2.o: $(DRIVER_DIR)/nor_flash.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUTDIR)/drv_nand2.o: $(DRIVER_DIR)/nand_flash.c | $(OUTDIR)
	$(CC) $(CFLAGS) -c $< -o $@

# ---- Stage 1 ----
stage1: $(STAGE1_ELF) $(STAGE1_BIN) $(STAGE1_HEX)

$(OUTDIR)/stage1.o: $(BOOT_DIR)/stage1.c | $(OUTDIR)
	@echo "[COMPILE] stage1.c"
	$(CC) $(CFLAGS) -c $< -o $@

$(STAGE1_ELF): $(STAGE1_OBJ)
	@echo "[LINK] stage1.elf"
	$(LD) $(LDFLAGS_STAGE1) -o $@ $^
	@echo "[SIZE] Stage 1:"
	$(SIZE) $@

$(STAGE1_BIN): $(STAGE1_ELF)
	@echo "[OBJCOPY] stage1.bin"
	$(OBJCOPY) -O binary $< $@

$(STAGE1_HEX): $(STAGE1_ELF)
	@echo "[OBJCOPY] stage1.hex"
	$(OBJCOPY) -O ihex $< $@

# ---- Stage 2 ----
stage2: $(STAGE2_ELF) $(STAGE2_BIN) $(STAGE2_HEX)

$(OUTDIR)/stage2.o: $(BOOT_DIR)/stage2.c | $(OUTDIR)
	@echo "[COMPILE] stage2.c"
	$(CC) $(CFLAGS) -c $< -o $@

$(STAGE2_ELF): $(STAGE2_OBJ)
	@echo "[LINK] stage2.elf"
	$(LD) $(LDFLAGS_STAGE2) -o $@ $^
	@echo "[SIZE] Stage 2:"
	$(SIZE) $@

$(STAGE2_BIN): $(STAGE2_ELF)
	@echo "[OBJCOPY] stage2.bin"
	$(OBJCOPY) -O binary $< $@

$(STAGE2_HEX): $(STAGE2_ELF)
	@echo "[OBJCOPY] stage2.hex"
	$(OBJCOPY) -O ihex $< $@

# ---- Symbols ----
symbols: stage1 stage2
	$(NM) -n $(STAGE1_ELF) > $(STAGE1_SYM)
	$(NM) -n $(STAGE2_ELF) > $(STAGE2_SYM)
	@echo "[SYM] Symbol tables generated"

# ---- Info ----
info:
	@echo "Project:     $(PROJECT)"
	@echo "Architecture: $(ARCH) ($(CPU))"
	@echo "Toolchain:   $(CC)"
	@echo "Output:      $(OUTDIR)/"
	@echo ""
	@echo "Stage 1:  $(STAGE1_SRC)"
	@echo "  + HAL:  $(HAL_SRC)"
	@echo "  + DRV:  $(DRIVER_SRC)"
	@echo "  Linker: $(STAGE1_LD)"
	@echo ""
	@echo "Stage 2:  $(STAGE2_SRC)"
	@echo "  + HAL:  $(HAL_SRC)"
	@echo "  + DRV:  $(DRIVER_SRC)"
	@echo "  Linker: $(STAGE2_LD)"

# ---- Clean ----
clean:
	@echo "[CLEAN] Removing $(OUTDIR)"
	rm -rf $(OUTDIR)

distclean: clean
	@echo "[DISTCLEAN] Removing all generated files"
	rm -f *.d

-include $(OUTDIR)/*.d
