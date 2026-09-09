#!/usr/bin/env bash
# Test 07 — ILA/VIO on-chip debug over the XVC bridge. OUTCOME UNKNOWN.
#
# Builds and programs, then leaves the bridge running so you can drive the
# cores from the Vivado GUI — the part only a human can judge.
source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "${1:-}" = "-y" ] && AUTO_YES=1

if [ ! -f "$HERE/ila_vio.bit" ] || [ "$HERE/src/ila_vio_top.v" -nt "$HERE/ila_vio.bit" ]; then
    step "Building (debug cores make this slower than test 01)"
    vivado_batch "$HERE" build.tcl
fi
[ -f "$HERE/ila_vio.bit" ] || fail "07-ila-vio: no bitstream produced"
[ -f "$HERE/ila_vio.ltx" ] || info "WARNING: no .ltx probe file — Hardware Manager won't name the probes"

step "Programming the board"
program "$HERE/ila_vio.bit"

step "Heartbeat check (proves the design is live, independent of the debug cores)"
info "LD7 (rightmost green LED) should be blinking about once a second."
confirm "07-ila-vio: is LD7 blinking?"

if [ "$AUTO_YES" = 1 ]; then
    ok "07-ila-vio: built and programmed; ILA/VIO interaction needs the GUI (unverified)"
    exit 0
fi

step "Starting the bridge for Hardware Manager"
xvc_start
cat <<EOF

    Leave this running. In the Vivado GUI inside the container:

      1. Flow → Open Hardware Manager
      2. Open Target → Open New Target → Next
      3. Local server → Next   (a device named xc7a100t_0 should appear)
      4. If the probes aren't loaded automatically, set the probes file to:
             $HERE/ila_vio.ltx
      5. The hw_ila_1 window shows the waveform. Click ▶ (Run trigger
         immediate) — you should see the 32-bit counter incrementing.
      6. The hw_vio_1 window lists probe_in0 (the switches) and probe_out0.
         Flip a physical switch: probe_in0 should follow it.
         Type a value into probe_out0: LEDs LD4-LD6 should change.

    Press Enter here when you're done to shut the bridge down.
EOF
read -r _ </dev/tty
xvc_stop

echo
info "Record what happened — this is the outcome nobody knew in advance:"
confirm "07-ila-vio: did the ILA capture a waveform AND the VIO read/drive probes?"
