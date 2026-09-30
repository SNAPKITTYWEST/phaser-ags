/*
 * Driver — OMAP3530 GPMC NOR Flash driver
 * Intel JS28F256M29EWH: 256Mbit (32MB), 16-bit bus, CFI-compatible
 * Mapped at CS0 → 0x08000000 (from memory-map.json)
 */

#ifndef FIRMWARE_DRIVERS_NOR_FLASH_H
#define FIRMWARE_DRIVERS_NOR_FLASH_H

#include "../common/types.h"
#include "../common/platform.h"

#define NOR_SECTOR_SIZE    0x20000UL   /* 128 KB sectors (typical for this device) */
#define NOR_CHIP_SIZE      0x10000000UL /* 256 MB */

int  nor_flash_init(int cs);
void nor_flash_read_id(int cs, uint16_t *manufacturer, uint16_t *device);
int  nor_flash_erase_sector(int cs, uint32_t offset);
int  nor_flash_program_word(int cs, uint32_t offset, uint16_t data);
int  nor_flash_program_buf(int cs, uint32_t offset, const uint16_t *buf, uint32_t count);
int  nor_flash_read_buf(int cs, uint32_t offset, uint16_t *buf, uint32_t count);
void nor_flash_reset(int cs);

#endif /* FIRMWARE_DRIVERS_NOR_FLASH_H */
