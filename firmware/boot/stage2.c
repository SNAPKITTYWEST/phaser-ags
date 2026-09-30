/*
 * ARM Cortex-A8 (OMAP3530) Stage 2 Bootloader
 *
 * Full firmware stack: MMU, Ethernet, SPI, MMC, shell
 * Integrates patterns from IMX6 Platinum and R8A7740:
 *   - platinum_setup_enet(): PHY reset → pinmux → MDIO → link check
 *   - platinum_setup_spi(): McSPI pinmux for FPGA config
 *   - spl_dram_init(): MMU + cache enable after DRAM init
 *   - do_go / do_reset: boot shell fallback
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
#include "../hal/spi.h"
#include "../hal/ethernet.h"
#include "../hal/mmc.h"
#include "../drivers/sdram.h"
#include "../drivers/nand_flash.h"
#include "../drivers/nor_flash.h"
#include "board.h"
#include "shell.h"

/* ---- Console + peripherals ---- */
static uart_dev_t console;
static timer_dev_t systimer;
static gpio_dev_t gpio1;
static eth_dev_t eth0;
static mmc_dev_t mmc1;

#define STAGE2_MAGIC  0x53544132UL
typedef struct {
    uint32_t magic;
    uint32_t size;
    uint32_t crc32;
    uint32_t entry_offset;
} stage2_header_t;

/* ---- MMU identity mapping (1MB sections, 4GB) ---- */
__attribute__((aligned(16384)))
static uint32_t mmu_table[4096];

static void mmu_init(void) {
    for (int i = 0; i < 4096; i++) {
        uint32_t pa = (uint32_t)i << 20;

        if (pa >= 0x30000000UL && pa < 0x40000000UL) {
            mmu_table[i] = pa | 0x00001C0E;   /* DRAM: WB, full access */
        } else if (pa < 0x00020000UL) {
            mmu_table[i] = pa | 0x0000040E;   /* SRAM: WT */
        } else if ((pa >= 0x48000000UL && pa < 0x4A000000UL) ||
                   (pa >= 0x6C000000UL && pa < 0x70000000UL)) {
            mmu_table[i] = pa | 0x0000180E;   /* Peripherals: device, XN */
        } else {
            mmu_table[i] = pa | 0x0000000E;   /* Strongly ordered */
        }
    }

    __asm__ volatile(
        "mcr p15, 0, %0, c2, c0, 0\n"
        "mov r0, #0\n"
        "mcr p15, 0, r0, c2, c0, 2\n"
        "mov r0, #0\n"
        "mcr p15, 0, r0, c3, c0, 0\n"
        "mov r0, #0\n"
        "mcr p15, 0, r0, c8, c7, 0\n"
        "dsb\nisb\n"
        :: "r"(mmu_table)
    );

    __asm__ volatile(
        "mrc p15, 0, r0, c1, c0, 0\n"
        "orr r0, r0, #(1 << 0)\n"
        "orr r0, r0, #(1 << 2)\n"
        "orr r0, r0, #(1 << 12)\n"
        "orr r0, r0, #(1 << 11)\n"
        "orr r0, r0, #(1 << 13)\n"
        "dsb\n"
        "mcr p15, 0, r0, c1, c0, 0\n"
        "isb\n"
    );
}

/* ---- Ethernet setup — platinum_setup_enet() pattern ---- */

static int setup_ethernet(void) {
    uart_puts(&console, "Setting up Ethernet...\r\n");

    if (eth_init(&eth0, MDIO_BASE, EMAC_BASE, 0) != 0) {
        uart_puts(&console, "EMAC init failed\r\n");
        return -1;
    }

    /* PHY reset via GPIO1[9] — mirrors IMX6 Platinum:
       1. Assert PHY reset while pinmux is configured
       2. Wait 10ms
       3. Release reset
       4. Wait 100µs for PHY startup */
    eth_phy_reset(&eth0, &gpio1, 9);

    if (eth_phy_config(&eth0) != 0) {
        uart_puts(&console, "PHY config failed\r\n");
        return -1;
    }

    /* Check link */
    if (eth_link_check(&eth0) > 0) {
        uart_puts(&console, "Ethernet: LINK UP at ");
        uart_put_hex(&console, eth0.link_speed);
        uart_puts(&console, "Mbps\r\n");
    } else {
        uart_puts(&console, "Ethernet: no link\r\n");
    }

    return 0;
}

/* ---- SPI setup — platinum_setup_spi() pattern ---- */

static spi_dev_t spi1;

static int setup_spi(void) {
    uart_puts(&console, "Setting up McSPI1...\r\n");

    /* Enable McSPI1 clock */
    hw_reg32_t cm = (hw_reg32_t)CM_BASE;
    reg_set32(cm + CM_FCLKEN1_CORE, (1 << 18));   /* EN_MCSPI1 */
    reg_set32(cm + CM_ICLKEN1_CORE, (1 << 18));
    delay_cycles(500);

    if (spi_init(&spi1, MCSPI1_BASE, 0, REF_CLK_HZ, 1000000, SPI_MODE_0, 8) != 0) {
        uart_puts(&console, "McSPI1 init failed\r\n");
        return -1;
    }

    uart_puts(&console, "McSPI1 ready (1MHz, mode 0)\r\n");
    return 0;
}

/* ---- MMC setup — for SD card kernel boot ---- */

static int setup_mmc(void) {
    uart_puts(&console, "Setting up MMC1 (SD card)...\r\n");

    /* Enable MMC1 clock */
    hw_reg32_t cm = (hw_reg32_t)CM_BASE;
    reg_set32(cm + CM_FCLKEN1_CORE, (1 << 24));   /* EN_MMC1 */
    reg_set32(cm + CM_ICLKEN1_CORE, (1 << 24));
    delay_cycles(500);

    if (mmc_init(&mmc1, MMC1_BASE, REF_CLK_HZ) != 0) {
        uart_puts(&console, "MMC1 init failed\r\n");
        return -1;
    }

    if (mmc_detect_card(&mmc1) != 0) {
        uart_puts(&console, "No SD card detected\r\n");
        return -1;
    }

    uart_puts(&console, "SD card: RCA=0x");
    uart_put_hex(&console, mmc1.rca);
    uart_puts(&console, " width=");
    uart_put_hex(&console, mmc1.bus_width);
    uart_puts(&console, " SDHC=");
    uart_puts(&console, mmc1.high_capacity ? "yes" : "no");
    uart_puts(&console, "\r\n");

    return 0;
}

/* ---- FPGA NCONFIG reset — IMX6 Platinum platinum_init_gpio() pattern ---- */
/* OMAP3530 version: 3 FPGAs on SPI bus, NCONFIG via GPIO */

#define GPIO_FPGA1_NCONFIG  10   /* GPIO1[10] */
#define GPIO_FPGA2_NCONFIG  11   /* GPIO1[11] */
#define GPIO_FPGA3_NCONFIG  12   /* GPIO1[12] */

static void fpga_init_gpio(void) {
    /* Configure NCONFIG pins as outputs — mirrors IMX6:
       gpio_direction_output(GPIO_IP_NCONFIG, 0) */
    gpio_set_output(&gpio1, GPIO_FPGA1_NCONFIG);
    gpio_set_output(&gpio1, GPIO_FPGA2_NCONFIG);
    gpio_set_output(&gpio1, GPIO_FPGA3_NCONFIG);

    /* Assert NCONFIG low (reset all FPGAs) */
    gpio_write(&gpio1, GPIO_FPGA1_NCONFIG, 0);
    gpio_write(&gpio1, GPIO_FPGA2_NCONFIG, 0);
    gpio_write(&gpio1, GPIO_FPGA3_NCONFIG, 0);

    /* Wait 3µs (IMX6 Platinum: udelay(3)) */
    delay_cycles(CPU_CLK_HZ / 333333);  /* ~3µs */

    /* Release NCONFIG — FPGAs begin configuration from SPI */
    gpio_write(&gpio1, GPIO_FPGA1_NCONFIG, 1);
    gpio_write(&gpio1, GPIO_FPGA2_NCONFIG, 1);
    gpio_write(&gpio1, GPIO_FPGA3_NCONFIG, 1);

    uart_puts(&console, "[FPGA] NCONFIG released — configuration via SPI\r\n");
}

/* ---- Load kernel from MMC ---- */

#define ZIMAGE_MAGIC  0x016F2818UL

typedef struct {
    uint32_t code[4];
    uint32_t magic;
    uint32_t start;
    uint32_t end;
} zimage_header_t;

static int load_kernel_mmc(void) {
    /* Read MBR + kernel from SD card sectors to DRAM */
    uint8_t *dst = (uint8_t *)DRAM_KERNEL_BASE;

    /* Kernel typically starts at sector 2048 (1MB offset, FAT boot partition) */
    uart_puts(&console, "Loading kernel from MMC (sector 2048)...\r\n");

    for (uint32_t sec = 0; sec < 8192; sec++) {
        if (mmc_read_block(&mmc1, 2048 + sec, dst + sec * MMC_BLOCK_SIZE) != 0) {
            uart_puts(&console, "MMC read error at sector ");
            uart_put_hex(&console, 2048 + sec);
            uart_puts(&console, "\r\n");
            return -1;
        }
    }

    uart_puts(&console, "Loaded 4MB from MMC\r\n");
    return 0;
}

/* ---- Load kernel from NAND ---- */

static int load_kernel_nand(void) {
    nand_dev_t nand;
    if (nand_init(&nand, 0) != 0) return -1;

    uint8_t page_buf[NAND_PAGE_SIZE];
    uint8_t *dst = (uint8_t *)DRAM_KERNEL_BASE;
    uint32_t copied = 0;

    for (uint32_t block = 8; block < 64 && copied < DRAM_KERNEL_SIZE; block++) {
        if (nand_is_bad_block(&nand, block)) continue;
        for (uint32_t page = 0; page < nand.pages_per_block && copied < DRAM_KERNEL_SIZE; page++) {
            uint32_t abs_page = block * nand.pages_per_block + page;
            if (nand_read_page(&nand, abs_page, page_buf, (uint8_t *)0) != 0) return -1;
            for (uint32_t i = 0; i < nand.page_size && copied < DRAM_KERNEL_SIZE; i++)
                dst[copied++] = page_buf[i];
        }
    }

    uart_puts(&console, "Loaded ");
    uart_put_hex(&console, copied);
    uart_puts(&console, " bytes from NAND\r\n");
    return (copied > 0) ? 0 : -1;
}

/* ================================================================ */

void stage2_main(void) {
    /* 1. Console */
    uart_init(&console, UART0_BASE, REF_CLK_HZ);
    uart_configure(&console, 115200, 8, 0, 1);
    uart_puts(&console, "\r\n=============================\r\n");
    uart_puts(&console, " Phaser AGS Stage 2 Bootloader\r\n");
    uart_puts(&console, "=============================\r\n");

    /* 2. Timer */
    timer_init(&systimer, GPTIMER2_BASE, REF_CLK_HZ);

    /* 3. MMU + caches (IMX6 SPL: spl_dram_init then enable caches) */
    uart_puts(&console, "Enabling MMU and caches...\r\n");
    mmu_init();
    uart_puts(&console, "MMU + I$/D$ enabled\r\n");

    /* 4. GPIO + status LED */
    gpio_init(&gpio1, 1);
    gpio_set_output(&gpio1, 8);
    gpio_write(&gpio1, 8, 1);

    /* 5. Interrupt controller */
    intc_init();

    /* 6. SPI setup (platinum_setup_spi pattern) */
    setup_spi();

    /* 7. Ethernet setup (platinum_setup_enet pattern) */
    setup_ethernet();

    /* 8. MMC setup (for SD card boot) */
    int mmc_ok = (setup_mmc() == 0);

    /* 9. FPGA init (platinum_init_gpio: NCONFIG reset) */
    fpga_init_gpio();

    /* 10. Load kernel */
    volatile zimage_header_t *zimg = (volatile zimage_header_t *)DRAM_KERNEL_BASE;

    /* Try MMC first, then NAND */
    int kernel_loaded = 0;

    if (mmc_ok && load_kernel_mmc() == 0) {
        kernel_loaded = 1;
    } else if (load_kernel_nand() == 0) {
        kernel_loaded = 1;
    }

    if (kernel_loaded && zimg->magic == ZIMAGE_MAGIC) {
        uint32_t ksize = zimg->end - zimg->start;
        uart_puts(&console, "Linux zImage: ");
        uart_put_hex(&console, ksize);
        uart_puts(&console, " bytes\r\n");

        /* Blink LED 3× then boot */
        for (int i = 0; i < 3; i++) {
            gpio_write(&gpio1, 8, 1);
            timer_delay_ms(&systimer, 50);
            gpio_write(&gpio1, 8, 0);
            timer_delay_ms(&systimer, 50);
        }

        uart_puts(&console, "Booting kernel at ");
        uart_put_hex(&console, DRAM_KERNEL_BASE);
        uart_puts(&console, "...\r\n");
        uart_flush(&console);

        uint32_t machine_type = 0x862;
        uint32_t dtb_addr = 0x30000000;

        __asm__ volatile(
            "dsb\nisb\n"
            "mov r0, #0\n"
            "mov r1, %0\n"
            "mov r2, %1\n"
            "bx  %2\n"
            :
            : "r"(machine_type), "r"(dtb_addr), "r"(DRAM_KERNEL_BASE)
            : "r0", "r1", "r2", "memory"
        );
    }

    /* 11. No kernel found or boot failed — drop to shell (U-Boot do_go pattern) */
    uart_puts(&console, "\r\nNo kernel loaded. Dropping to shell.\r\n");
    uart_puts(&console, "Use 'go <addr>' to jump, or 'help' for commands.\r\n\r\n");

    shell_run(&console);
}
