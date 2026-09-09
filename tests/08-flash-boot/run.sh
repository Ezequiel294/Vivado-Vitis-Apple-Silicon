#!/usr/bin/env bash
# Test 08 — write the design to QSPI flash so it survives a power cycle.
source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "${1:-}" = "-y" ] && AUTO_YES=1

BIT="$TESTS/01-leds/leds.bit"
[ -f "$BIT" ] || fail "08-flash-boot: needs test 01's bitstream — run ../01-leds/run.sh first"

cat <<'EOF'

    This test writes to the board's NON-VOLATILE flash. Unlike every other
    test here, it persists: the board will boot this design at power-on until
    you overwrite or erase the flash.

    It also needs a jumper moved by hand.

EOF
if [ "$AUTO_YES" = 1 ]; then
    info "unattended mode: skipping (this test needs a physical jumper change)"
    exit 0
fi

step "Step 1 — set the MODE jumper"
info "Place a shunt on JP1 (labelled MODE) so the FPGA boots from QSPI flash."
info "With JP1 open the FPGA ignores the flash and waits for JTAG."
confirm "08-flash-boot: is the JP1 shunt fitted?"

step "Step 2 — writing to flash (slower than a normal download)"
require_board
openFPGALoader -b "$BOARD" -f "$BIT"

step "Step 3 — power-cycle the board"
info "Unplug the USB cable, wait a couple of seconds, plug it back in."
info "Do NOT reprogram it over JTAG — the point is that it boots on its own."
confirm "08-flash-boot: after the power cycle, do the switches still drive the LEDs?"

cat <<'EOF'

    The board now boots this design every time it powers on.

    To go back to the Digilent factory demo, or to stop it booting from
    flash, either remove the JP1 shunt or erase the flash:

        openFPGALoader -b arty_a7_100t --bulk-erase

EOF
