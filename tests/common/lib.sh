# lib.sh — shared helpers for the test suite. Sourced by each test's run.sh.
#
# Everything that compiles runs inside the `vivado` container; everything that
# touches the USB cable runs here on macOS. These helpers hide that split.

set -euo pipefail

CONTAINER=vivado
CONTAINER_ROOT=/home/user/fpga-work
XILINX=/opt/Xilinx/2026.1
BOARD=arty_a7_100t                      # openFPGALoader board name
PART=xc7a100tcsg324-1
BOARD_PART=digilentinc.com:arty-a7-100:part0:1.1

# This file lives at fpga-work/tests/common/lib.sh
FPGA_WORK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS="$FPGA_WORK/tests"

# --- output -------------------------------------------------------------
step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
info() { printf '    %s\n' "$1"; }
ok()   { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1" >&2; exit 1; }
die()  { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# Ask the human to confirm something only eyes can confirm (LEDs, waveforms).
# Agents: pass -y / set AUTO_YES=1 to skip these and report them as unverified.
AUTO_YES=${AUTO_YES:-0}
confirm() {
    if [ "$AUTO_YES" = 1 ]; then
        printf '\033[33mSKIP\033[0m  (unattended) %s\n' "$1"
        return 0
    fi
    printf '\n\033[1m%s\033[0m [y/N] ' "$1"
    read -r reply </dev/tty
    case "$reply" in [yY]*) ok "$1" ;; *) fail "$1" ;; esac
}

# --- container ----------------------------------------------------------
# Host path -> container path. The same tree is mounted at CONTAINER_ROOT.
in_container() { echo "$CONTAINER_ROOT${1#"$FPGA_WORK"}"; }

require_docker() {
    docker info >/dev/null 2>&1 || die "Docker isn't running (open -a Docker)"
    docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" \
        || die "container '$CONTAINER' isn't up — run: cd ~/Containers/vivado-vitis && docker compose up -d"
}

require_board() {
    command -v openFPGALoader >/dev/null || die "openFPGALoader not installed (brew install openfpgaloader)"
    openFPGALoader --detect >/dev/null 2>&1 \
        || die "no board detected — check the USB cable (data, not charge-only) and that nothing else holds the port (screen, an --xvc bridge)"
}

# Run a Vivado batch script; $1 = directory holding it, $2 = script name.
vivado_batch() {
    local dir=$1 tcl=$2
    require_docker
    docker exec -w "$(in_container "$dir")" "$CONTAINER" bash -lc \
        "source $XILINX/Vivado/settings64.sh && vivado -mode batch -notrace -source $tcl -log vivado.log -journal vivado.jou"
}

# Run a Vitis python script (XSCT is disabled in 2026.1; -s takes python).
vitis_batch() {
    local dir=$1 py=$2
    require_docker
    docker exec -w "$(in_container "$dir")" "$CONTAINER" bash -lc \
        "source $XILINX/Vitis/settings64.sh && vitis -s $py"
}

# Run an xsdb script inside the container (used by the XVC tests).
xsdb_batch() {
    local dir=$1 tcl=$2
    require_docker
    docker exec -w "$(in_container "$dir")" "$CONTAINER" bash -lc \
        "source $XILINX/Vitis/settings64.sh && xsdb $tcl"
}

# Merge an ELF into a bitstream's BRAM initialisation, so the program runs as
# soon as the FPGA configures. This replaces Vitis "Run on Hardware", which
# cannot work over the XVC bridge (see 06-mb-debug).
#   bake_elf <impl_dir> <app.elf> <out.bit>
bake_elf() {
    local impl=$1 elf=$2 out=$3
    local bit="$impl/system_wrapper.bit" mmi="$impl/system_wrapper.mmi"
    [ -f "$bit" ] || die "no bitstream at $bit — build the hardware first"
    [ -f "$mmi" ] || die "no $mmi — this design has no BRAM memory map, so there is nothing to bake an ELF into"
    [ -f "$elf" ] || die "no ELF at $elf — build the application first"
    # Read the CPU instance out of the memory map instead of hardcoding it, so
    # this keeps working on designs with differently-named processors.
    local proc
    proc=$(grep -o 'InstPath="[^"]*"' "$mmi" | head -1 | cut -d'"' -f2)
    [ -n "$proc" ] || die "couldn't find a processor InstPath in $mmi"
    require_docker
    docker exec -w "$(in_container "$(dirname "$out")")" "$CONTAINER" bash -lc \
        "source $XILINX/Vivado/settings64.sh && updatemem -force \
           -meminfo '$(in_container "$mmi")' -data '$(in_container "$elf")' \
           -bit '$(in_container "$bit")' -proc '$proc' -out '$(in_container "$out")'"
    [ -f "$out" ] || die "updatemem did not produce $out"
    info "baked $(basename "$elf") into $(basename "$out")  (cpu: $proc)"
}

program() {
    local bit=$1
    [ -f "$bit" ] || die "no bitstream at $bit — build the test first"
    require_board
    openFPGALoader -b "$BOARD" "$bit"
}

# --- XVC bridge ---------------------------------------------------------
# openFPGALoader's XVC server defaults to port 3721; Xilinx tools expect 2542.
# It also quits when its stdin reaches EOF, hence the sleep holding stdin open.
XVC_PORT=2542
XVC_PIDFILE=/tmp/xvc-bridge.pid

xvc_start() {
    require_board
    xvc_stop
    step "Starting the XVC bridge on port $XVC_PORT"
    sleep 999999 | openFPGALoader -b "$BOARD" --xvc --port "$XVC_PORT" \
        >/tmp/xvc-bridge.log 2>&1 &
    echo $! >"$XVC_PIDFILE"
    sleep 2
    kill -0 "$(cat "$XVC_PIDFILE")" 2>/dev/null \
        || { cat /tmp/xvc-bridge.log; die "bridge died on startup (see /tmp/xvc-bridge.log)"; }
    info "bridge up (pid $(cat "$XVC_PIDFILE")), log: /tmp/xvc-bridge.log"
}

xvc_stop() {
    [ -f "$XVC_PIDFILE" ] || return 0
    kill "$(cat "$XVC_PIDFILE")" 2>/dev/null || true
    rm -f "$XVC_PIDFILE"
    # Stale in-container servers make later sessions report "no devices"
    docker exec "$CONTAINER" pkill -x hw_server  2>/dev/null || true
    docker exec "$CONTAINER" pkill -x cs_server  2>/dev/null || true
}
