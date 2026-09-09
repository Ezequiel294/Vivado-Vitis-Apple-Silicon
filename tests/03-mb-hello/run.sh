#!/usr/bin/env bash
# Test 03 — MicroBlaze soft CPU running a C program, printing over serial.
source "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "${1:-}" = "-y" ] && AUTO_YES=1

IMPL="$HERE/vivado/mb_hello.runs/impl_1"
APP="$HERE/vitis/hello"
BOOT="$HERE/mb-hello-boot.bit"

# --- 1. hardware --------------------------------------------------------
if [ ! -f "$HERE/system_wrapper.xsa" ]; then
    step "Building the MicroBlaze platform (SLOW — 20+ min under emulation)"
    vivado_batch "$HERE" build-hw.tcl
else
    info "hardware already built (delete system_wrapper.xsa to force a rebuild)"
fi

# --- 2. software --------------------------------------------------------
if [ ! -d "$APP" ]; then
    step "Creating the Vitis platform and application (slow)"
    vitis_batch "$HERE" make-app.py
else
    step "Rebuilding the application"
    cp "$HERE/src/main.c" "$APP/src/main.c"
    require_docker
    docker exec "$CONTAINER" bash -lc \
        "source $XILINX/Vitis/settings64.sh && cmake --build '$(in_container "$APP/build")'"
fi
[ -f "$APP/build/hello.elf" ] || fail "03-mb-hello: no ELF produced"

# --- 3. merge and program ----------------------------------------------
step "Baking the program into the bitstream"
bake_elf "$IMPL" "$APP/build/hello.elf" "$BOOT"

step "Programming the board"
program "$BOOT"

# --- 4. check -----------------------------------------------------------
step "Check the serial console"
cat <<'EOF'
    In another terminal:

        screen /dev/cu.usbserial-*1 9600      (exit: Ctrl-A then K, then y)

    Press the board's RESET button (the one labelled RESET, next to the
    USB connector) to re-run the program cleanly, then look for:

        === TEST 03 MB-HELLO ===
        MicroBlaze is alive and running your C code.
        tick 1
        tick 2   ...

    Output printed while JTAG was still busy can arrive truncated — that is
    why you press RESET rather than trusting the first burst.
EOF
confirm "03-mb-hello: does the banner appear and do the ticks keep counting?"
