# Test 07 — ILA and VIO (on-chip debug)

**Status: ✅ PASS** (2026-09-08) — ILA *and* VIO both work over the XVC bridge.
This was the suite's biggest open question.

- **ILA**: 1024 samples captured, the counter incrementing by exactly 1 each
  sample (`8b1d1644` → `8b1d1a43`, no gaps), plus the switch probe.
- **VIO**: read the switches live (`0000`, then `1001` once they were flipped)
  and drove `probe_out0` to `101`, confirmed on LD4/LD6.

| | |
|---|---|
| Proves | Vivado's on-chip debug cores work through the XVC bridge |
| Needs | Container running, board on USB; Vivado GUI, or `ila-check.tcl` headless |
| Depends on | 05 (working bridge) |
| Time | ~10 min build, then interactive |

## What it tests

Two debug cores compiled into the design:

- **ILA** (Integrated Logic Analyzer) — records internal signals into on-chip
  memory and plays them back as a waveform in Hardware Manager. This is how
  you see inside a running design. **openFPGALoader cannot do this at all**;
  it's the main reason the XVC bridge exists.
- **VIO** (Virtual Input/Output) — virtual buttons and lights: read signals
  live, and drive values into the design from the GUI.

If a lab ever says "capture the bus with an ILA and show the waveform," this
is the capability it needs.

### Why it works when test 06 doesn't

Both go over the same bridge, but ILA and VIO use a different scan chain and
differently shaped transactions — mostly bulk reads of a capture buffer rather
than interactive CPU control. The bridge handles those fine. Only the debug
module's traffic fails.

### The heartbeat

`led[3]` (LD7) is driven straight from the counter, not from the VIO. It
separates two failures that would otherwise look the same:

| LD7 | VIO LEDs | Meaning |
|---|---|---|
| blinking | respond | everything works |
| blinking | dead | design is running, VIO is broken |
| dead | dead | the design never loaded — a plain programming failure, nothing to do with debug cores |

## How to run it (human)

```sh
cd ~/…/fpga-work/tests/07-ila-vio
./run.sh
```

The script builds, programs, checks the heartbeat, then starts the bridge and
waits. With it running, in the **Vivado GUI inside the container**:

1. Flow → Open Hardware Manager
2. Open Target → Open New Target → Next
3. Local server → Next. A device `xc7a100t_0` should appear.
4. If probes aren't loaded automatically, point the probes file at
   `ila_vio.ltx` in this directory.
5. In the `hw_ila_1` window press **▶ Run trigger immediate**. A waveform of
   the 32-bit counter incrementing should appear.
6. In the `hw_vio_1` window: flip a physical switch and watch `probe_in0`
   follow it; type a value into `probe_out0` and watch LD4–LD6 change.

Press Enter in the terminal when done, and answer honestly — a partial result
(ILA works, VIO doesn't, or vice versa) is a genuinely useful finding.

If Hardware Manager says "No devices detected", **retry** — the first
`open_hw_target` frequently fails even though the bridge logged the
connection. Clear stale servers first if it persists:
`docker exec vivado pkill -x hw_server`.

## How to run it (agent)

```sh
./run.sh -y      # builds, programs, stops before the GUI part
```

Machine-checkable from `run.sh`:

- `BUILD OK: …ila_vio.bit + ila_vio.ltx` — the `.ltx` matters; its absence
  means the debug cores weren't inserted
- openFPGALoader exits 0

**A successful build is not a pass.** To actually exercise the cores without a
GUI, run `ila-check.tcl` in this directory with the bridge up: it retries
`open_hw_target`, fires the ILA with `run_hw_ila -trigger_now`, writes the
capture to `ila_capture.csv`, and reads/drives the VIO probes. That is how the
2026-09-08 result was verified by machine rather than by eye.

Two API details worth knowing before editing it:

- VIO probes are named in the `.ltx` after **the nets they're wired to**
  (`sw_IBUF`, `vio_led`), not the IP port names — `get_hw_probes probe_in0`
  silently matches nothing.
- `DIRECTION` is not a valid property on a `hw_probe`, so probes can't be
  classified that way.

## Pass criteria

The ILA captures and displays a waveform of the counter, and the VIO both
reads the switches and drives the LEDs.

## If it fails

| Symptom | Cause |
|---|---|
| No `.ltx` produced | Debug cores weren't inserted — check `create_ip` succeeded in the build log |
| Hardware Manager: "No devices detected" | Usually just the first attempt — retry. If it persists, stale `hw_server`: `docker exec vivado pkill -x hw_server`, then reopen |
| Device appears, no debug cores listed | Probes file not loaded — set it manually to `ila_vio.ltx` |
| ILA never triggers | Use "Run trigger immediate" rather than waiting on a condition |
| Waveform is garbage or the GUI hangs | Same class of bug as test 06 — record it, it's a real finding |
| LD7 not blinking | The design isn't running; this is a programming problem, not a debug-core problem |
