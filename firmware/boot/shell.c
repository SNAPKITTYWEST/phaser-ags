/*
 * Minimal Boot Shell
 * U-Boot command pattern: parse command → dispatch → print result
 */

#include "shell.h"
#include "board.h"
#include "../hal/timer.h"
#include "../hal/gpio.h"
#include "../hal/ethernet.h"
#include "../hal/mmc.h"
#include "../drivers/nand_flash.h"
#include "../drivers/nor_flash.h"

#define SHELL_MAX_LINE  128
#define SHELL_MAX_ARGS  8

static uart_dev_t *sh_console;
static timer_dev_t *sh_timer;

/* ---- Simple string utilities ---- */

static int str_eq(const char *a, const char *b) {
    while (*a && *b) {
        if (*a++ != *b++) return 0;
    }
    return (*a == 0 && *b == 0);
}

static int str_starts(const char *s, const char *prefix) {
    while (*prefix) {
        if (*s++ != *prefix++) return 0;
    }
    return 1;
}

static uint32_t parse_hex(const char *s) {
    uint32_t val = 0;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) s += 2;
    while (*s) {
        char c = *s++;
        if (c >= '0' && c <= '9')      val = (val << 4) | (c - '0');
        else if (c >= 'a' && c <= 'f')  val = (val << 4) | (c - 'a' + 10);
        else if (c >= 'A' && c <= 'F')  val = (val << 4) | (c - 'A' + 10);
        else break;
    }
    return val;
}

static int tokenize(char *line, char *argv[], int max) {
    int argc = 0;
    while (*line && argc < max) {
        while (*line == ' ') line++;
        if (!*line) break;
        argv[argc++] = line;
        while (*line && *line != ' ') line++;
        if (*line) *line++ = '\0';
    }
    return argc;
}

/* ---- Memory display (md) ---- */

static void cmd_md(int argc, char *argv[]) {
    if (argc < 2) {
        uart_puts(sh_console, "Usage: md <addr> [count]\r\n");
        return;
    }

    uint32_t addr = parse_hex(argv[1]);
    uint32_t count = (argc >= 3) ? parse_hex(argv[2]) : 16;
    volatile uint32_t *ptr = (volatile uint32_t *)addr;

    for (uint32_t i = 0; i < count; i += 4) {
        uart_put_hex(sh_console, addr + i * 4);
        uart_puts(sh_console, ": ");
        for (uint32_t j = 0; j < 4 && (i + j) < count; j++) {
            uart_put_hex(sh_console, ptr[i + j]);
            uart_puts(sh_console, " ");
        }
        uart_puts(sh_console, "\r\n");
    }
}

/* ---- Memory write (mw) ---- */

static void cmd_mw(int argc, char *argv[]) {
    if (argc < 3) {
        uart_puts(sh_console, "Usage: mw <addr> <value> [count]\r\n");
        return;
    }

    uint32_t addr = parse_hex(argv[1]);
    uint32_t value = parse_hex(argv[2]);
    uint32_t count = (argc >= 4) ? parse_hex(argv[3]) : 1;
    volatile uint32_t *ptr = (volatile uint32_t *)addr;

    for (uint32_t i = 0; i < count; i++) {
        ptr[i] = value;
    }

    uart_puts(sh_console, "Wrote ");
    uart_put_hex(sh_console, count);
    uart_puts(sh_console, " words\r\n");
}

/* ---- Go (jump to address) — U-Boot do_go pattern ---- */

static void cmd_go(int argc, char *argv[]) {
    if (argc < 2) {
        uart_puts(sh_console, "Usage: go <addr>\r\n");
        return;
    }

    uint32_t addr = parse_hex(argv[1]);

    uart_puts(sh_console, "## Starting application at ");
    uart_put_hex(sh_console, addr);
    uart_puts(sh_console, " ...\r\n");
    uart_flush(sh_console);

    /* Invalidate caches before jump */
    __asm__ volatile(
        "mov r0, #0\n"
        "mcr p15, 0, r0, c7, c5, 0\n"
        "mcr p15, 0, r0, c7, c6, 0\n"
        "dsb\nisb\n"
    );

    void (*entry)(void) = (void (*)(void))addr;
    entry();

    uart_puts(sh_console, "## Application returned\r\n");
}

/* ---- Reset — U-Boot do_reset pattern ---- */

static void cmd_reset(int argc, char *argv[]) {
    board_reset();
}

/* ---- Boot (load kernel and jump) ---- */

static void cmd_boot(int argc, char *argv[]) {
    uart_puts(sh_console, "Booting from default source...\r\n");
    /* This would call the Stage 2 kernel load logic */
    uart_puts(sh_console, "Not yet implemented — use go <addr>\r\n");
}

/* ---- NAND info ---- */

static void cmd_nand(int argc, char *argv[]) {
    nand_dev_t nand;
    if (nand_init(&nand, 0) != 0) {
        uart_puts(sh_console, "NAND init failed\r\n");
        return;
    }
    uart_puts(sh_console, "NAND: mfr=0x");
    uart_put_hex_byte(sh_console, nand.manufacturer_id);
    uart_puts(sh_console, " dev=0x");
    uart_put_hex_byte(sh_console, nand.device_id);
    uart_puts(sh_console, " page=");
    uart_put_hex(sh_console, nand.page_size);
    uart_puts(sh_console, " block=");
    uart_put_hex(sh_console, nand.pages_per_block * nand.page_size);
    uart_puts(sh_console, "\r\n");
}

/* ---- NOR info ---- */

static void cmd_nor(int argc, char *argv[]) {
    uint16_t mfr, dev;
    if (nor_flash_init(0) != 0) {
        uart_puts(sh_console, "NOR init failed\r\n");
        return;
    }
    nor_flash_read_id(0, &mfr, &dev);
    uart_puts(sh_console, "NOR: mfr=0x");
    uart_put_hex(sh_console, mfr);
    uart_puts(sh_console, " dev=0x");
    uart_put_hex(sh_console, dev);
    uart_puts(sh_console, "\r\n");
}

/* ---- Help ---- */

static void cmd_help(int argc, char *argv[]) {
    uart_puts(sh_console, "Phaser AGS Boot Shell\r\n");
    uart_puts(sh_console, "=====================\r\n");
    uart_puts(sh_console, "md <addr> [n]   — Memory display (32-bit words)\r\n");
    uart_puts(sh_console, "mw <addr> <val> [n] — Memory write\r\n");
    uart_puts(sh_console, "go <addr>       — Jump to address\r\n");
    uart_puts(sh_console, "boot            — Boot from default source\r\n");
    uart_puts(sh_console, "reset           — Reset board\r\n");
    uart_puts(sh_console, "nand            — NAND flash info\r\n");
    uart_puts(sh_console, "nor             — NOR flash info\r\n");
    uart_puts(sh_console, "help            — This help\r\n");
}

/* ---- Command dispatch ---- */

typedef struct {
    const char *name;
    void (*handler)(int argc, char *argv[]);
} shell_cmd_t;

static const shell_cmd_t shell_commands[] = {
    { "md",    cmd_md    },
    { "mw",    cmd_mw    },
    { "go",    cmd_go    },
    { "boot",  cmd_boot  },
    { "reset", cmd_reset },
    { "nand",  cmd_nand  },
    { "nor",   cmd_nor   },
    { "help",  cmd_help  },
    { "?",     cmd_help  },
};

#define NUM_COMMANDS (sizeof(shell_commands) / sizeof(shell_commands[0]))

/* ---- Line input with echo ---- */

static int readline(char *buf, int maxlen) {
    int pos = 0;
    while (pos < maxlen - 1) {
        char c = uart_getc(sh_console);

        if (c == '\r' || c == '\n') {
            buf[pos] = '\0';
            uart_puts(sh_console, "\r\n");
            return pos;
        } else if (c == 0x08 || c == 0x7F) {   /* Backspace */
            if (pos > 0) {
                pos--;
                uart_puts(sh_console, "\b \b");
            }
        } else if (c >= 0x20) {                   /* Printable */
            buf[pos++] = c;
            uart_putc(sh_console, c);
        }
    }
    buf[pos] = '\0';
    return pos;
}

/* ---- Main shell loop ---- */

void shell_run(uart_dev_t *console) {
    sh_console = console;

    char line[SHELL_MAX_LINE];
    char *argv[SHELL_MAX_ARGS];

    uart_puts(sh_console, "\r\nPhaser AGS> ");

    while (1) {
        int len = readline(line, SHELL_MAX_LINE);
        if (len == 0) {
            uart_puts(sh_console, "Phaser AGS> ");
            continue;
        }

        int argc = tokenize(line, argv, SHELL_MAX_ARGS);
        if (argc == 0) {
            uart_puts(sh_console, "Phaser AGS> ");
            continue;
        }

        /* Dispatch command */
        int found = 0;
        for (int i = 0; i < NUM_COMMANDS; i++) {
            if (str_eq(argv[0], shell_commands[i].name)) {
                shell_commands[i].handler(argc, argv);
                found = 1;
                break;
            }
        }

        if (!found) {
            uart_puts(sh_console, "Unknown command: ");
            uart_puts(sh_console, argv[0]);
            uart_puts(sh_console, "\r\n");
        }

        uart_puts(sh_console, "Phaser AGS> ");
    }
}
