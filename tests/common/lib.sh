# lib.sh — shared helpers for the test suite. Sourced by each test's run.sh.
#
# Everything that compiles runs inside the `vivado` container; everything that
# touches the USB cable runs here on macOS. These helpers hide that split.
#
# This is a library for SCRIPTS, not for your interactive shell. Sourcing it at
# a prompt arms `set -euo pipefail` in that shell, so the next command that
# returns non-zero closes your terminal. To watch the serial port by hand, run
# `tools/serial.sh` instead.

if [ -z "${BASH_VERSION:-}" ]; then
    echo "lib.sh needs bash (it uses BASH_SOURCE and bash's set -o pipefail)." >&2
    echo "Your shell is ${SHELL:-not bash}. To watch the serial port, run:" >&2
    echo "    ./tools/serial.sh" >&2
    return 1 2>/dev/null || exit 1
fi

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
    # Don't assume the wrapper is called system_wrapper: a block design made in
    # the Vivado GUI is named after the design (design_1_wrapper, etc). Find
    # the memory map, then take the matching bitstream.
    local mmi bit
    mmi=$(ls "$impl"/*.mmi 2>/dev/null | head -1)
    [ -n "$mmi" ] || die "no .mmi in $impl — either the hardware isn't implemented yet, or this design has no MicroBlaze BRAM to bake an ELF into"
    bit="${mmi%.mmi}.bit"
    [ -f "$bit" ] || die "found $(basename "$mmi") but no matching $(basename "$bit") — generate the bitstream first"
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

# Rebuild a Vitis application's generated build tree.
# Vitis emits a CMake/Ninja tree, but settings64.sh puts neither cmake nor a
# usable make on PATH: cmake lives under tps/ (matched by glob so a toolchain
# version bump doesn't break this) and ninja ships in Vitis/bin. Plain `make`
# cannot build this tree at all — the generator is Ninja, not Unix Makefiles.
#   build_app <build_dir>
build_app() {
    local build
    build=$(in_container "$1")
    require_docker
    docker exec "$CONTAINER" bash -lc '
        source '"$XILINX"'/Vitis/settings64.sh
        # The generated build calls mb-gcc by absolute path but mb-size and
        # friends by bare name, and they live in two different trees that
        # settings64.sh does not add to PATH.
        export PATH='"$XILINX"'/Vitis/gnu/microblaze/lin/bin:'"$XILINX"'/gnu/microblaze/lin/bin:$PATH
        CM=$(ls -d '"$XILINX"'/tps/lnx64/cmake-*/bin/cmake 2>/dev/null | head -1)
        if [ -n "$CM" ]; then
            exec "$CM" --build '"'$build'"'
        elif command -v ninja >/dev/null 2>&1; then
            exec ninja -C '"'$build'"'
        else
            echo "no cmake or ninja found in the Vitis install" >&2; exit 1
        fi'
}

program() {
    local bit=$1
    [ -f "$bit" ] || die "no bitstream at $bit — build the test first"
    require_board
    openFPGALoader -b "$BOARD" "$bit"
}

# --- serial -------------------------------------------------------------
# Channel B of the board's FT2232 is the UART; channel A is JTAG. Both live on
# one cable, and traffic on A costs bytes on B, so never capture while
# programming — program first, then capture.
SERIAL_BAUD=9600

serial_port() {
    local port
    port=$(ls /dev/cu.usbserial-*1 2>/dev/null | head -1)
    [ -n "$port" ] || die "no serial port — looked for /dev/cu.usbserial-*1 (channel B).
Is the board plugged in? Note it is cu.*, not tty.*, and the port ending in 1, not 0."
    echo "$port"
}

# capture_serial <logfile> [seconds] [stop-pattern]
#
# Reads the board's UART, writes exactly what it sent to <logfile>, and echoes
# a copy to the terminal with carriage returns added so output that ends its
# lines with a bare LF does not stair-step down the screen. This is the macOS
# equivalent of setting TeraTerm's "Receive new-line" to LF.
#
# With a stop-pattern: returns 0 as soon as it appears, 1 if the time runs out
# first. Without one: captures for the whole duration and returns 0.
# A duration of 0 means no time limit — run until the pattern appears, or
# until Ctrl-C.
#
# Read-only — it cannot send input. Use `screen` when the program expects you
# to type.
#
# Returns non-zero on timeout, so under `set -e` call it as a condition:
#   if capture_serial "$log" 60 "done"; then ... else ... fi
capture_serial() {
    local log=$1 secs=${2:-30} pattern=${3:-}
    local port; port=$(serial_port)
    : >"$log"
    stty -f "$port" "$SERIAL_BAUD" raw -echo 2>/dev/null \
        || die "could not configure $port — is screen or another reader holding it?"
    if [ "$secs" -gt 0 ]; then
        info "capturing $port at $SERIAL_BAUD for up to ${secs}s -> $log"
    else
        info "capturing $port at $SERIAL_BAUD -> $log   (Ctrl-C to stop)"
    fi
    perl -e '
        my ($port, $log, $secs, $pat) = @ARGV;
        open(my $fh,  "<", $port) or die "cannot read $port: $!\n";
        open(my $out, ">", $log)  or die "cannot write $log: $!\n";
        $| = 1; select((select($out), $| = 1)[0]);
        my $found = 0;
        my $tail  = "";
        eval {
            local $SIG{ALRM} = sub { die "timeout\n" };
            alarm $secs if $secs > 0;
            while (sysread($fh, my $buf, 256)) {
                print $out $buf;                        # raw, byte for byte
                (my $shown = $buf) =~ s/\r?\n/\r\n/g;   # legible on a terminal
                print STDOUT $shown;
                next if $pat eq "";
                $tail = substr($tail . $buf, -4096);
                if (index($tail, $pat) >= 0) { $found = 1; last; }
            }
            alarm 0;
        };
        exit(($pat eq "" || $found) ? 0 : 1);
    ' "$port" "$log" "$secs" "$pattern"
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
