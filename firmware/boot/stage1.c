/*
 * ARM Cortex-A8 (OMAP3530) Stage 1 Bootloader — C Entry
 *
 * Called from start.S after assembly lowlevel_init completes:
 *   - DPLLs locked (600MHz CPU, 266MHz DDR)
 *   - SDRC initialized (JEDEC sequence complete)
 *   - GPMC configured (NOR CS0, NAND CS1)
 *   - Stack and BSS ready
 *
 * This file: console init, board init, Stage 2 load + validate + jump
 */

#include "../common/types.h"
#include "../common/platform.h"
#include "../hal/uart.h"
#include "../hal/gpio.h"
#include "../hal/timer.h"
#include "../hal/interrupt.h"
#include "../hal/clock.h"
#include "../hal/pinmux.h"
#include "../hal/i2c.h"
#include "../drivers/sdram.h"
#include "../drivers/nor_flash.h"
#include "../drivers/nand_flash.h"
#include "board.h"

/* ---- Console UART ---- */
static uart_dev_t console;

/* ---- CRC32 (Ethernet polynomial) ---- */
static uint32_t crc32_table[256];

static void crc32_init(void) {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t crc = i;
        for (int j = 0; j < 8; j++) {
            if (crc & 1)
                crc = (crc >> 1) ^ 0xEDB88320UL;
            else
                crc >>= 1;
        }
        crc32_table[i] = crc;
    }
}

static uint32_t crc32_compute(const uint8_t *data, uint32_t len) {
    uint32_t crc = 0xFFFFFFFFUL;
    for (uint32_t i = 0; i < len; i++) {
        crc = (crc >> 8) ^ crc32_table[(crc ^ data[i]) & 0xFF];
    }
    return crc ^ 0xFFFFFFFFUL;
}

/* ---- Boot source detection via SYS_BOOT pins ---- */
static boot_source_t detect_boot_source(void) {
    hw_reg32_t scm = (hw_reg32_t)SCM_BASE;
    reg32_t sysboot = reg_read32(scm + 0x2F0) & 0x1F;
    switch (sysboot) {
        case 0x00: return BOOT_SOURCE_NAND;
        case 0x01: return BOOT_SOURCE_NOR;
        case 0x02: return BOOT_SOURCE_UART;
        case 0x03: return BOOT_SOURCE_MMC;
        default:   return BOOT_SOURCE_UNKNOWN;
    }
}

/* ---- Load Stage 2 from NOR Flash ---- */
static int load_stage2_nor(void) {
    uart_puts(&console, "Loading Stage 2 from NOR Flash...\r\n");

    if (nor_flash_init(0) != 0) {
        uart_puts(&console, "NOR Flash init failed\r\n");
        return -1;
    }

    uint16_t mfr, dev;
    nor_flash_read_id(0, &mfr, &dev);
    uart_puts(&console, "NOR Flash ID: mfr=");
    uart_put_hex(&console, mfr);
    uart_puts(&console, " dev=");
    uart_put_hex(&console, dev);
    uart_puts(&console, "\r\n");

    volatile uint8_t *src = (volatile uint8_t *)(NOR_FLASH_BASE + 0x40000);
    volatile uint8_t *dst = (volatile uint8_t *)DRAM_BOOT_BASE;

    for (uint32_t i = 0; i < DRAM_BOOT_SIZE; i++) {
        dst[i] = src[i];
    }

    return 0;
}

/* ---- Load Stage 2 from NAND Flash ---- */
static int load_stage2_nand(void) {
    uart_puts(&console, "Loading Stage 2 from NAND Flash...\r\n");

    nand_dev_t nand;
    if (nand_init(&nand, 0) != 0) {
        uart_puts(&console, "NAND Flash init failed\r\n");
        return -1;
    }

    uart_puts(&console, "NAND ID: mfr=");
    uart_put_hex_byte(&console, nand.manufacturer_id);
    uart_puts(&console, " dev=");
    uart_put_hex_byte(&console, nand.device_id);
    uart_puts(&console, "\r\n");

    uint32_t start_block = 1;
    uint8_t page_buf[NAND_PAGE_SIZE];
    uint8_t *dst = (uint8_t *)DRAM_BOOT_BASE;
    uint32_t copied = 0;

    for (uint32_t block = start_block; block < 8 && copied < DRAM_BOOT_SIZE; block++) {
        if (nand_is_bad_block(&nand, block))
            continue;

        for (uint32_t page = 0; page < nand.pages_per_block && copied < DRAM_BOOT_SIZE; page++) {
            uint32_t abs_page = block * nand.pages_per_block + page;
            if (nand_read_page(&nand, abs_page, page_buf, (uint8_t *)0) != 0) {
                uart_puts(&console, "NAND read error\r\n");
                return -1;
            }
            for (uint32_t i = 0; i < nand.page_size && copied < DRAM_BOOT_SIZE; i++) {
                dst[copied++] = page_buf[i];
            }
        }
    }

    uart_puts(&console, "Loaded ");
    uart_put_hex(&console, copied);
    uart_puts(&console, " bytes from NAND\r\n");

    return 0;
}

/* ---- Stage 2 header ---- */
#define STAGE2_MAGIC  0x53544132UL

typedef struct {
    uint32_t magic;
    uint32_t size;
    uint32_t crc32;
    uint32_t entry_offset;
} stage2_header_t;

static int validate_stage2(void) {
    volatile stage2_header_t *hdr = (volatile stage2_header_t *)DRAM_BOOT_BASE;

    if (hdr->magic != STAGE2_MAGIC) {
        uart_puts(&console, "Stage 2: bad magic (");
        uart_put_hex(&console, hdr->magic);
        uart_puts(&console, ")\r\n");
        return -1;
    }

    if (hdr->size > DRAM_BOOT_SIZE) {
        uart_puts(&console, "Stage 2: too large\r\n");
        return -1;
    }

    crc32_init();
    uint32_t computed = crc32_compute(
        (const uint8_t *)(DRAM_BOOT_BASE + sizeof(stage2_header_t)),
        hdr->size - sizeof(stage2_header_t)
    );

    if (computed != hdr->crc32) {
        uart_puts(&console, "Stage 2: CRC mismatch\r\n");
        return -1;
    }

    uart_puts(&console, "Stage 2 validated (");
    uart_put_hex(&console, hdr->size);
    uart_puts(&console, " bytes, CRC OK)\r\n");
    return 0;
}

/* ================================================================ */
/*              RESET HANDLER — C entry from start.S                */
/* ================================================================ */

void reset_handler(void) {
    /* 1. Board early init (pinmux, peripheral clocks) */
    board_early_init_f();

    /* 2. Console UART */
    uart_init(&console, UART0_BASE, REF_CLK_HZ);
    uart_configure(&console, 115200, 8, 0, 1);

    uart_puts(&console, "\r\n");
    uart_puts(&console, "=============================\r\n");
    uart_puts(&console, " Phaser AGS Stage 1 Bootloader\r\n");
    uart_puts(&console, " OMAP3530 Cortex-A8 @ 600MHz\r\n");
    uart_puts(&console, "=============================\r\n");

    /* 3. Board init (GPIO, I2C PMIC, SDRAM verify) */
    if (board_init() != 0) {
        uart_puts(&console, "Board init FAILED\r\n");
        while(1);
    }

    /* 4. Detect boot source and load Stage 2 */
    boot_source_t boot = detect_boot_source();
    uart_puts(&console, "Boot source: ");
    switch (boot) {
        case BOOT_SOURCE_NAND: uart_puts(&console, "NAND\r\n"); break;
        case BOOT_SOURCE_NOR:  uart_puts(&console, "NOR\r\n");  break;
        case BOOT_SOURCE_UART: uart_puts(&console, "UART\r\n"); break;
        case BOOT_SOURCE_MMC:  uart_puts(&console, "MMC\r\n");  break;
        default:               uart_puts(&console, "UNKNOWN\r\n"); break;
    }

    int load_result = -1;
    switch (boot) {
        case BOOT_SOURCE_NAND:
            load_result = load_stage2_nand();
            break;
        case BOOT_SOURCE_NOR:
            load_result = load_stage2_nor();
            break;
        default:
            uart_puts(&console, "Unsupported boot source\r\n");
            while(1);
    }

    if (load_result != 0) {
        uart_puts(&console, "Stage 2 load FAILED\r\n");
        while(1);
    }

    /* 5. Validate Stage 2 */
    if (validate_stage2() != 0) {
        uart_puts(&console, "Stage 2 validation FAILED\r\n");
        while(1);
    }

    /* 6. Board late init */
    board_late_init();

    /* 7. Jump to Stage 2 */
    volatile stage2_header_t *hdr = (volatile stage2_header_t *)DRAM_BOOT_BASE;
    void (*stage2_entry)(void) = (void (*)(void))(DRAM_BOOT_BASE + hdr->entry_offset);

    uart_puts(&console, "Jumping to Stage 2 at ");
    uart_put_hex(&console, (uint32_t)stage2_entry);
    uart_puts(&console, "\r\n\r\n");
    uart_flush(&console);

    __asm__ volatile(
        "mov r0, #0\n"
        "mcr p15, 0, r0, c7, c5, 0\n"  /* Invalidate I-cache */
        "mcr p15, 0, r0, c7, c6, 0\n"  /* Invalidate D-cache */
        "dsb\n"
        "isb\n"
    );

    stage2_entry();

    uart_puts(&console, "Stage 2 returned unexpectedly\r\n");
    while(1);
}
