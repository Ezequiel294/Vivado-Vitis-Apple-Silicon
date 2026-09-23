# Arty A7-100T test suite

Nine tests that between them exercise everything this environment can do —
Vivado, Vitis, the simulator, both programming paths, the serial console in
both directions, the on-chip debug cores, flash boot, and benchmarking.

The point is to **see with your own eyes** that each piece works, and to keep
an honest record of the one that doesn't (06, MicroBlaze debug) and the one
never tried (08, flash boot). Every test says what it proves, how to run it,
what passing looks like, and what to check when it fails.

All tests target the **Arty A7-100T** (`xc7a100tcsg324-1`). Nothing here is
written for the Spartan-7.

> **Reading this in the `vivado-vitis` repo?** These tests cannot run from
> there. Copy **`tests/` and `tools/`** into the `fpga-work` folder that
> `docker-compose.yml` mounts, then run them from that copy:
> `cp -R tests tools "/path/to/your/fpga-work/"`. The container cannot see the
> repo at all — only `fpga-work` is mounted — and `common/lib.sh` derives
> container paths by stripping the `fpga-work` root off host paths, so from
> anywhere else every `docker exec` targets a path that does not exist.

## Status

Whole suite run 2026-09-08 on an Arty A7-100T. Update this table when you run
them again.

| # | Test | Proves | Board? | Status |
|---|---|---|---|---|
| 01 | [leds](01-leds/) | build → bitstream → program → board I/O | yes | ✅ pass (2026-09-08, LEDs confirmed) |
| 02 | [simulation](02-simulation/) | xsim testbenches and waveforms | **no** | ✅ pass (2026-09-08, 11s, 512/512) |
| 03 | [mb-hello](03-mb-hello/) | MicroBlaze runs your C, prints over serial | yes | ✅ pass (2026-09-08, ticks 1-55 captured) |
| 04 | [serial-input](04-serial-input/) | typed characters reach the FPGA | yes | ✅ pass (2026-09-08, "hello world"→"HELLO WORLD") |
| 05 | [xvc-program](05-xvc-program/) | container-side tools can reach the board | yes | ✅ pass (2026-09-08, XVC PROGRAM OK) |
| 06 | [mb-debug](06-mb-debug/) | MicroBlaze interactive debug | yes | ✅ expected-fail reproduced (2026-09-08, oFL v1.1.1, 0/3) |
| 07 | [ila-vio](07-ila-vio/) | ILA/VIO on-chip debug | yes | ✅ **PASS** (2026-09-08) — ILA + VIO both work over XVC |
| 08 | [flash-boot](08-flash-boot/) | design survives a power cycle | yes | ⬜ not run — ⚠️ writes flash |
| 09 | [dhrystone](09-dhrystone/) | benchmarking: template app, `-O3`, 128 kB `updatemem` | yes | ✅ pass (2026-09-21, 50,403 Dhrystones/s) |

Legend: ⬜ not run · ✅ pass · ❌ fail · ⚠️ partial

Two rows need their status read carefully:

- **06 is *expected* to fail.** It's a regression test for a known
  limitation — MicroBlaze debug operations don't work through openFPGALoader's
  XVC bridge — kept so that we notice the day someone fixes it. Failure is the
  correct result; success means the limitation is gone and the docs need
  updating.
- **07 settled the suite's big open question: ILA and VIO both work.** The ILA
  captured 1024 samples of a counter incrementing by exactly 1 each sample,
  and the VIO read the switches live and drove the LEDs. So the bridge's
  problem in test 06 really is specific to the debug module, not to on-chip
  debug in general. It needed one thing Hardware Manager doesn't do by
  default: **retry `open_hw_target`**, which often fails the first time with
  "No devices detected". `07-ila-vio/ila-check.tcl` drives both cores
  headlessly, no GUI needed.

## Order

Run them in numerical order the first time. Later tests reuse earlier
outputs:

```
01 leds ──┬─→ 05 xvc-program ──→ 07 ila-vio
          └─→ 08 flash-boot
02 simulation   (independent, no board)
03 mb-hello ──┬─→ 04 serial-input (independent design, same serial setup)
          ├───→ 06 mb-debug
          └───→ 09 dhrystone    (independent design, much larger memory)
```

Tests 03 and 09 take 20+ minutes on the first run — the MicroBlaze block
designs are the slowest builds in the suite. Everything else is minutes.

## Running them

```sh
cd ~/…/fpga-work/tests
./run-all.sh              # every test in order, stopping at the first failure
./01-leds/run.sh          # or one at a time
```

Prerequisites for anything touching the board:

```sh
open -a Docker
cd ~/Containers/vivado-vitis && docker compose up -d
```

Plus the board on USB with a **data** cable, and nothing else holding the
serial port (`screen`) or the JTAG channel (a leftover XVC bridge).

## For agents

Each test's README has a "How to run it (agent)" section — read it before
running anything. General rules:

- **`-y` suppresses the human confirmation prompts. It does not make a test
  pass.** Exiting 0 under `-y` means "built and programmed", nothing more.
  Tests 03, 04 and 07 have documented ways to verify the real result by
  machine (serial capture, and `07-ila-vio/ila-check.tcl`); 01 and 08 can only
  be judged by eye. Report anything you did not actually observe as
  unverified.
- **Test 06's exit codes are inverted**: 0 = still broken (expected), 2 = it
  works now (update the docs), 1 = couldn't run.
- **Never run test 08 unattended.** It writes persistent flash and needs a
  jumper moved by hand. It refuses under `-y` by design.
- **Test 09 is fully machine-checkable but slow.** It is left out of
  `run-all.sh` for its runtime, not for any hazard: its result is a number
  read off the serial port, which `run.sh` checks itself. Run it on its own
  when you need it, and use `--no-hw` to skip the Vivado rebuild.
- **Don't edit a test to make it pass.** 02's adder is known correct and 06 is
  supposed to fail; a green result obtained by changing the test is worthless.
- Tests 05, 06 and 07 need the XVC bridge, which is single-client. `lib.sh`
  starts and stops it, including cleaning up stale in-container `hw_server`
  processes. Don't run two bridge tests at once.

## Layout

```
tests/
  common/lib.sh     shared helpers: container exec, programming, XVC bridge,
                    updatemem, pass/fail output
  run-all.sh        run everything in order
  NN-name/
    README.md       what it proves, how to run it, pass criteria, failure modes
    run.sh          the test itself
    build.tcl       Vivado batch build (where one is needed)
    src/            Verilog / C sources
```

Build outputs (`vivado/`, `vitis/`, `*.bit`, `*.xsa`) stay inside each test's
directory and can be deleted to force a rebuild.

## Related

- Repo `README.md` — environment setup, daily workflow, what works overall
- Repo `journal.md` — the debugging history behind these limitations:
  §13–16 (the day the board arrived), §17–19 (the day this suite first ran)
- `../tools/run-sw.sh` — the everyday build-and-flash loop for your own
  MicroBlaze projects (the same `updatemem` flow as test 03)
