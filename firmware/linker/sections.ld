/* ARM Cortex-A8 Section Definitions */

OUTPUT_ARCH(arm)
ENTRY(_start)

SECTIONS
{
  /* Reset vector and exception vectors */
  .vector_table (NOLOAD) : {
    KEEP(*(.vector_table))
    . = ALIGN(32);
  } > RESET_VECTOR

  /* Boot code - loaded first */
  .boot : ALIGN(4) {
    __boot_start = .;
    KEEP(*(.boot))
    KEEP(*(.boot.*))
    __boot_end = .;
  } > SRAM AT > FLASH

  /* Text section (code) */
  .text : ALIGN(4) {
    __text_start = .;
    *(.text)
    *(.text.*)
    *(.gnu.linkonce.t.*)
    . = ALIGN(4);
    __text_end = .;
  } > SRAM AT > FLASH

  /* Read-only data */
  .rodata : ALIGN(4) {
    __rodata_start = .;
    *(.rodata)
    *(.rodata.*)
    *(.gnu.linkonce.r.*)
    . = ALIGN(4);
    __rodata_end = .;
  } > SRAM AT > FLASH

  /* Initialized data */
  .data : ALIGN(4) {
    __data_start = .;
    *(.data)
    *(.data.*)
    *(.gnu.linkonce.d.*)
    . = ALIGN(4);
    __data_end = .;
  } > SRAM AT > FLASH
  __data_load_start = LOADADDR(.data);
  __data_load_size = SIZEOF(.data);

  /* Uninitialized data (BSS) */
  .bss (NOLOAD) : ALIGN(4) {
    __bss_start = .;
    *(.bss)
    *(.bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > SRAM

  /* Stack */
  .stack (NOLOAD) : ALIGN(16) {
    __stack_start = .;
    . += 0x4000;
    . = ALIGN(16);
    __stack_end = .;
  } > SRAM

  /* Heap */
  .heap (NOLOAD) : ALIGN(16) {
    __heap_start = .;
    . += 0x8000;
    . = ALIGN(16);
    __heap_end = .;
  } > SRAM

  /* Discard unused sections */
  /DISCARD/ : {
    *(.note.GNU-stack)
    *(.gnu_debuglink)
    *(.gnu.lto_*)
  }
}

/* Linker-defined symbols */
__etext = __data_load_start + __data_load_size;
