#!/usr/bin/env bash
#
# make-app.sh — create the Vitis platform + application for a Vivado design.
#
# Replaces the Vitis IDE's "New Platform"/"New Application Project" wizards,
# which we cannot use because the IDE does not run under emulation
# (journal section 20). Run this ONCE per project; after that use run-sw.sh
# to rebuild and flash.
#
#   ./tools/make-app.sh -d projects/Test_Microblaze
#   ./tools/make-app.sh -d projects/lab4 -a blinky -s projects/lab4/src/blinky.c
#   ./tools/make-app.sh -d projects/hw2 -a dhry -t dhrystone -O -O3 -g none
#
# Options:
#   -d, --dir        the Vivado project directory (required)
#   -a, --app        application name                    (default: hello)
#   -s, --src        your C file                         (default: <dir>/src/main.c)
#   -c, --cpu        processor instance                  (default: microblaze_0)
#   -x, --xsa        path to the .xsa                    (default: the one in <dir>)
#   -t, --template   Vitis app template                  (default: hello_world)
#   -O, --opt        optimization level: -O0 -O1 -O2 -O3 -Os
#   -g, --debug      debug level: -g1 -g2 -g3, or 'none' for no debug info
#
# --opt and --debug are the Vitis IDE's Build > Settings page. Passing either
# one for an app that already exists updates the setting and rebuilds, so you
# can measure the same program at a different optimization level.
#
# A template other than hello_world brings its own sources — you do not write
# a main.c for it, and rebuilds will not overwrite what it ships.
#
# Before running, in Vivado: Generate Bitstream, then
#   File > Export > Export Hardware... > Include bitstream
# and save the .xsa into the project directory.
#
source "$(dirname "${BASH_SOURCE[0]}")/../tests/common/lib.sh"

DIR=""; APP=hello; SRC=""; CPU=microblaze_0; XSA=""; TEMPLATE=hello_world
OPT=""; DEBUG=""
while [ $# -gt 0 ]; do
    case "$1" in
        -d|--dir)  DIR=$2; shift 2 ;;
        -a|--app)  APP=$2; shift 2 ;;
        -s|--src)  SRC=$2; shift 2 ;;
        -c|--cpu)  CPU=$2; shift 2 ;;
        -x|--xsa)  XSA=$2; shift 2 ;;
        -t|--template) TEMPLATE=$2; shift 2 ;;
        -O|--opt)      OPT=$2; shift 2 ;;
        -g|--debug)    DEBUG=$2; shift 2 ;;
        -h|--help) awk 'NR>2 && !/^#/ {exit} NR>2 {sub(/^# ?/,""); print}' "$0"; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done
[ -n "$DIR" ] || die "which project? pass -d <dir> (try --help)"
case "$DIR" in /*) PROJ=$DIR ;; *) PROJ="$FPGA_WORK/$DIR" ;; esac
[ -d "$PROJ" ] || die "no such directory: $PROJ"

# Resolve optional paths the same way, so relative arguments work too.
abspath() { case "$1" in ""|/*) echo "$1" ;; *) echo "$FPGA_WORK/$1" ;; esac; }
SRC=$(abspath "$SRC"); XSA=$(abspath "$XSA")

if [ -z "$XSA" ] && ! ls "$PROJ"/*.xsa >/dev/null 2>&1; then
    die "no .xsa in $PROJ
In Vivado: Generate Bitstream, then File > Export > Export Hardware...,
tick 'Include bitstream', and save it into the project directory."
fi

# Give the project one canonical source file, so "where do I edit my C?" has a
# single answer that both this script and run-sw.sh agree on. Templates that
# ship their own program get no main.c — there would be nothing to put in it.
if [ "$TEMPLATE" = hello_world ] && [ -z "$SRC" ] && [ ! -f "$PROJ/src/main.c" ]; then
    mkdir -p "$PROJ/src"
    cat > "$PROJ/src/main.c" <<'STARTER'
#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"

int main(void)
{
    init_platform();

    xil_printf("\r\nHello from the MicroBlaze!\r\n");

    for (int n = 1;; n++) {
        for (volatile long i = 0; i < 3000000; i++) { }   /* crude delay */
        xil_printf("tick %d\r\n", n);
    }

    cleanup_platform();
    return 0;
}
STARTER
    info "created $PROJ/src/main.c — edit this file; it is the one that gets compiled"
fi
if [ "$TEMPLATE" = hello_world ] && [ -z "$SRC" ] && [ -f "$PROJ/src/main.c" ]; then
    SRC="$PROJ/src/main.c"
fi

require_docker
step "Creating the Vitis platform and app (slow the first time)"
docker exec \
    -e PROJ="$(in_container "$PROJ")" \
    -e APP="$APP" \
    -e CPU="$CPU" \
    -e TEMPLATE="$TEMPLATE" \
    ${OPT:+-e OPT="$OPT"} \
    ${DEBUG:+-e DEBUG="$DEBUG"} \
    ${SRC:+-e SRC="$(in_container "$SRC")"} \
    ${XSA:+-e XSA="$(in_container "$XSA")"} \
    -w "$(in_container "$PROJ")" "$CONTAINER" bash -lc \
    "source $XILINX/Vitis/settings64.sh && vitis -s $(in_container "$FPGA_WORK/tools/make-app.py")"

APP_ARG=""
if [ "$APP" != hello ]; then APP_ARG=" -a $APP"; fi

if [ "$TEMPLATE" = hello_world ]; then
cat <<EOF

Next:
  1. edit your C at $PROJ/src/main.c (any editor on the Mac)
  2. ./tools/run-sw.sh -d ${DIR}${APP_ARG}      # rebuild, bake in, flash
  3. screen /dev/cu.usbserial-*1 9600           # watch it print
EOF
else
cat <<EOF

Next ($TEMPLATE supplies its own sources — there is no main.c to edit):
  1. ./tools/run-sw.sh -d ${DIR}${APP_ARG}      # bake in, flash
  2. screen /dev/cu.usbserial-*1 9600           # watch it print
EOF
fi
