#!/usr/bin/env bash
#
# serial.sh — watch the board's serial output, and keep a copy of it.
#
# Use this instead of `screen` when the output is hard to read or you want a
# transcript to quote in a report. Programs from the Vitis examples (Dhrystone
# among them) end their lines with a bare LF, which stair-steps down the screen
# under `screen` or `cat`; this fixes that for the terminal while writing the
# board's bytes to the log exactly as sent.
#
# This is the macOS equivalent of setting TeraTerm's "Receive new-line" to LF.
#
#   ./tools/serial.sh                       # watch until Ctrl-C, log to serial.log
#   ./tools/serial.sh -o dhry.log           # ...to a log file you name
#   ./tools/serial.sh -t 60                 # stop after 60 seconds
#   ./tools/serial.sh -u "run successfully" # stop when that text appears
#
# Options:
#   -o, --out      log file                     (default: serial.log)
#   -t, --time     seconds to capture, 0 = no limit  (default: 0)
#   -u, --until    stop as soon as this text appears
#
# It cannot send input — it only listens. When the program expects you to type,
# use `screen /dev/cu.usbserial-*1 9600` (exit: Ctrl-A then K, then y).
#
# Press the board's RESET button to re-run the program from the start.
#
source "$(dirname "${BASH_SOURCE[0]}")/../tests/common/lib.sh"

LOG=serial.log
SECS=0
UNTIL=""

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--out)   LOG=$2;   shift 2 ;;
        -t|--time)  SECS=$2;  shift 2 ;;
        -u|--until) UNTIL=$2; shift 2 ;;
        -h|--help)  awk 'NR>2 && !/^#/ {exit} NR>2 {sub(/^# ?/,""); print}' "$0"; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

case "$SECS" in
    ''|*[!0-9]*) die "--time wants a whole number of seconds (0 for no limit), got: $SECS" ;;
esac

# Ctrl-C is the normal way to stop an open-ended capture, so treat it as
# success and still tell the user where the transcript went.
trap 'printf "\n"; info "stopped — transcript: $LOG"; exit 0' INT

if capture_serial "$LOG" "$SECS" "$UNTIL"; then
    echo
    ok "transcript saved to $LOG"
else
    echo
    fail "nothing matching \"$UNTIL\" within ${SECS}s — transcript so far: $LOG
If the log is empty, press the board's RESET button and try again."
fi
