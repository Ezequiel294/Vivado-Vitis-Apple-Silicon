# Reference — how the daily workflow actually works

The [README](README.md) tells you which commands to run. This file explains
*why* they are what they are: what each tool really does, which paths through
the toolchain exist, what the scripts are doing on your behalf, and which parts
of the normal Xilinx flow are unavailable here and what replaces them.

Read the README to get work done. Read this when something surprises you, when
you need to do something the scripts do not cover, or when you want to know
what you are actually looking at.

For the chronological account of how all of this was worked out — every dead
end, every fix and why — see [journal.md](journal.md).

---

## Compile, program, debug: three different things

Much of the confusion in this environment comes from collapsing three separate
operations into one idea. They are done by different tools, in different
places:

| Step | What it means | Who does it |
|---|---|---|
| **Compile** | Verilog / block design → `.bit` | **Vivado only**, always in the container |
| **Program** | send an existing `.bit` to the FPGA over JTAG | openFPGALoader on the Mac (path A) **or** xsdb / Hardware Manager over XVC (path B) |
| **Debug** | watch the design *while it runs* — ILA, VIO | Hardware Manager over XVC (path B only) |

Neither programming path compiles anything. Both just load a bitstream Vivado
has already produced. Path A is the default and covers the everyday loop;
path B exists for on-chip debug and for tools that run inside the container.

---

## Path B — the XVC bridge (JTAG over TCP)

The container has no USB: Docker on macOS can't pass the board's FTDI chip
through, so Vivado inside the container cannot reach the Arty by itself.
**XVC (Xilinx Virtual Cable)** closes that gap — openFPGALoader plays the part
of the cable, serving JTAG over a TCP socket the container connects to.

```
Vivado / xsdb / Vitis  --TCP:2542-->  openFPGALoader --xvc  --USB-->  Arty A7-100T
   (in container)                          (on the Mac)
```

`host.docker.internal` is how the container addresses your Mac.

**Use it for on-chip debug — ILA and VIO.** That's the real reason it exists.
An ILA records internal signals into on-chip memory and Hardware Manager reads
them back as waveforms; a VIO gives you virtual switches and LEDs for a
running design. openFPGALoader alone can do neither — it only pushes
bitstreams. The bridge also lets you program from inside the container
(Hardware Manager, or xsdb `fpga -f`) and inspect the scan chain.

**Skip it for everything else.** Compiling never touches the board, and the
everyday loop — edit Verilog, build, load the `.bit`, look at the LEDs — is
simpler over path A.

**It cannot do MicroBlaze breakpoint debugging** or Vitis "Run on Hardware".
Use the boot-bitstream flow instead (below).

### Three rules that save time

- **`--port 2542` is required.** openFPGALoader's XVC default is 3721; Xilinx
  tools expect 2542.
- **The bridge is single-client.** One of Hardware Manager *or* xsdb at a
  time, path A can't be used while it runs, and `screen` must be closed.
- **Retry `open_hw_target`.** The first attempt often fails with "No devices
  detected" even though the bridge logged the connection; a retry usually
  works. If it keeps failing, clear stale servers:
  `docker exec vivado pkill -x hw_server`.

### Using it (two terminals)

**Terminal 1 (Mac)** — start the bridge and leave it running:

```sh
openFPGALoader -b arty_a7_100t --xvc --port 2542         # Ctrl-C quits
```

**Terminal 2** — xsdb inside the container (xsdb is the JTAG console that
ships with Vitis; 2026.1 disabled xsct, but xsdb works):

```sh
docker exec -it vivado bash -lc 'source /opt/Xilinx/2026.1/Vitis/settings64.sh && xsdb'
```

At the `xsdb%` prompt, one line at a time:

```tcl
connect -xvc-url tcp:host.docker.internal:2542    ;# reach the bridge on the Mac
targets                                           ;# list the scan chain
targets -set -filter {name =~ "xc7a*"}            ;# select the FPGA
fpga -f ~/fpga-work/bitstreams/<file>.bit         ;# program it
exit
```

`targets` should list `xc7a100t` (plus the MDM and CPU for MicroBlaze
designs). If `connect` fails, the bridge in terminal 1 isn't running.

In the GUI: Hardware Manager → Open Target → Open New Target → Local server.
`tests/07-ila-vio/ila-check.tcl` does the same job headlessly from batch Tcl,
including dumping an ILA capture to CSV.

---

## Why C is compiled by a script instead of a button

**The Vitis IDE does not start here** — it is an Electron app and Chromium
crashes under emulation, under Rosetta *and* QEMU alike (journal §20). That
costs you the editor, the project wizards and the build buttons. It does
**not** cost you Vitis: the compiler, the BSP generator and the linker are
separate command-line tools that work fine. Vivado's GUI is unaffected, so the
class flow — design the hardware in Vivado, write C for it in Vitis — is
intact. Only the C gets compiled by a script instead of a button.

Three scripts stand in for the parts of the IDE you would have used:

| Script | Replaces |
|---|---|
| `make-app.sh` | New Platform Project + New Application Project wizards, and the Build → Settings page |
| `run-sw.sh` | the Build and Run buttons |
| `serial.sh` | the IDE's serial terminal (and TeraTerm's "Receive new-line: LF" setting) |

### What `make-app.sh` is really doing

It builds the **BSP** — the drivers and headers generated for *your* block
design, which is how `xil_printf()` knows how to reach your UART — and then
creates an application component against it. That is the whole content of the
two wizards it replaces.

Underneath, it runs `tools/make-app.py` inside the container through
`vitis -s`, the Vitis Python API. `make-app.py` is the part that talks to the
toolchain; it is not meant to be run directly.

To run any Vitis script of your own the same way:

```sh
docker exec vivado bash -lc 'source /opt/Xilinx/2026.1/Vitis/settings64.sh && vitis -s <script>.py'
```

### What a template app brings with it

`-t <template>` instantiates one of the ~35 applications shipped with the
toolchain (`hello_world`, `dhrystone`, `memory_tests`, `peripheral_tests`,
`lwip_*`, the FSBLs, …) — the same list the IDE shows as its Examples library.

A template app is **not** like a hello-world app:

- It brings its own sources, its own BSP libraries and its own linker
  settings. There is no `src/main.c` for it, and `run-sw.sh` will not put one
  there — your project's `main.c`, if it has one, is left out of it entirely.
  The rule both scripts follow is simple: *the app's sources are yours to sync
  only if the app already has a `main.c` of its own.*
- It states what hardware it needs, and creation fails if the design lacks it.
  `dhrystone` wants a UART, an AXI Timer and at least `0x7800` bytes of
  memory; the error quotes Vitis's own reason and leaves no half-made app
  behind.

### Where compiler settings actually go

`-O` and `-g` are the IDE's **Build → Settings** page. They are applied through
`set_app_config`, the same API the IDE calls, and land in the app's
`UserConfig.cmake` as:

```cmake
set(USER_COMPILE_OPTIMIZATION_LEVEL "-O3")
set(USER_COMPILE_DEBUG_LEVEL "")
```

They survive rebuilds. Passing either flag for an app that **already exists**
updates the setting and rebuilds, which is what makes "measure the same program
at several optimization levels" a two-command loop:

```sh
./tools/make-app.sh -d projects/hw2 -a dhry -O -O0    # rebuild at -O0
./tools/make-app.sh -d projects/hw2 -a dhry -O -O3    # and again at -O3
```

The flags actually used are printed in the build output, so you can show them
in a report.

Every build ends by printing the compiled size — the `text data bss dec hex`
line. That is `mb-size` running as the last build step, and it is where
"collect the code size from the compilation log" comes from.

### Why the ELF is baked into the bitstream

A bitstream configures *hardware*. Your compiled program is a separate artifact
that lives in the CPU's BRAM, and a plain `.bit` comes up with that memory
empty — a running MicroBlaze executing nothing.

Normally Vitis "Run on Hardware" would download the ELF over JTAG through the
MicroBlaze Debug Module. That path does not work here (see below), so
`run-sw.sh` merges the two files *before* download with `updatemem`. The
program then starts the moment the FPGA configures, and the RESET button
re-runs it.

The underlying command, if you want to run it by hand:

```sh
updatemem -meminfo <impl>/<top>_wrapper.mmi -data <app>.elf \
  -bit <impl>/<top>_wrapper.bit -proc <design>_i/microblaze_0 -out boot.bit
```

`make-app.sh` and `run-sw.sh` find these things rather than assuming names, so
they work with GUI-made projects (`design_1_wrapper.bit`,
`<Project>.runs/impl_1`) as well as the scripted tests
(`system_wrapper.bit`, `vivado/…`). The processor instance is read out of the
`.mmi`.

---

## What does not work, and why

*Verified on hardware; see journal §15, §19, §20.*

**Interactive debug of the MicroBlaze** — breakpoints, single-step,
`stop`/`dow`/`con`, and the Vitis GUI's "Run/Debug on Hardware" — does not
work. openFPGALoader's XVC server mishandles the MicroBlaze Debug Module's
transactions, and the symptom is misleading: xsdb reports "MicroBlaze is not
being clocked" when the clock is fine.

The failure is narrow. **ILA and VIO work fine over the same bridge** (journal
§19), so on-chip debug as a whole is available; only the CPU debug module
fails. The
Vitis GUI would fail identically to the command line (same
`hw_server → XVC → MDM` path), so there is no GUI-only workaround even if the
IDE ran.

Debug instead with `xil_printf` over the serial console, LEDs, and the RESET
button to re-run — which is what `run-sw.sh` is built around. If breakpoints
ever become essential, the options are a different XVC server or a Windows-ARM
VM with native cable drivers.

`tests/06-mb-debug` is a regression test for this: it is *expected* to fail,
and reports the limitation disappearing as the result that needs the docs
updated.

---

## Serial console details

### Why `screen` sometimes looks broken

C code that ends its lines with a bare `\n` — which most toolchain-supplied
code does, Dhrystone included — stair-steps down the screen under `screen` or
`cat`, because nothing returns the cursor to the left margin. This is the same
problem the course slides solve by setting TeraTerm's "Receive new-line" to LF.

`tools/serial.sh` fixes it by echoing a carriage-return-inserted copy to your
terminal while writing the board's bytes to the log **exactly as sent**. So the
log is faithful and the screen is legible.

`serial.sh` is read-only — it cannot send input. Use `screen` when the program
expects you to type.

### Do not source `tests/common/lib.sh` at your shell prompt

It is a library for scripts. Sourcing it interactively does two harmful things
at once: it reads `BASH_SOURCE`, which is unset in zsh, so `FPGA_WORK` silently
resolves to the wrong directory; and it runs `set -euo pipefail`, which in an
interactive shell closes your terminal on the next command that returns
non-zero. `lib.sh` now refuses to load under anything but bash and points you
at `serial.sh` instead.

Inside a test's `run.sh`, the underlying helper is
`capture_serial "$log" "$secs" "$pattern"`. It returns non-zero on timeout, so
call it as a condition:

```sh
if capture_serial "$log" 60 "done"; then … else … fi
```

---

## Batch builds (no GUI)

```sh
docker exec -w /home/user/fpga-work/tests/01-leds vivado bash -lc \
  'source /opt/Xilinx/2026.1/Vivado/settings64.sh && vivado -mode batch -source build.tcl'
```

Every test in `fpga-work/tests/` is a worked reference to copy from:
`01-leds/build.tcl` (plain Verilog), `03-mb-hello/build-hw.tcl` (a MicroBlaze
block design), `07-ila-vio/build.tcl` (debug cores),
`09-dhrystone/build-hw.tcl` (a MicroBlaze with 128 kB of local memory, an AXI
Timer, and guards on all three).

---

## The test suite in detail

Nine tests, each with a README stating what it proves, how a human runs it, how
an agent runs it, its pass criteria and its failure modes.

Status: **01–07 pass** (2026-09-08), **09 passes** (2026-09-21), 08 (flash
boot) not yet run. Per-test detail is in `tests/README.md`.

`run-all.sh` covers 01–07. Two are left out of it and run deliberately:

- **08 (flash boot)** writes persistent flash and needs a jumper moved by
  hand — a hazard, and it refuses to run unattended.
- **09 (dhrystone)** is only slow: a second 20+ minute MicroBlaze build. It is
  the benchmarking test, and it checks its own result off the serial port —
  template app, `-O3` with no debug, `updatemem` on a 128 kB local memory, and
  a non-zero Dhrystones/second. Run it with `--no-hw` to reuse its bitstream.

Two results need reading carefully:

- **06 is *expected* to fail**, for the reason above.
- **07 settled the suite's big open question: ILA and VIO both work.**

The copy in this repo is **sources only** — build outputs (`vivado/`,
`vitis/`, `.bit`, `.xsa`, `.ltx`, logs) are gitignored, so a fresh copy
rebuilds from scratch. Tests 03 and 09 take 20+ minutes the first time; the
rest are minutes.

### Why the tests must be copied out of the repo

Only `fpga-work` is bind-mounted, so the container cannot see this repo at all.
`tests/common/lib.sh` derives container paths by stripping the `fpga-work` root
off host paths; run from anywhere else and every `docker exec` targets a path
that does not exist. Copy **both** `tests/` and `tools/` — `tools/run-sw.sh`
sources `../tests/common/lib.sh`.

The copies in `fpga-work/` are what actually run, and they do not update
themselves. After pulling repo updates, re-copy:

```sh
cp -R tests tools "/path/to/your/fpga-work/"
```
