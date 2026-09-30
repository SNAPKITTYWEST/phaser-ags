#!/usr/bin/tclsh
# Source file configuration

# RTL sources
set RTL_SOURCES {
  ../rtl/top.v
  ../rtl/cpu_wrapper.v
  ../rtl/memory_controller.v
  ../rtl/uart_controller.v
  ../rtl/gpio_controller.v
  ../rtl/interrupt_controller.v
  ../rtl/timer_controller.v
}

# Constraint files
set CONSTRAINT_FILES {
  ../constraints/board.xdc
  ../constraints/timing.xdc
  ../constraints/power.xdc
}

# Firmware files
set FIRMWARE_FILES {
  ../firmware/linker/memory.ld
  ../firmware/linker/sections.ld
  ../firmware/linker/boot.ld
  ../boot/arm/stage1.c
}

# Simulation sources
set SIM_SOURCES {
  ../sim/tb_top.v
  ../sim/tb_uart.v
  ../sim/tb_memory.v
}

# IP cores (if using Vivado)
set IP_CORES {
  # xilinx:ip:zynq_ultra_ps_e:1.3
  # xilinx:ip:clk_wiz:6.0
}

puts "RTL sources: [llength $RTL_SOURCES]"
puts "Constraints: [llength $CONSTRAINT_FILES]"
puts "Firmware: [llength $FIRMWARE_FILES]"
