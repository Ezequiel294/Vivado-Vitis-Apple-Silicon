#!/usr/bin/env bash
# Test 06 — MicroBlaze interactive debug over XVC. KNOWN BROKEN.
#
# Exit codes are inverted compared to the other tests:
#   0 = still broken (the documented, expected state)
#   2 = it worked — the limitation is FIXED, go update the docs
#   1 = the test could not run (bridge down, missing inputs)
source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BOOT="$TESTS/03-mb-hello/mb-hello-boot.bit"
ELF="$TESTS/03-mb-hello/vitis/hello/build/hello.elf"
[ -f "$BOOT" ] || fail "06-mb-debug: needs test 03's boot bitstream — run ../03-mb-hello/run.sh first"
[ -f "$ELF" ]  || fail "06-mb-debug: needs test 03's ELF — run ../03-mb-hello/run.sh first"

trap xvc_stop EXIT
xvc_start

step "Attempting MicroBlaze debug operations (stop / dow / con)"
info "openFPGALoader version: $(openFPGALoader --Version 2>&1 | head -1 || echo unknown)"

OUT=$(xsdb_batch "$HERE" "debug-test.tcl $(in_container "$BOOT") $(in_container "$ELF")" 2>&1) || true
echo "$OUT"
echo "$OUT" >"$HERE/last-run.log"

echo
if echo "$OUT" | grep -q "BASELINE BROKEN"; then
    fail "06-mb-debug: could not run — the bridge or programming path is down, fix test 05 first"
elif echo "$OUT" | grep -q "MDM-DEBUG-NOW-WORKING"; then
    printf '\033[32m*** MicroBlaze debug WORKS NOW ***\033[0m\n'
    info "The known limitation is fixed. Update:"
    info "  - tests/README.md status table"
    info "  - repo README.md section 7"
    info "  - repo journal.md section 15"
    exit 2
elif echo "$OUT" | grep -q "MDM-DEBUG-PARTIAL"; then
    printf '\033[33m*** Behaviour CHANGED (partial success) ***\033[0m\n'
    info "Some debug operations now work. Worth investigating — see last-run.log"
    exit 2
elif echo "$OUT" | grep -q "MDM-DEBUG-STILL-BROKEN"; then
    ok "06-mb-debug: still broken, exactly as documented (expected result)"
    info "The 'not being clocked' error is bogus — test 03 proves the CPU runs fine."
    exit 0
else
    fail "06-mb-debug: unrecognised output, read last-run.log"
fi
