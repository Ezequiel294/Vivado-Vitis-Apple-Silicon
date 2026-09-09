#!/usr/bin/env bash
# Test 05 — the XVC bridge: container-side tools can see and program the board.
source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "${1:-}" = "-y" ] && AUTO_YES=1

BIT="$TESTS/01-leds/leds.bit"
[ -f "$BIT" ] || fail "05-xvc-program: needs test 01's bitstream — run ../01-leds/run.sh first"

trap xvc_stop EXIT
xvc_start

step "Programming over the bridge from inside the container"
if OUT=$(xsdb_batch "$HERE" "program.tcl $(in_container "$BIT")" 2>&1); then
    echo "$OUT"
else
    echo "$OUT"
    fail "05-xvc-program: xsdb could not program over the bridge"
fi

echo "$OUT" | grep -q "XVC PROGRAM OK" \
    || fail "05-xvc-program: no success marker in xsdb output"
echo "$OUT" | grep -qi "xc7a100t" \
    || info "note: expected xc7a100t in the scan chain listing"

ok "05-xvc-program: bridge up, device enumerated, bitstream downloaded"

step "Confirm on the board"
info "This programmed test 01's design, so the switches should drive the LEDs again."
confirm "05-xvc-program: do the switches control the LEDs?"
