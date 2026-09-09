# Test 08 — Boot from flash (survives a power cycle)

**Status: ⬜ not run.** Deliberately skipped in the 2026-09-08 suite run —
it needs a jumper fitted and a power cycle by hand.

⚠️ **This is the only test that changes the board permanently.** It writes to
non-volatile QSPI flash and moves a jumper. Everything else in this suite
disappears the moment the board loses power; this doesn't, until you erase it.

| | |
|---|---|
| Proves | A design can be stored in flash and boot with no computer attached |
| Needs | Board on USB, a hand free for the jumper |
| Depends on | 01 (uses `01-leds/leds.bit`) |
| Time | a few minutes |

## What it tests

Normally the Arty's configuration lives in SRAM: program it, pull the power,
and it's gone — which is why you reprogram after every power cycle. The board
also has a 16MB QSPI flash chip that it can configure itself from at
power-up.

This matters for a final project that has to be demonstrated standalone —
plugged into a wall adapter or a battery, with no laptop. It's also the
mechanism behind the Digilent factory demo you saw when the board first
arrived, and knowing how to overwrite (and restore) it is useful.

## The JP1 jumper

The **MODE** jumper (JP1) decides whether the FPGA configures itself from
flash at power-up:

| JP1 | Behaviour |
|---|---|
| shunt fitted | boots from QSPI flash at power-on |
| open | ignores the flash, waits for JTAG |

Leaving JP1 open is genuinely useful while developing — it stops a stale
flash image from confusing you about what's running. See the
[Arty A7 reference manual](https://digilent.com/reference/programmable-logic/arty-a7/reference-manual).

## How to run it (human)

```sh
cd ~/…/fpga-work/tests/08-flash-boot
./run.sh
```

The script walks you through it: fit the JP1 shunt, write the flash (slower
than a normal download — it's erasing and programming a flash chip), then
**unplug the USB cable and plug it back in**. The switch/LED design should
come up on its own, with nothing programmed over JTAG.

That last step is the whole test. Resist the urge to reprogram.

### Undoing it

```sh
openFPGALoader -b arty_a7_100t --bulk-erase     # wipe the flash
```

Or just remove the JP1 shunt, and the board goes back to waiting for JTAG.
Note that erasing also removes the Digilent factory demo permanently — no
great loss, but it won't come back by itself.

## How to run it (agent)

```sh
./run.sh -y      # exits 0 immediately without doing anything
```

**Do not run this unattended.** It requires a physical jumper change and a
physical power cycle, neither of which can be automated, and it writes
persistent state to the user's hardware. With `-y` the script deliberately
skips rather than half-completing — writing flash while JP1 is open leaves
the board in a state the user didn't ask for.

If asked to verify flash boot, explain that it needs hands on the board and
let the user drive.

## Pass criteria

After a full power cycle with no JTAG programming, the switches drive the
LEDs.

## If it fails

| Symptom | Cause |
|---|---|
| `openFPGALoader -f` errors on the flash | Wrong board argument, or something else holds the FTDI port |
| Flash writes, board dead after power cycle | JP1 shunt not fitted, or not seated |
| Old design still boots | Flash write didn't take — re-run, then `--bulk-erase` and try again |
| Board boots the factory demo | You erased/overwrote a different region; re-run the write |
| Works, but you can't program over JTAG any more | Unlikely — JTAG has priority. Remove JP1 and retry |
