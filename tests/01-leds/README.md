# Test 01 — Switches to LEDs

**Status: ✅ pass** (2026-09-08) — built, programmed, all four switch→LED pairs confirmed on hardware.

| | |
|---|---|
| Proves | Vivado can synthesize, implement and generate a bitstream; openFPGALoader can program the board; the board's I/O responds |
| Needs | Container running, board on USB |
| Depends on | nothing — this is the baseline |
| Time | a few minutes to build, seconds to program |

## What it tests

The whole basic path, end to end, with the simplest design that can possibly
work: `assign led = sw;` — four switches, four LEDs, no clock, no reset, no
IP cores. Because the design cannot really be wrong, a failure here points at
the toolchain, the license, the cable, or the board — never at your Verilog.

Run this first. Every other test assumes this one passes, and several of them
reuse `leds.bit`.

## How to run it (human)

```sh
cd ~/…/fpga-work/tests/01-leds
./run.sh
```

Then flip the four slide switches along the bottom edge of the board. Each
one should light the green LED directly above it — SW0 → LD4, SW1 → LD5,
SW2 → LD6, SW3 → LD7 — and affect no other LED. Answer `y` when asked.

To build without programming: `./run.sh` needs the board, so if you only want
the bitstream, run the build step alone:

```sh
docker exec -w /home/user/fpga-work/tests/01-leds vivado bash -lc \
  'source /opt/Xilinx/2026.1/Vivado/settings64.sh && vivado -mode batch -source build.tcl'
```

## How to run it (agent)

```sh
./run.sh -y      # builds and programs, skips the visual confirmation
```

`-y` (or `AUTO_YES=1`) suppresses the interactive prompt, so the script exits
0 after programming succeeds. **That is not a pass** — it only shows the
build and download worked. The LED behaviour is unverifiable without human
eyes; report it as unverified and ask the user to confirm.

Machine-checkable signals:

- `build.tcl` prints `BUILD OK: <path>` on success and calls `error` otherwise
- `leds.bit` exists and is ~3.8 MB
- openFPGALoader exits 0 and its status output shows `Done 1`

A `Done 0` with `ID Error` means the bitstream was built for a different FPGA
than the one on the cable.

## Pass criteria

Each switch controls its own LED, independently, with no others lit.

## If it fails

| Symptom | Cause |
|---|---|
| `no board detected` | USB cable is charge-only, or `screen`/an XVC bridge is holding the port |
| Build fails on `board_part` | Digilent board files aren't installed in the container (README §5) |
| `ID Error`, `Done 0` | Wrong-part bitstream — check the part is `xc7a100tcsg324-1` |
| Programs fine, LEDs dead | Board was power-cycled after programming; SRAM config is volatile, reprogram |
| LEDs stuck on a fixed pattern | You're seeing the QSPI factory demo, not this design — reprogram |
