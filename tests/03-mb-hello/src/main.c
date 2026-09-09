/*
 * Test 03 — proves a C program compiled in Vitis actually executes on the
 * MicroBlaze and can talk to the outside world.
 *
 * Prints a recognisable banner, then counts forever so you can tell "running"
 * apart from "printed once and hung". The LEDs are not driven here — this
 * test is about the software toolchain and the UART.
 */
#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"

int main(void)
{
    init_platform();

    xil_printf("\r\n");
    xil_printf("=== TEST 03 MB-HELLO ===\r\n");
    xil_printf("MicroBlaze is alive and running your C code.\r\n");
    xil_printf("Counting once per second; press RESET to start over.\r\n");

    /* No timer peripheral in this platform, so this is a calibrated-ish busy
     * wait. The exact rate does not matter — visible, steady progress does. */
    for (int n = 1;; n++) {
        for (volatile long i = 0; i < 3000000; i++) { }
        xil_printf("tick %d\r\n", n);
    }

    cleanup_platform();
    return 0;
}
