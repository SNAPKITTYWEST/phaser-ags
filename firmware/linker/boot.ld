/* ARM Boot Linker Script - Stage 1 Bootloader */

INCLUDE memory.ld
INCLUDE sections.ld

/* Boot-specific settings */

OUTPUT_FORMAT(elf32-littlearm)
TARGET(elf32-littlearm)

ENTRY(_start)

/* Force sections to load at specific addresses */
SECTIONS
{
  /* Ensure boot code starts at SRAM origin */
  . = 0x00000000;

  .reset_vectors : ALIGN(4) {
    KEEP(*(.vectors))
    KEEP(*(.vector_table))
    . = ALIGN(32);
  }

  /* Stage 1 bootloader must be compact */
  .stage1 : {
    KEEP(*(.stage1_start))
    *(.text.stage1)
    *(.rodata.stage1)
    . = ALIGN(4);
  }

  /* Everything else follows */
  .text : {
    *(.text)
    *(.text.*)
  }

  .rodata : {
    *(.rodata)
    *(.rodata.*)
  }

  .data : {
    *(.data)
    *(.data.*)
    . = ALIGN(4);
  }

  .bss (NOLOAD) : {
    *(.bss)
    *(.bss.*)
    *(COMMON)
    . = ALIGN(4);
  }

  /* Stack at fixed location for bootloader */
  .stack (NOLOAD) : ALIGN(16) {
    . = 0x20010000;  /* Stack at DRAM boundary */
    . += 0x4000;
  }
}

/* Stage2 handoff location */
__stage2_load_addr = 0x30000000;
__stage2_entry = 0x30000000;

/* Boot configuration */
__reset_vector = 0xFFF00000;
__stack_base = 0x20010000;
__stack_top = 0x20014000;
