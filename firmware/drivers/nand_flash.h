/*
 * Driver — OMAP3530 GPMC NAND Flash driver
 * 8-bit bus, large-page (2KB + 64B spare), ONFI-compatible
 * Mapped at CS0 or CS1 → 0x40000000 (from memory-map.json)
 */

#ifndef FIRMWARE_DRIVERS_NAND_FLASH_H
#define FIRMWARE_DRIVERS_NAND_FLASH_H

#include "../common/types.h"
#include "../common/platform.h"

#define NAND_PAGE_SIZE       2048
#define NAND_SPARE_SIZE      64
#define NAND_PAGES_PER_BLOCK 64
#define NAND_BLOCK_SIZE      (NAND_PAGE_SIZE * NAND_PAGES_PER_BLOCK)  /* 128 KB */
#define NAND_ECC_CORRECTABLE 4   /* bits correctable by OMAP BCH ECC */

typedef struct {
    int      cs;
    uint32_t page_size;
    uint32_t spare_size;
    uint32_t pages_per_block;
    uint32_t total_blocks;
    uint8_t  manufacturer_id;
    uint8_t  device_id;
} nand_dev_t;

int  nand_init(nand_dev_t *dev, int cs);
void nand_read_id(nand_dev_t *dev);
int  nand_read_page(nand_dev_t *dev, uint32_t page, uint8_t *data, uint8_t *spare);
int  nand_write_page(nand_dev_t *dev, uint32_t page, const uint8_t *data, const uint8_t *spare);
int  nand_erase_block(nand_dev_t *dev, uint32_t block);
int  nand_is_bad_block(nand_dev_t *dev, uint32_t block);
int  nand_mark_bad_block(nand_dev_t *dev, uint32_t block);

#endif /* FIRMWARE_DRIVERS_NAND_FLASH_H */
