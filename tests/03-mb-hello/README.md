# Test 03 — MicroBlaze running a C program

**Status: ✅ pass** (2026-09-08) — hardware + Vitis app + updatemem; ticks 1-55 captured on the UART.

| | |
|---|---|
| Proves | A soft CPU can be built in Vivado, an application compiled in Vitis, and the two combined so your C code runs on the board and prints over serial |
| Needs | Container running, board on USB, a serial terminal |
| Depends on | 01 (baseline programming) |
| Time | **20+ minutes** the first time — the block design build is the slowest thing in the suite |
| Produces | `system_wrapper.xsa`, `vitis/hello/build/hello.elf`, `mb-hello-boot.bit` — reused by tests 04 and 06 |

## What it tests

This is the second half of the course: a CPU built out of FPGA logic, running
C you wrote. Three things have to work together, and the test proves all
three:

1. **Vivado** builds the hardware — MicroBlaze, 32KB of local memory, a UART,
   and the MDM debug module — and exports it as an `.xsa`.
2. **Vitis** compiles a C program against that hardware.
3. **`updatemem`** merges the compiled program into the bitstream's memory
   initialisation, so the CPU starts executing it the moment the FPGA
   configures.

### Why the extra merge step

A bitstream configures *hardware*. Your C program is a separate artifact that
lives in the CPU's BRAM, and a plain `system_wrapper.bit` comes up with that
memory empty — a running MicroBlaze executing nothing. Normally Vitis "Run on
Hardware" would load the program over JTAG, but that path is broken here
(test 06 documents exactly how). `updatemem` gets the same result by putting
the program *inside* the bitstream before it's ever downloaded.

Practical upside: the program runs at power-on and the RESET button restarts
it, with no debugger and no host connection involved.

## How to run it (human)

```sh
cd ~/…/fpga-work/tests/03-mb-hello
./run.sh
```

Open a second terminal **before** the script finishes:

```sh
screen /dev/cu.usbserial-*1 9600        # exit: Ctrl-A then K, then y
```

Press the board's **RESET** button, then look for:

```
=== TEST 03 MB-HELLO ===
MicroBlaze is alive and running your C code.
Counting once per second; press RESET to start over.
tick 1
tick 2
```

The ticks continuing is the important part — it distinguishes a running
program from one that printed once and hung.

To change the program, edit `src/main.c` and re-run `./run.sh`; it skips the
slow hardware build and only recompiles the software.

### Details worth knowing

- **Baud is 9600**, set explicitly in `build-hw.tcl`. The AXI UartLite
  automation defaults to 9600 while almost every tutorial says 115200, which
  produces pure garbage. If you'd rather have 115200, change
  `CONFIG.C_BAUDRATE` and rebuild the hardware — the serial command must
  match.
- Use `/dev/cu.usbserial-*1`, not `tty.` (which waits for a carrier signal
  and exits after a few seconds) and not `*0` (that's the JTAG channel).
- **`make-app.py` repoints `USER_COMPILE_SOURCES` at `main.c`.** The Vitis
  `hello_world` template pins its source list to `helloworld.c`; copy the
  script for your own app and keep that fix, or CMake will either fail or
  silently keep compiling the template (journal §18).

## How to run it (agent)

```sh
./run.sh -y
```

Machine-checkable:

- `BUILD OK: …system_wrapper.xsa` from the Vivado step
- `APP OK: …hello.elf` (first run) or a successful `build_app` rebuild — note
  `cmake` is not on PATH after `settings64.sh`; `lib.sh` locates it under
  `tps/` and adds the MicroBlaze toolchain dirs (journal §21)
- `mb-hello-boot.bit` exists and **differs** from
  `vivado/mb_hello.runs/impl_1/system_wrapper.bit` — if `cmp` reports them
  identical, `updatemem` silently did nothing and the CPU will run an empty
  memory
- openFPGALoader exits 0

The serial output *is* checkable without `screen` — read the port directly
(this is how the 2026-09-08 result was captured):

```sh
DEV=$(ls /dev/cu.usbserial-*1 | head -1)
stty -f "$DEV" 9600 cs8 -cstopb -parenb raw -echo
cat "$DEV" > /tmp/serial.txt & CATPID=$!; sleep 15; kill $CATPID
cat -v /tmp/serial.txt
```

Nothing else may hold the port while this runs. Never infer the serial result
from a successful download — capture it or report it unverified.

## Pass criteria

The banner appears on the serial console after a RESET press, and `tick N`
keeps incrementing.

## If it fails

| Symptom | Cause |
|---|---|
| Build error `ext_reset_in is unconnected` | The guard caught the reset bug — board automation didn't apply; do not remove the guard, fix the automation |
| Nothing on serial at all | Wrong device (`cu.` not `tty.`, `*1` not `*0`), or `screen` is on the wrong baud |
| Garbage characters | Baud mismatch — usually the QSPI factory demo at 115200 after a power cycle. Reprogram |
| Banner truncated, e.g. `d application` | The FT2232 drops UART bytes while JTAG is busy. Press RESET for a clean run |
| Banner appears, ticks never advance | CPU held in reset or hung — check the `ext_reset_in` connection in the block design |
| Vitis step fails on a `create_*` call | The workspace half-exists. Delete `vitis/` and re-run |
