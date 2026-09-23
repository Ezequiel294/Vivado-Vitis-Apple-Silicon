# Test 09 — Dhrystone benchmark

**Status: ✅ pass** (2026-09-21) — 50,403 Dhrystones/second, 0.2869 DMIPS/MHz,
`updatemem` confirmed working on a 128 kB local memory.

| | |
|---|---|
| Proves | A benchmark from the Vitis Examples library runs on the board with no IDE: template app, assignment-mandated compiler flags, a 128 kB local memory through `updatemem`, and a readable serial transcript |
| Needs | Container running, board on USB, nothing holding the serial port |
| Depends on | 03 (MicroBlaze + `updatemem`), 04 (serial) |
| Time | **20-30 minutes**, nearly all of it the Vivado build |
| Produces | `system_wrapper.xsa`, `vitis/dhry/build/dhry.elf`, `09-dhrystone-boot.bit`, `dhrystone.log`, `codesize.txt` |

## What it tests

The course teaches benchmarking through the Vitis IDE: pick Dhrystone from the
Examples library, set Build → Settings → Optimization to `-O3`, click Run,
read the numbers in TeraTerm. The IDE does not run in this environment
(journal §20), so every one of those steps has a headless equivalent, and this
test exercises all of them at once.

1. **The template.** `dhrystone` is one of 35 app templates the headless
   `vitis -s` client can instantiate. It brings `dhry_1.c`, `dhry_2.c` and
   `platform.c`, pulls the `xiltimer` BSP library in, and sets its own linker
   constraints (`stack 16k heap 16k`). The tooling must leave all of that
   alone — this is the first test of an app whose sources we do not own.
2. **The build settings.** `-O3` and no debug info, set through
   `set_app_config`, which is what the IDE's Build Settings page calls.
3. **`updatemem` at 128 kB.** Every other test in this suite bakes an ELF into
   a small local memory. Homework 2 fixes it at 128 kB, which means a much
   larger `.mmi` and many more BRAMs. Nothing else exercises that.
4. **The transcript.** Dhrystone ends its result lines with a bare `LF`, which
   stair-steps across a terminal. The course slides fix this by setting
   TeraTerm's "Receive new-line" to LF; `capture_serial` does the same job
   here, while writing the raw bytes to a log you can quote in a report.

### What it does not test

The JTAG debugger. Benchmarking needs none of it — Dhrystone prints and exits,
with no breakpoints, no stepping, no `dow`. Test 06 still owns that limitation.

### Why the hardware script has guards

Three mistakes in the block design produce a *plausible* result rather than an
obvious failure, so `build-hw.tcl` refuses to continue on any of them:

| Guard | What it prevents |
|---|---|
| AXI Timer present and address-mapped | An unmapped timer reads as a constant, and the score comes out absurd or infinite |
| Local memory is exactly 128K | Too small and the template refuses to instantiate, minutes later, with an error about `0x7800 bytes` |
| Processor clock is 100 MHz | `DMIPS/MHz` is computed by dividing by this, so a different clock gives a wrong number that still looks reasonable |

The `ext_reset_in` guard from test 03 is kept as well.

## How to run it (human)

```sh
cd ~/fpga-work/tests/09-dhrystone
./run.sh
```

Then wait. The Vivado step is 15-25 minutes and prints very little; the
`GUARDS OK` line right after it is the first sign the design is what the
homework asked for.

When the board is programmed, the benchmark starts on its own — there is
nothing to type, and no run count to enter. Expect several seconds of silence
(160000 iterations) and then a burst of output ending in:

```
Microseconds for one run through Dhrystone: 19.8400
Dhrystones per Second:                      50403.2096
DMIPS/Sec:                                  28.6871
DMIPS/MHz:                                  0.2869

The Dhrystone App has run successfully
```

Those are the figures from the 2026-09-21 run of this configuration. The
course slides report 37,764 Dhrystones/second and 0.2149 DMIPS/MHz for their
own build, so being in the same range is the sanity check — not matching them
exactly.

To watch it again, start a capture and press the board's **RESET** button:

```sh
../../tools/serial.sh -u "run successfully"
```

Use `serial.sh` rather than `screen` here: Dhrystone's result lines end in a
bare `LF`, which `screen` stair-steps across the terminal. The numbers are the
same either way, but `serial.sh` also leaves you a transcript to paste into a
report, as the test itself does in `dhrystone.log`.

### Details worth knowing

- **Serial is 9600 baud, on `/dev/cu.usbserial-*1`** — the `cu.` device, not
  `tty.`, and the port ending in `1` (channel B), not `0` (channel A, JTAG).
- **Re-running does not need the hardware rebuilt.** `./run.sh --no-hw` skips
  straight to the application.
- **Code size** lands in `codesize.txt` and in the build log, as the `text
  data bss dec hex` line. That is `mb-size` running as the last build step, and
  it is the figure Homework 2 asks you to collect.

## How to run it (agent)

```sh
AUTO_YES=1 ./run.sh
```

Machine-checkable, in order:

- `GUARDS OK: AXI Timer mapped, local memory 128 kB, clock 100.000 MHz`
- `BUILD OK: …system_wrapper.xsa`
- The template's sources survived: `vitis/dhry/src/{dhry_1.c,dhry_2.c,platform.c}`
  all exist and `vitis/dhry/src/main.c` does **not**
- `Build setting: USER_COMPILE_OPTIMIZATION_LEVEL = -O3` in `build.log`
- `09-dhrystone-boot.bit` exists and **differs** from
  `vivado/mb_dhry.runs/impl_1/system_wrapper.bit` — identical means
  `updatemem` silently did nothing, which at this memory size is exactly the
  failure this test exists to catch
- `dhrystone.log` contains `The Dhrystone App has run successfully` and a
  non-zero `Dhrystones per Second` value

`run.sh` checks all of these and exits non-zero on any of them. Do not infer
the result from a successful build — the benchmark number is the result.

## Pass criteria

The transcript contains `The Dhrystone App has run successfully` and a
non-zero `Dhrystones per Second`. The `Final values of the variables` block
that precedes it should match the `should be:` line under each entry; a
mismatch there means the benchmark computed the wrong answer and the timing is
meaningless regardless of what it reports.

## If it fails

| Symptom | Cause |
|---|---|
| `local memory is 0x00008000 (32 kB), expected 128 kB` | Block automation ran with the wrong `local_mem` — fix `build-hw.tcl`, do not weaken the guard |
| `no AXI Timer in the design` / `not mapped into the processor's address space` | The timer's AXI automation did not apply; check `TIMER_AXI_AUTOMATION` in `vivado.log` |
| Vitis: `requires at least 0x7800 bytes of any memory` | The platform was built from an older `.xsa` with a small memory. Delete `vitis/` and re-run |
| `a main.c was injected into a template app` | `make-app.sh` regressed — template apps must never receive the project's source |
| Bake step fails, or the boot bitstream equals the plain one | **`updatemem` could not handle the 128 kB memory.** This is the one genuinely unproven step; record the exact error in the journal before working around it |
| No completion message within 180s | Press RESET and re-run with `--no-hw`. If the log is empty, the CPU is held in reset; if it is garbage, the QSPI factory demo is running at a different baud — reprogram |
| `Dhrystones per Second` is 0 | The timer never advanced — it is present but not readable at `XPAR_XTMRCTR_0_BASEADDR` |
| A *slower* processor reports a *shorter* time | The 32-bit timer wrapped. At 100 MHz it wraps every 42.9 s and the code corrects for only one wrap. Lower `ITERATIONS`, or treat that configuration's timing as invalid |
| Result far below the published ~1.2 DMIPS/MHz | Expected. The course slides see this too and say so — no cache, no barrel shifter, and the slides note they will keep hunting for causes through the semester |

## Deriving the other configurations (Homework 2)

This test builds **configuration 3**: hardware multiplier *and* divider. The
homework wants three, differing only in those two options:

| | `C_USE_HW_MUL` | `C_USE_DIV` |
|---|---|---|
| 1. No multiplier or divider | `0` | `0` |
| 2. Hardware multiplier, no divider | `1` | `0` |
| 3. Hardware multiplier and divider | `1` | `1` |

Everything else is fixed by the assignment and already correct here: the
Microcontroller preset, 128 kB local memory, 100 MHz, MDM enabled, AXI Timer
present, and no barrel shifter, FPU or caches.

To produce the other two, copy this directory, edit the `set_property -dict`
block near the top of `build-hw.tcl`, and run it. Each one needs its own
Vivado build, so budget an afternoon.

Two things to expect when you analyse the results:

- **The times will be close.** Dhrystone is dominated by string operations,
  pointer chasing, comparisons and procedure calls — it barely multiplies and
  almost never divides. That is the answer to "how much did hardware
  multiplication and/or division help, and does that make sense?"
- **The code sizes will not be.** Without the hardware instructions the
  compiler links in soft-arithmetic routines (`__mulsi3`, `__divsi3`), so the
  `text` figure grows. Collect it from `codesize.txt` for each configuration.
