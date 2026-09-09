#!/usr/bin/env bash
# Test 02 — Vivado's simulator (xsim). No board required.
source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "${1:-}" = "-y" ] && AUTO_YES=1

step "Compiling and simulating"
require_docker
# xvlog parses, xelab elaborates, xsim runs. -R runs to completion and exits,
# so this is fully non-interactive.
OUT=$(docker exec -w "$(in_container "$HERE")" "$CONTAINER" bash -lc "
    source $XILINX/Vivado/settings64.sh &&
    rm -rf xsim.dir *.log *.jou *.pb *.wdb &&
    xvlog src/adder4.v sim/adder4_tb.v &&
    xelab -debug typical adder4_tb -s adder4_sim &&
    xsim adder4_sim -R" 2>&1) || { echo "$OUT"; fail "02-simulation: the simulator did not run"; }

echo "$OUT" | grep -E "CHECKED|MISMATCH|TEST (PASS|FAIL)" || true

if echo "$OUT" | grep -q "TEST PASS"; then
    ok "02-simulation: 512/512 vectors correct, simulator works"
else
    echo "$OUT" | tail -30
    fail "02-simulation: testbench did not report TEST PASS"
fi
