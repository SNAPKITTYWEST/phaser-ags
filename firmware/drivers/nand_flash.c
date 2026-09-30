/*
 * Driver — OMAP3530 GPMC NAND Flash driver
 * Uses GPMC NAND command/address/data register windows
 */

#include "nand_flash.h"

static hw_reg32_t nand_cmd_reg(int cs)  { return (hw_reg32_t)GPMC_NAND_CMD(cs); }
static hw_reg32_t nand_addr_reg(int cs) { return (hw_reg32_t)GPMC_NAND_ADDR(cs); }
static hw_reg32_t nand_data_reg(int cs) { return (hw_reg32_t)GPMC_NAND_DATA(cs); }

static void nand_send_cmd(nand_dev_t *dev, uint8_t cmd) {
    reg_write8((hw_reg8_t)nand_cmd_reg(dev->cs), cmd);
    delay_cycles(50);
}

static void nand_send_addr(nand_dev_t *dev, uint8_t addr) {
    reg_write8((hw_reg8_t)nand_addr_reg(dev->cs), addr);
    delay_cycles(25);
}

static uint8_t nand_read_byte(nand_dev_t *dev) {
    return reg_read8((hw_reg8_t)nand_data_reg(dev->cs));
}

static void nand_write_byte(nand_dev_t *dev, uint8_t val) {
    reg_write8((hw_reg8_t)nand_data_reg(dev->cs), val);
}

static void nand_wait_ready(nand_dev_t *dev) {
    uint32_t timeout = 2000000;
    while (timeout--) {
        nand_send_cmd(dev, NAND_CMD_STATUS);
        uint8_t status = nand_read_byte(dev);
        if (status & NAND_STATUS_READY)
            return;
    }
}

int nand_init(nand_dev_t *dev, int cs) {
    hw_reg32_t gpmc = (hw_reg32_t)GPMC_BASE;
    dev->cs = cs;
    dev->page_size = NAND_PAGE_SIZE;
    dev->spare_size = NAND_SPARE_SIZE;
    dev->pages_per_block = NAND_PAGES_PER_BLOCK;

    /* Configure GPMC for NAND on this CS */
    reg_write32(gpmc + GPMC_CONFIG1(cs),
        GPMC_CONFIG1_DEVICETYPE_NAND |
        (0x00 << 12) |      /* MWIDTH: 8-bit */
        (0x00 << 18)        /* No wait pin */
    );

    /* NAND timings — conservative */
    reg_write32(gpmc + GPMC_CONFIG2(cs), (0x08 << 0) | (0x0C << 8));
    reg_write32(gpmc + GPMC_CONFIG3(cs), (0x02 << 0) | (0x04 << 8));
    reg_write32(gpmc + GPMC_CONFIG4(cs), (0x03 << 0) | (0x08 << 8) | (0x03 << 16) | (0x08 << 24));
    reg_write32(gpmc + GPMC_CONFIG5(cs), (0x02 << 0) | (0x02 << 8));
    reg_write32(gpmc + GPMC_CONFIG6(cs), 0x00);

    /* Set NAND base address and validate CS */
    reg32_t config7 = (0x40 << 0) |     /* Base [31:24] = 0x40 → 0x40000000 */
                      (0x0F << 8) |     /* 256MB mask */
                      GPMC_CONFIG7_CSVALID;
    reg_write32(gpmc + GPMC_CONFIG7(cs), config7);

    /* Enable NAND pipeline prefetch (GPMC prefetch engine) */
    reg_write32(gpmc + GPMC_CONFIG, 0x10);

    /* Reset the NAND device */
    nand_send_cmd(dev, NAND_CMD_RESET);
    nand_wait_ready(dev);
    delay_cycles(5000);

    /* Read ID to populate dev info */
    nand_read_id(dev);

    return 0;
}

void nand_read_id(nand_dev_t *dev) {
    nand_send_cmd(dev, NAND_CMD_READID);
    nand_send_addr(dev, 0x00);
    delay_cycles(50);
    dev->manufacturer_id = nand_read_byte(dev);
    dev->device_id = nand_read_byte(dev);
    /* Skip 3rd and 4th ID bytes for now */
    nand_read_byte(dev);
    nand_read_byte(dev);
}

int nand_read_page(nand_dev_t *dev, uint32_t page, uint8_t *data, uint8_t *spare) {
    uint32_t block = page / dev->pages_per_block;
    uint32_t page_in_block = page % dev->pages_per_block;

    /* Column = 0 (start of page), Row = page number */
    nand_send_cmd(dev, NAND_CMD_READ0);
    nand_send_addr(dev, 0x00);                     /* Column low */
    nand_send_addr(dev, 0x00);                     /* Column high */
    nand_send_addr(dev, page_in_block & 0xFF);     /* Row low */
    nand_send_addr(dev, (page_in_block >> 8) & 0xFF); /* Row mid */
    nand_send_addr(dev, block & 0xFF);             /* Row high (for >128MB) */
    nand_send_cmd(dev, NAND_CMD_READSTART);

    nand_wait_ready(dev);

    /* Read main page data */
    for (uint32_t i = 0; i < dev->page_size; i++) {
        data[i] = nand_read_byte(dev);
    }

    /* Read spare area */
    if (spare) {
        for (uint32_t i = 0; i < dev->spare_size; i++) {
            spare[i] = nand_read_byte(dev);
        }
    }

    /* Check status for uncorrectable ECC error (simplified) */
    nand_send_cmd(dev, NAND_CMD_STATUS);
    uint8_t status = nand_read_byte(dev);
    if (status & NAND_STATUS_FAIL)
        return -1;

    return 0;
}

int nand_write_page(nand_dev_t *dev, uint32_t page, const uint8_t *data, const uint8_t *spare) {
    uint32_t block = page / dev->pages_per_block;
    uint32_t page_in_block = page % dev->pages_per_block;

    nand_send_cmd(dev, NAND_CMD_SEQIN);
    nand_send_addr(dev, 0x00);
    nand_send_addr(dev, 0x00);
    nand_send_addr(dev, page_in_block & 0xFF);
    nand_send_addr(dev, (page_in_block >> 8) & 0xFF);
    nand_send_addr(dev, block & 0xFF);

    /* Write main page data */
    for (uint32_t i = 0; i < dev->page_size; i++) {
        nand_write_byte(dev, data[i]);
    }

    /* Write spare area */
    if (spare) {
        for (uint32_t i = 0; i < dev->spare_size; i++) {
            nand_write_byte(dev, spare[i]);
        }
    }

    nand_send_cmd(dev, NAND_CMD_PAGEPROG);
    nand_wait_ready(dev);

    nand_send_cmd(dev, NAND_CMD_STATUS);
    uint8_t status = nand_read_byte(dev);
    if (status & NAND_STATUS_FAIL)
        return -1;

    return 0;
}

int nand_erase_block(nand_dev_t *dev, uint32_t block) {
    nand_send_cmd(dev, NAND_CMD_ERASE1);
    nand_send_addr(dev, block & 0xFF);
    nand_send_addr(dev, (block >> 8) & 0xFF);
    nand_send_addr(dev, (block >> 16) & 0xFF);
    nand_send_cmd(dev, NAND_CMD_ERASE2);
    nand_wait_ready(dev);

    nand_send_cmd(dev, NAND_CMD_STATUS);
    uint8_t status = nand_read_byte(dev);
    if (status & NAND_STATUS_FAIL)
        return -1;

    return 0;
}

int nand_is_bad_block(nand_dev_t *dev, uint32_t block) {
    uint8_t spare[NAND_SPARE_SIZE];
    uint32_t page = block * dev->pages_per_block;

    if (nand_read_page(dev, page, (uint8_t *)0, spare) != 0)
        return 1;  /* Can't read = treat as bad */

    /* Bad block marker is at spare[0] for first page of block.
       0xFF = good, anything else = bad */
    return (spare[0] != 0xFF);
}

int nand_mark_bad_block(nand_dev_t *dev, uint32_t block) {
    uint8_t spare[NAND_SPARE_SIZE];
    uint32_t page = block * dev->pages_per_block;

    /* Fill spare with 0x00 to mark bad */
    for (int i = 0; i < NAND_SPARE_SIZE; i++)
        spare[i] = 0x00;

    return nand_write_page(dev, page, (const uint8_t *)0, spare);
}
