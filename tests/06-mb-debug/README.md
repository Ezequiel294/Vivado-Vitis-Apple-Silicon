# Test 06 — MicroBlaze interactive debug (KNOWN BROKEN)

**Status: ✅ expected failure reproduced** (2026-09-08, openFPGALoader v1.1.1,
0/3 operations). This is a regression test for a limitation we already
understand — it exists so that the day someone fixes it, we find out.

| | |
|---|---|
| Proves | Whether the MicroBlaze Debug Module can be driven over the XVC bridge |
| Expected today | 0 of 3 debug operations succeed |
| Needs | Container running, board on USB |
| Depends on | 03 (boot bitstream + ELF), 05 (working bridge) |
| Time | about a minute |

## What it tests

Three JTAG operations against the MicroBlaze Debug Module (MDM):

| Operation | What it does | Needed for |
|---|---|---|
| `stop` | halt the CPU | any debugging at all |
| `dow` | download an ELF into memory over JTAG | Vitis "Run on Hardware" |
| `con` | resume execution | running after a download |

`stop` and `dow` fail with `Cannot stop MicroBlaze. MicroBlaze is not being
clocked` — while in the same session `con` fails with **`Already running`**.

**That error message is a lie**, and it's the single most important thing
recorded in this suite. The CPU *is* clocked and *is* running: test 03 has it
printing to the serial console at the same time this test claims it isn't, and
the contradictory `con` failure above proves the tool knows it. Hours went into
chasing a clocking bug that never existed. If you see this message, check for a
heartbeat (serial output, an LED) before believing it.

### Why "Run on Hardware" is affected, not just breakpoints

It's tempting to think only the live debugger is broken and that Vitis "Run
on Hardware" is really just "program the board". It isn't. Running a program
from Vitis is `stop` → `dow` → `con` — the debugger's download engine minus
the breakpoints. `dow` is exactly one of the calls that fails, so the ELF
never reaches memory. That's why test 03 uses `updatemem` instead: it puts
the program inside the bitstream, so no MDM traffic is needed at all.

The Vivado/Vitis GUI fails the same way. It sits on the identical
`hw_server → XVC → MDM` path; there is no GUI-only route around it.

### What we know about the cause

- Everything else over the same bridge works perfectly: enumeration, and
  `fpga -f` bitstream downloads (test 05). Only MDM traffic fails.
- It still fails with JTAG slowed to 1MHz, so it isn't a signal-integrity or
  timing problem.
- The likely cause is openFPGALoader's XVC server mishandling the longer
  BSCAN/USER2 shifts the debug module needs. AWS hit something similar:
  [aws/aws-fpga#641](https://github.com/aws/aws-fpga/issues/641).

This is a bug in one program, **not** a hardware limitation and not something
about Rosetta or Docker. It is very plausibly fixable.

## Untried fixes, cheapest first

1. **A newer openFPGALoader.** Homebrew ships v1.1.1. Upstream has moved on
   and the changelog has never been audited against this bug. `brew install
   --HEAD openfpgaloader`, then re-run this test — five minutes to a
   definitive answer.
2. **A different XVC server.** Independent implementations drive the FT2232
   directly; separate codebase, separate bugs.
3. **Native cable drivers in a Windows-on-ARM VM.** No XVC in the path, so it
   would certainly work. Expensive: paid VM, a second full toolchain install.

Docker Desktop on macOS cannot pass USB through to a container, so the
obvious fix — letting Vivado talk to the cable directly — isn't available.

## How to run it (human)

```sh
cd ~/…/fpga-work/tests/06-mb-debug
./run.sh
```

Expected output today:

```
RESULT connect OK
RESULT select-fpga OK
RESULT fpga-program OK
RESULT stop FAIL: Cannot stop MicroBlaze. MicroBlaze is not being clocked
RESULT dow  FAIL: …
RESULT con  FAIL: …
SUMMARY: MDM-DEBUG-STILL-BROKEN (0/3 debug operations worked)
PASS  06-mb-debug: still broken, exactly as documented (expected result)
```

The full transcript is saved to `last-run.log`.

## How to run it (agent)

```sh
./run.sh          # no -y needed, there is nothing for a human to look at
```

**Exit codes are inverted here.** Read them carefully:

| Exit | Meaning | What to do |
|---|---|---|
| 0 | `MDM-DEBUG-STILL-BROKEN` | Expected. Nothing to do |
| 2 | `MDM-DEBUG-NOW-WORKING` or `PARTIAL` | The limitation changed. Update `tests/README.md`, repo `README.md` §7, repo `journal.md` §15 |
| 1 | `BASELINE BROKEN` | The test couldn't run. Fix test 05 first — this run proves nothing |

Do not "fix" a failure here by editing the test. A failure is the documented,
correct outcome. The only change that should ever make this pass is a real
fix in the bridge.

Note the distinction between `BASELINE BROKEN` and the debug failures: the
baseline steps (connect, enumerate, program) are known-good, so if *they*
fail the environment is broken rather than the feature under test.

## Pass criteria

"Pass" means the documented failure reproduced exactly: `connect`,
`select-fpga` and `fpga-program` succeed, and all three of `stop`, `dow`,
`con` fail.

## Retest checklist

Re-run this after any of: upgrading openFPGALoader, switching XVC servers,
upgrading Vivado/Vitis, or changing how the bridge is started. Record the
openFPGALoader version — `run.sh` prints it — alongside the result.
