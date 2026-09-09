#!/usr/bin/env bash
# Test 01 — switches drive LEDs. Builds, programs, then asks you to look.
source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "${1:-}" = "-y" ] && AUTO_YES=1

if [ ! -f "$HERE/leds.bit" ] || [ "$HERE/src/leds.v" -nt "$HERE/leds.bit" ]; then
    step "Building (a few minutes under emulation)"
    vivado_batch "$HERE" build.tcl
fi
[ -f "$HERE/leds.bit" ] || fail "01-leds: no bitstream produced"

step "Programming the board"
program "$HERE/leds.bit"

step "Check the board"
info "Flip the four slide switches (SW0..SW3, bottom edge)."
info "Each should light the green LED above it (LD4..LD7) and nothing else."
confirm "01-leds: does every switch control its own LED?"
