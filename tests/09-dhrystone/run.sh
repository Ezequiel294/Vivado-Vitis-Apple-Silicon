#!/usr/bin/env bash
#
# Test 09 — run the Dhrystone benchmark on the MicroBlaze.
#
# Proves the whole benchmarking path works without the Vitis IDE:
#   * an application created from a toolchain-supplied template (dhrystone),
#     with its own sources, BSP libraries and linker settings left alone
#   * the compiler settings an assignment specifies (-O3, no debug)
#   * updatemem on a 128 kB local memory — far larger than any other test
#   * a serial transcript legible despite bare-LF line endings
#
# See README.md. Takes roughly 20-30 minutes, most of it Vivado.
#
#   ./run.sh                 # build everything, program, capture, check
#   ./run.sh --no-hw         # reuse the existing bitstream
#   AUTO_YES=1 ./run.sh      # no prompts
#
source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"

HERE="$TESTS/09-dhrystone"
APP=dhry
DO_HW=1
LOG="$HERE/dhrystone.log"

while [ $# -gt 0 ]; do
    case "$1" in
        --no-hw) DO_HW=0; shift ;;
        -h|--help) awk 'NR>2 && !/^#/ {exit} NR>2 {sub(/^# ?/,""); print}' "$0"; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

# --- 1. hardware --------------------------------------------------------
if [ "$DO_HW" = 1 ]; then
    step "Building the hardware (MicroBlaze, 128 kB LMB, AXI Timer, 100 MHz)"
    info "this is the slow part — roughly 15-25 minutes under emulation"
    vivado_batch "$HERE" build-hw.tcl
    grep -q "BUILD OK" "$HERE/vivado.log" || fail "hardware build did not finish (see $HERE/vivado.log)"
    grep "GUARDS OK" "$HERE/vivado.log" | tail -1
fi
[ -f "$HERE/system_wrapper.xsa" ] || fail "no system_wrapper.xsa — run without --no-hw first"

# --- 2. application -----------------------------------------------------
# No -s: the dhrystone template brings dhry_1.c, dhry_2.c and platform.c, and
# make-app.sh must not put a main.c anywhere near them.
step "Creating the Dhrystone application at -O3 with no debug info"
"$FPGA_WORK/tools/make-app.sh" -d "$HERE" -a "$APP" -t dhrystone -O -O3 -g none \
    2>&1 | tee "$HERE/build.log"

for f in dhry_1.c dhry_2.c platform.c; do
    [ -f "$HERE/vitis/$APP/src/$f" ] || fail "the template's $f is missing — was it overwritten?"
done
if [ -f "$HERE/vitis/$APP/src/main.c" ]; then
    fail "a main.c was injected into a template app"
fi

step "Code size (this is the figure Homework 2 asks for)"
grep -A2 "^   text" "$HERE/build.log" | tail -2 | tee "$HERE/codesize.txt"

# --- 3. bake and program ------------------------------------------------
step "Baking dhry.elf into the 128 kB local memory and programming"
info "first exercise of updatemem at this memory size — if it fails, it fails here"
"$FPGA_WORK/tools/run-sw.sh" -d "$HERE" -a "$APP" --no-build

# --- 4. capture ---------------------------------------------------------
# Only now, never during programming: JTAG traffic on channel A costs UART
# bytes on channel B (journal §12).
step "Capturing the benchmark output"
info "160000 iterations — expect roughly 5-20 seconds of silence, then a burst"
if capture_serial "$LOG" 180 "The Dhrystone App has run successfully"; then
    info "benchmark reported success"
else
    fail "no completion message within 180s — see $LOG
If the log is empty: press the board's RESET button and re-run with --no-hw.
If it is garbage: something else is programmed, or the baud rate is wrong."
fi

# --- 5. check -----------------------------------------------------------
step "Checking the results"
dps=$(grep -a "Dhrystones per Second:" "$LOG" | tail -1 | awk '{print $NF}')
[ -n "$dps" ] || fail "no 'Dhrystones per Second' line in $LOG"
case "$dps" in
    0|0.0000|"") fail "Dhrystones per Second is $dps — the timer never advanced.
Check that the AXI Timer is mapped into the processor's address space." ;;
esac

echo
grep -aE "Microseconds for one run|Dhrystones per Second|DMIPS" "$LOG"
echo
ok "Dhrystone ran to completion at $dps Dhrystones/second"
info "transcript: $LOG"
info "code size:  $HERE/codesize.txt"
info "For Homework 2, repeat with the two other processor configurations —"
info "see the 'Deriving the other configurations' section of README.md."
