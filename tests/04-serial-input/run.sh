#!/usr/bin/env bash
# Test 04 — typed characters reach the FPGA (serial RX path).
source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "${1:-}" = "-y" ] && AUTO_YES=1

if [ ! -f "$HERE/uart_echo.bit" ] || [ "$HERE/src/uart_echo.v" -nt "$HERE/uart_echo.bit" ]; then
    step "Building"
    vivado_batch "$HERE" build.tcl
fi
[ -f "$HERE/uart_echo.bit" ] || fail "04-serial-input: no bitstream produced"

step "Programming the board"
program "$HERE/uart_echo.bit"

step "Check the serial console"
cat <<'EOF'
    In another terminal:

        screen /dev/cu.usbserial-*1 9600      (exit: Ctrl-A then K, then y)

    Type some lowercase letters, e.g.  hello world

    Expect:
      - each letter comes back UPPERCASE:  HELLO WORLD
      - the LEDs change as you type (they show the low 4 bits of the last byte)

    Uppercase is the point: a plain mirror could come from the cable or the
    driver, but case conversion can only have happened inside the FPGA.
EOF
confirm "04-serial-input: do typed letters come back uppercased, and do the LEDs move?"
