/*
 * Driver — OMAP3530 GPMC NOR Flash driver
 * Intel JS28F256M29EWH via GPMC CS0
 */

#include "nor_flash.h"

static hw_reg32_t nor_base(int cs) {
    return (hw_reg32_t)(NOR_FLASH_BASE + cs * 0x10000000UL);
}

static void nor_write_cmd(int cs, uint32_t offset, uint16_t cmd) {
    hw_reg32_t base = nor_base(cs);
    volatile uint16_t *flash = (volatile uint16_t *)base;
    flash[offset] = cmd;
    __asm__ volatile("dmb" ::: "memory");
}

static uint16_t nor_read_reg(int cs, uint32_t offset) {
    hw_reg32_t base = nor_base(cs);
    volatile uint16_t *flash = (volatile uint16_t *)base;
    return flash[offset];
}

int nor_flash_init(int cs) {
    hw_reg32_t gpmc = (hw_reg32_t)GPMC_BASE;

    /* Enable GPMC */
    reg_write32(gpmc + GPMC_SYSCONFIG, 0x10);  /* Smart idle */
    delay_cycles(100);

    /* Configure CS0 for 16-bit NOR flash, async */
    reg_write32(gpmc + GPMC_CONFIG1(cs),
        (0x00 << 0) |       /* DEVICETYPE: NOR async */
        (0x02 << 12) |      /* MWIDTH: 16-bit */
        (0x01 << 18)        /* WAITPIN: WAIT0 */
    );

    /* CS signal timings — conservative for initial bring-up */
    reg_write32(gpmc + GPMC_CONFIG2(cs),
        (0x08 << 0) |       /* CS_ON: 8 cycles */
        (0x1F << 8)         /* CS_WR_OFF: 31 cycles */
    );

    reg_write32(gpmc + GPMC_CONFIG3(cs),
        (0x02 << 0) |       /* ADV_ON: 2 cycles */
        (0x06 << 8)         /* ADV_WR_OFF: 6 cycles */
    );

    reg_write32(gpmc + GPMC_CONFIG4(cs),
        (0x03 << 0) |       /* OE_ON: 3 cycles */
        (0x0C << 8) |       /* OE_OFF: 12 cycles */
        (0x03 << 16) |      /* WE_ON: 3 cycles */
        (0x0C << 24)        /* WE_OFF: 12 cycles */
    );

    reg_write32(gpmc + GPMC_CONFIG5(cs),
        (0x02 << 0) |       /* RD_CYCLE: 2 extra */
        (0x02 << 8) |       /* WR_CYCLE: 2 extra */
        (0x02 << 16) |      /* RD_ACCESS: 2 cycles */
        (0x02 << 24)        /* WR_ACCESS: 2 cycles */
    );

    reg_write32(gpmc + GPMC_CONFIG6(cs),
        (0x00 << 0) |       /* WR_DATA_MUX: 0 */
        (0x02 << 8) |       /* WR_ACCESS: 2 cycles */
        (0x00 << 16)        /* CYCLE2CYCLE: no delay */
    );

    /* Set base address and enable CS */
    reg32_t config7 = (0x08 << 0) |    /* Base address bits [31:24] = 0x08 → 0x08000000 */
                      (0x0F << 8) |    /* Mask: 256MB region */
                      GPMC_CONFIG7_CSVALID;
    reg_write32(gpmc + GPMC_CONFIG7(cs), config7);

    /* Reset flash to read mode */
    nor_flash_reset(cs);

    return 0;
}

void nor_flash_read_id(int cs, uint16_t *manufacturer, uint16_t *device) {
    nor_write_cmd(cs, 0, NOR_CMD_READ_ID);
    delay_cycles(100);
    *manufacturer = nor_read_reg(cs, 0);
    *device = nor_read_reg(cs, 1);
    nor_flash_reset(cs);
}

void nor_flash_reset(int cs) {
    nor_write_cmd(cs, 0, NOR_CMD_RESET);
    delay_cycles(500);
}

int nor_flash_erase_sector(int cs, uint32_t offset) {
    nor_write_cmd(cs, 0, NOR_CMD_ERASE);
    nor_write_cmd(cs, offset >> 1, NOR_CMD_CONFIRM);

    /* Poll for completion (status bit 7 toggles when done) */
    volatile uint16_t *flash = (volatile uint16_t *)nor_base(cs);
    uint32_t timeout = 5000000;
    while (timeout--) {
        uint16_t status = flash[offset >> 1];
        if (status & 0x0080)  /* DSQ7: done */
            break;
    }

    nor_flash_reset(cs);

    /* Verify erased (should read 0xFFFF) */
    if (flash[offset >> 1] != 0xFFFF)
        return -1;

    return 0;
}

int nor_flash_program_word(int cs, uint32_t offset, uint16_t data) {
    volatile uint16_t *flash = (volatile uint16_t *)nor_base(cs);
    uint32_t word_offset = offset >> 1;

    nor_write_cmd(cs, 0, NOR_CMD_PROG);
    flash[word_offset] = data;
    __asm__ volatile("dmb" ::: "memory");

    /* Poll for completion */
    uint32_t timeout = 1000000;
    while (timeout--) {
        uint16_t status = flash[word_offset];
        if ((status & 0x0080) && (status == data))
            break;
    }

    nor_flash_reset(cs);

    if (flash[word_offset] != data)
        return -1;

    return 0;
}

int nor_flash_program_buf(int cs, uint32_t offset, const uint16_t *buf, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        if (nor_flash_program_word(cs, offset + i * 2, buf[i]) != 0)
            return -1;
    }
    return 0;
}

int nor_flash_read_buf(int cs, uint32_t offset, uint16_t *buf, uint32_t count) {
    volatile uint16_t *flash = (volatile uint16_t *)nor_base(cs);
    uint32_t word_offset = offset >> 1;

    for (uint32_t i = 0; i < count; i++) {
        buf[i] = flash[word_offset + i];
    }
    return 0;
}
