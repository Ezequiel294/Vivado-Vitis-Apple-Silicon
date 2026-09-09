# Test 02 — Simulation (testbench + waveform)

**Status: ✅ pass** (2026-09-08) — 512/512 vectors, 0 mismatches, 11s.

| | |
|---|---|
| Proves | Vivado's simulator (xsim) works under emulation; testbenches run and waveforms can be produced |
| Needs | Container running. **No board.** |
| Depends on | nothing |
| Time | under a minute |

## What it tests

Simulation is how most coursework gets verified before it ever reaches
hardware, and it's the fallback whenever an on-board debug feature is
unavailable — so it matters that it works here. This test runs a 4-bit
ripple-carry adder against a self-checking testbench that sweeps **all 512
input combinations** and compares each result against Verilog's own
arithmetic.

It's self-checking on purpose: the testbench prints `TEST PASS` or
`TEST FAIL`, so no one has to interpret a waveform to know whether the
simulator is working correctly.

This is the only test in the suite that runs without the board, which also
makes it the fastest way to confirm the container and license are healthy.

## How to run it (human)

```sh
cd ~/…/fpga-work/tests/02-simulation
./run.sh
```

Expected output:

```
CHECKED 512 vectors, 0 mismatches
TEST PASS
PASS  02-simulation: 512/512 vectors correct, simulator works
```

**To see the waveform** (this is the part that matters for coursework — most
labs want a screenshot of one): the run writes `adder4_tb.vcd`. Open it in
the Vivado GUI inside the container:

```
File → Open File… → tests/02-simulation/adder4_tb.vcd
```

Or build the same thing interactively: open Vivado, create a project with
`src/adder4.v` and `sim/adder4_tb.v` (the latter as a simulation source), set
`adder4_tb` as the simulation top, and click **Run Simulation → Run
Behavioral Simulation**. That's the flow the class slides use, and this test
existing proves it will work when you need it.

## How to run it (agent)

```sh
./run.sh          # fully non-interactive already; -y accepted but unnecessary
```

Fully machine-checkable — no human eyes needed anywhere:

- exit 0 and `TEST PASS` in stdout ⇒ pass
- `TEST FAIL` plus `MISMATCH …` lines ⇒ the simulator ran but computed wrong
  results (a genuine and surprising toolchain bug — report loudly)
- non-zero exit with no verdict ⇒ xsim didn't run at all (licensing, install,
  or emulation problem)

Do not "fix" a `TEST FAIL` by editing the testbench. The adder is known
correct; a mismatch means the tool is broken.

## Pass criteria

`CHECKED 512 vectors, 0 mismatches` followed by `TEST PASS`.

## If it fails

| Symptom | Cause |
|---|---|
| `xvlog: command not found` | Vivado settings not sourced / install incomplete |
| Licensing error | The node-locked licence didn't load — check hostname/MAC pinning (repo README §4) |
| Hangs for many minutes at ~100% CPU | Almost certainly cloud-evicted source files: the container gets `Input/output error` and `xvlog` spins instead of exiting. Re-read the files from macOS (`find . -type f -exec cat {} + > /dev/null`) — journal §17. Otherwise, a testbench that never hit `$finish` |
