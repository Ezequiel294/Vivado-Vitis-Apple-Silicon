#!/usr/bin/env bash
# Run the whole suite in dependency order.
#
#   ./run-all.sh          interactive — asks you to confirm what only eyes can
#   ./run-all.sh -y       unattended  — builds/programs, skips visual checks
#
# Test 08 is excluded: it writes persistent flash and needs a jumper moved by
# hand, so it is always run deliberately and on its own.
source "$(dirname "${BASH_SOURCE[0]}")/common/lib.sh"

YES=""
[ "${1:-}" = "-y" ] && YES="-y"

TESTS_TO_RUN=(01-leds 02-simulation 03-mb-hello 04-serial-input 05-xvc-program 06-mb-debug 07-ila-vio)

declare -a RESULTS=()
overall=0

for t in "${TESTS_TO_RUN[@]}"; do
    printf '\n\033[1m########## %s ##########\033[0m\n' "$t"
    if "$TESTS/$t/run.sh" $YES; then
        rc=0
    else
        rc=$?
    fi

    case "$t:$rc" in
        06-mb-debug:0) RESULTS+=("$t: still broken (expected)") ;;
        06-mb-debug:2) RESULTS+=("$t: NOW WORKING - update the docs!") ;;
        *:0)           RESULTS+=("$t: pass") ;;
        *)             RESULTS+=("$t: FAIL (exit $rc)"); overall=1 ;;
    esac

    # Stop on a real failure; there is no point running dependents.
    if [ "$overall" = 1 ]; then
        info "stopping — later tests depend on this one"
        break
    fi
done

printf '\n\033[1m########## SUMMARY ##########\033[0m\n'
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo
echo "  08-flash-boot: not run (writes flash — run it by hand)"

if [ "$YES" = "-y" ]; then
    echo
    info "Unattended run: visual checks were skipped. Tests 01, 03, 04, 07 are"
    info "NOT verified by this — only their builds and downloads are."
fi

exit "$overall"
