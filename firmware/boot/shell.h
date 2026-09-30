/*
 * Minimal Boot Shell — modeled on U-Boot command interface
 * Commands: go, reset, md, mw, boot, help
 * Like IMX6 Platinum: do_go for jumping, do_reset for board reset
 */

#ifndef FIRMWARE_BOOT_SHELL_H
#define FIRMWARE_BOOT_SHELL_H

#include "../common/types.h"
#include "../hal/uart.h"

void shell_run(uart_dev_t *console);

#endif /* FIRMWARE_BOOT_SHELL_H */
