#!/usr/bin/env bash
#
# run-sw.sh — rebuild a Vitis app, bake the ELF into the bitstream, program the board.
#
# The everyday loop for your own MicroBlaze coursework. Replaces Vitis "Run on
# Hardware", which cannot work through the XVC bridge (see tests/06-mb-debug).
# The ELF is merged into the bitstream's BRAM instead, so the program starts as
# soon as the FPGA configures and the RESET button re-runs it.
#
# Compilation happens inside the `vivado` container; programming happens here
# on macOS, where the USB cable is.
#
#   ./tools/run-sw.sh -d tests/03-mb-hello        # the worked example
#   ./tools/run-sw.sh -d projects/unit5 -a lab3   # your own project
#   ./tools/run-sw.sh -d … --no-build             # ELF is current: merge + flash
#   ./tools/run-sw.sh -d … --no-program           # produce the .bit, don't touch the board
#
# Layout it expects inside the project directory:
#   <dir>/vivado/*.runs/impl_1/system_wrapper.{bit,mmi}
#   <dir>/vitis/<app>/build/<app>.elf
#   <dir>/src/main.c            (optional; copied over the app's source)
#
source "$(dirname "${BASH_SOURCE[0]}")/../tests/common/lib.sh"

DIR=""
APP=hello
WORKSPACE=vitis
VIVADO_PROJ=vivado
DO_BUILD=1
DO_PROGRAM=1

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--dir)       DIR=$2;         shift 2 ;;
        -a|--app)       APP=$2;         shift 2 ;;
        -w|--workspace) WORKSPACE=$2;   shift 2 ;;
        -v|--vivado)    VIVADO_PROJ=$2; shift 2 ;;
        --no-build)     DO_BUILD=0;     shift ;;
        --no-program)   DO_PROGRAM=0;   shift ;;
        -h|--help)      awk 'NR>2 && !/^#/ {exit} NR>2 {sub(/^# ?/,""); print}' "$0"; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

[ -n "$DIR" ] || die "which project? pass -d <dir> (try --help)"
# Accept either an absolute path or one relative to fpga-work.
case "$DIR" in /*) PROJ_DIR=$DIR ;; *) PROJ_DIR="$FPGA_WORK/$DIR" ;; esac
[ -d "$PROJ_DIR" ] || die "no such directory: $PROJ_DIR"

APP_DIR="$PROJ_DIR/$WORKSPACE/$APP"
IMPL=$(echo "$PROJ_DIR/$VIVADO_PROJ"/*.runs/impl_1)
BOOT="$PROJ_DIR/$(basename "$PROJ_DIR")-boot.bit"

# --- 1. rebuild the ELF --------------------------------------------------
if [ "$DO_BUILD" = 1 ]; then
    step "Building $APP"
    [ -d "$APP_DIR/build" ] || die "no build tree at $APP_DIR/build
(first time? create the app with: vitis -s <your make-app.py>)"
    [ -f "$PROJ_DIR/src/main.c" ] && cp "$PROJ_DIR/src/main.c" "$APP_DIR/src/main.c"
    require_docker
    docker exec "$CONTAINER" bash -lc \
        "source $XILINX/Vitis/settings64.sh && cmake --build '$(in_container "$APP_DIR/build")'"
fi

# --- 2. merge ------------------------------------------------------------
step "Baking $APP.elf into the bitstream"
bake_elf "$IMPL" "$APP_DIR/build/$APP.elf" "$BOOT"

# --- 3. program ----------------------------------------------------------
if [ "$DO_PROGRAM" = 1 ]; then
    step "Programming the board"
    program "$BOOT"
    cat <<EOF

Done — the program is running.
  serial:  screen /dev/cu.usbserial-*1 9600     (exit: Ctrl-A then K, then y)
  re-run:  press the board's RESET button
EOF
fi
