# Test 04 — Serial input (keyboard to FPGA)

**Status: ✅ pass** (2026-09-08) — "hello world" → "HELLO WORLD" over the wire; sending 0x6A lit exactly LD7+LD5.

| | |
|---|---|
| Proves | Characters typed on the Mac reach the FPGA and are processed by it — the UART *receive* direction |
| Needs | Container running, board on USB, a serial terminal |
| Depends on | 01 (baseline programming) |
| Time | a few minutes to build |

## What it tests

Test 03 proves the board can *send* serial data. This proves it can
**receive** — the direction nothing in this setup had ever exercised, and the
one a project needs if it takes commands, reads a menu, or accepts input of
any kind.

It's written as plain Verilog (its own UART receiver and transmitter, no
MicroBlaze, no Vitis) for two reasons: it builds in minutes instead of
twenty, and it tests the physical RX path directly rather than through a
soft CPU and an IP core. If this passes, MicroBlaze input works too — same
pins, same signals, just an IP block on top.

**The echo is not a loopback.** Lowercase letters come back uppercase. A
plain mirror could be produced by the cable, the FTDI chip, or a terminal
setting; case conversion can only have happened inside the FPGA. The LEDs
showing the low four bits of the last byte are a second, independent
witness.

## How to run it (human)

```sh
cd ~/…/fpga-work/tests/04-serial-input
./run.sh
```

Then, in another terminal:

```sh
screen /dev/cu.usbserial-*1 9600        # exit: Ctrl-A then K, then y
```

Type `hello world`. You should see `HELLO WORLD` come back, and the LEDs
should flicker as each character arrives.

If you type and see *nothing*, that's the interesting failure — it means
input isn't reaching the design. Check the LEDs before blaming the echo: if
they move, RX works and the problem is on the transmit side.

## How to run it (agent)

```sh
./run.sh -y      # builds and programs only
```

Machine-checkable:

- `BUILD OK: …uart_echo.bit`
- openFPGALoader exits 0

**The echo *is* machine-checkable** — no `screen`, no pyserial. This is the
exact round trip that produced the 2026-09-08 result; nothing else may hold
the port while it runs:

```sh
DEV=$(ls /dev/cu.usbserial-*1 | head -1)
stty -f "$DEV" 9600 cs8 -cstopb -parenb raw -echo
exec 3<>"$DEV"
cat <&3 > /tmp/echo04.txt & CATPID=$!
sleep 1; printf 'hello world' >&3; sleep 3
kill $CATPID; exec 3>&-
cat -v /tmp/echo04.txt          # expect: HELLO WORLD
```

To check the LED half in the same way, send a single byte with a known low
nibble and look at LD7–LD4 — e.g. `printf 'j' >&3` (`0x6A`, low nibble
`1010`) should light LD7 and LD5 only.

## Pass criteria

Typed lowercase letters return uppercase, and the LEDs change as bytes
arrive.

## If it fails

| Symptom | Cause |
|---|---|
| Nothing comes back, LEDs still | RX not reaching the FPGA — wrong device (`*1`, not `*0`), or wrong baud |
| LEDs move, no characters return | RX works, TX doesn't — the transmit half of the design, or `screen` isn't showing local output |
| Characters come back *unchanged* | You may be seeing a terminal-level echo rather than the FPGA's. Turn off local echo, or check the LEDs |
| Garbage in both directions | Baud mismatch. This design is fixed at 9600 (`CLKS_PER_BIT = 10417`) |
| Every character doubles | Local echo in `screen` plus the FPGA's echo. Harmless |
