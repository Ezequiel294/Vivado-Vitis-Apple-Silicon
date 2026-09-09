# Journal — issues hit while building this environment

Chronological record of every problem encountered getting Vivado/Vitis 2026.1
running in Docker on the MacBook Air M5, what was tried, and what the actual
fix was. Entries are dated as they happened and are **not** revised
afterwards — later entries correct earlier ones. Three phases so far:
§1–12 building the environment (2026-09-03), §13–16 the day the board arrived
(2026-09-07), §17–19 the day the test suite first ran (2026-09-08).

For the current state of what works, read `README.md` §7 — not this file.

---

## 1. Rosetta was silently OFF — Docker was using QEMU

**Symptom:** `docker run --platform linux/amd64 … uname -m` printed `x86_64`,
so everything *looked* fine, but the VM's binfmt handler for x86-64 was
`/usr/bin/qemu-x86_64` (~10x slower than Rosetta; Vivado would have been
unusable).

**Diagnosis that worked:** read the binfmt registrations from inside the VM:

```sh
docker run --rm --privileged --platform linux/arm64 ubuntu:22.04 \
  sh -c 'mount -t binfmt_misc none /proc/sys/fs/binfmt_misc; ls /proc/sys/fs/binfmt_misc/'
```

**Tried:** setting `UseVirtualizationFramework: true` and
`UseVirtualizationFrameworkRosetta: true` in
`~/Library/Group Containers/group.com.docker/settings-store.json` and
restarting Docker → **no effect**, still qemu.

**Root cause:** `UseLibkrun: true` — Docker Desktop was on the **Docker VMM
(libkrun)** backend, which ignores the Rosetta setting entirely.

**Correct fix:** switch the VMM to **Apple Virtualization framework**
(`UseLibkrun: false`, done via Docker Desktop settings + restart) with the
Rosetta checkbox on. Verified by the `rosetta` binfmt entry
(`interpreter /run/rosetta/rosetta`) appearing in the list above.

---

## 2. AMD installer died silently mid-download (twice) — OOM kill

**Symptom:** installer GUI window vanished after ~30-60 min with no error;
23GB of the 27.7GB download present; no installer process left running.

**Diagnosis that worked:** installer logs
(`~/.Xilinx/xinstall/xinstall-*.log`) showed
`Used memory: 7865 MB. Total memory: 7934 MB` right before death, and the
kernel confirmed it: `cat /sys/fs/cgroup/memory.events` → `oom_kill 1`, plus
`docker inspect vivado` → `OOMKilled: true`. The installer's JVM eats nearly
8GB by itself.

**Correct fix:** raise the Docker VM memory **8GB → 10GB** (`MemoryMiB: 10240`,
i.e. Docker Desktop → Resources → Memory). The installer resumes interrupted
downloads, so nothing was lost. With 10GB it completed in ~30 min.

Related habit adopted: run `caffeinate -dims` on the Mac during long installs.

---

## 3. Vivado refused to start: "valid license was not found"

**Symptom:** first `vivado` GUI launch after install popped the License
Manager error dialog instead of the IDE. (Not a Rosetta bug — 2026.1 Standard
requires a license up front, matching the class slides.)

**Wrinkle:** the License Manager's "View Host Information" screen wasn't
reachable from the error dialog, but it wasn't needed — the identity is pinned
in `docker-compose.yml`.

**Correct fix:** generate the free **Vivado ML Standard node-locked** license
at xilinx.com/getlicense against host name `vivado-box`, Ethernet MAC
`02:42:AC:11:00:02`, Linux 64-bit, and copy the emailed `Xilinx.lic` to
`~/.Xilinx/Xilinx.lic` (persistent volume). These compose values must never
change or the license dies.

---

## 4. Vivado crashed in license checkout: `realloc(): invalid pointer`

**Symptom:** `vivado -version` and the bare GUI worked, but any *licensed*
startup (batch mode with the license installed) aborted with
`realloc(): invalid pointer` (glibc abort, hs_err log written).

**Diagnosis that worked:** the hs_err stack showed
`libXil_lmgr11.so` (FlexLM) → **system** `/lib/x86_64-linux-gnu/libudev.so.1`
→ `udev_enumerate_scan_devices` → realloc abort. This is the known
Vivado-under-Rosetta udev bug (docker/for-mac#7320), but our `LD_PRELOAD`
stub did NOT intercept it because **FlexLM loads libudev via
`dlopen`/`dlsym`, which bypasses LD_PRELOAD symbol interposition.**

**Correct fix:** don't just preload the stub — **replace the system library**:
symlink `/lib/x86_64-linux-gnu/libudev.so.1 → /opt/stub/libudev-stub.so`
(now done in the Dockerfile). Keep LD_PRELOAD too (belt and suspenders).
License checkout then worked; FlexLM reads the MAC by other means, so the
node-locked check still passes.

---

## 5. The libudev replacement broke apt (versioned symbols)

**Symptom:** after fix #4, `apt-get` printed
`no version information available (required by libapt-pkg.so.6.0)` and then
crashed with an ld.so assertion; later, after partial fixes,
`undefined symbol: udev_enumerate_get_udev, version LIBUDEV_183`.

**Root cause:** real libudev exports its symbols under the version tag
`LIBUDEV_183`; binaries like apt link against those versioned symbols. The
plain stub had no version info and was missing some symbols.

**Tried:** temporarily restoring the real symlink just to run apt (works but
means the stub and OS tools can't coexist — unacceptable).

**Correct fix (all three parts needed):**
1. compile the stub with `-Wl,-soname,libudev.so.1`,
2. add a version script (`udev-stub.map`) exporting `udev_*` under
   `LIBUDEV_183`,
3. extend `udev-stub.c` with the extra symbols apt/others reference
   (`udev_enumerate_get_udev` and ~25 more no-ops).

After that, `apt-get check` passes AND Vivado license checkout still works.
Baked into the Dockerfile.

---

## 6. Vivado Tcl `add_files` doesn't expand `~`

**Symptom:** `add_files ~/fpga-work/...` → `ERROR: [Vivado 12-172] File or
Directory '~/fpga-work/...' does not exist` (while `create_project` with `~`
worked, confusingly).

**Correct fix:** use `$env(HOME)/...` in all Vivado Tcl scripts.

---

## 7. MicroBlaze IP: wrong version selected by scripting

**Symptom:** `ERROR: [BD 5-216] VLNV <xilinx.com:ip:microblaze:9.5> is not
supported for the current part. The latest supported version… <11.0>`.

**Root cause:** picking the IP def with plain `lsort` — string sort puts
`9.5` after `11.0`.

**Correct fix:** `lsort -dictionary` (numeric-aware) when selecting from
`get_ipdefs`.

---

## 8. Board automation wired a generic diff clock instead of the board clock

**Symptom (several rounds):**
- `get_bd_pins clk_wiz_1/clk_in1` → no such pin;
- automation with `Board_Interface {sys_clock}` "succeeded" but the generated
  wrapper had `diff_clock_rtl_clk_p/n` ports — a generic differential clock,
  not the board oscillator, which would never work on hardware.

**Tried:** targeting the `CLK_IN1_D` interface pin; using the GUI display-name
config string `{sys_clock ( System Clock ) }` → still fell back to the
generic diff clock.

**Root cause (from the board file):** the Arty **S7-25's `sys_clock` is a
12MHz single-ended** oscillator, while the clocking wizard defaults to a
differential input (`CLK_IN1_D`); the automation can't bind single-ended
board clock → diff input and silently creates a generic port instead.

**Correct fix:** before the board automation, run
`set_property CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin}` on the
clk_wiz cell so it exposes plain `clk_in1`, then apply the `sys_clock` board
automation to that pin. Also added a guard that errors out if any
`*diff_clock*` port exists after automation. (The MMCM multiplies 12MHz →
100MHz internally; working script: `fpga-work/projects/mb-hello/build-hw.tcl`.)

---

## 9. Generated Verilog wrappers had syntax errors — corrupted headers

**Symptom:** synthesis failed with `syntax error near '='` at line 7 of
**Vivado-generated** files (`system_wrapper.v`, `system.v`). Inspection showed
the `//Host : … running 64-bit Ubuntu"` header comment followed by raw,
uncommented lines of `/etc/os-release` (`VERSION_ID="22.04"…`).

**Root cause:** Vivado's OS-detection shells out to `lsb_release`; without it,
it falls back to parsing `/etc/os-release` badly and pastes multi-line output
into a single-line Verilog comment.

**Correct fix:** install `lsb-release` in the image. Header becomes one clean
line; generated files compile.

---

## 10. Vitis scripting: XSCT is dead in 2026.1

**Symptom 1:** `xsct` → `ERROR: xlsclients is not available` → fixed by
installing `x11-utils`. But then:

**Symptom 2:** `[ERROR]********** XSCT is disabled in Vitis 2026.1 release`.

**Correct fix:** use the **Vitis unified Python API** instead:
`vitis -s script.py` with `vitis.create_client(workspace=…)`,
`create_platform_component(hw_design=<xsa>, os="standalone",
cpu="microblaze_0")`, `create_app_component(template="hello_world")`, then
`.build()`. Working script pattern preserved in this journal's companion
scripts under `fpga-work/projects/mb-hello/`.

---

## 11. Vitis platform build failed in `dtc`

**Symptom:** `create_platform_component` → `Error in generating Processor
List. [fdt.py][ERROR]: dt_compile: unable to compile…` with no useful detail.

**Diagnosis that worked:** running AMD's bundled binary directly:
`/opt/Xilinx/2026.1/Vitis/bin/dtc --version` →
`error while loading shared libraries: libyaml-0.so.2`.

**Correct fix:** install `libyaml-0-2` in the image. Platform + hello-world
then built cleanly (this was the moment Vitis-under-Rosetta was proven to
work — the project's biggest open risk).

---

## 12. Smaller snags

- **`docker cp` of board files nested wrongly:** copying
  `arty-a7-100` into `…/board_files/` landed its `E.0` version dir at the top
  level (target dir didn't exist yet). Vivado still found the board via
  `board.xml`, but the layout was fixed to the proper
  `board_files/arty-a7-100/E.0/` nesting.
- **Proton Drive "Edit conflict" copies:** Vivado's build tree churns fast
  enough inside the synced `fpga-work/` folder that Proton Drive created
  `… (# Edit conflict … #).vdi` duplicates of intermediates. Harmless —
  delete them; pause sync during long builds if it gets noisy.
- **Quitting Docker Desktop from scripts is unreliable:** `osascript quit`
  sometimes leaves it running; the user ended up restarting it manually when
  changing VM settings.
- **Vivado License Manager GUI couldn't show Host Information pre-license** —
  irrelevant in this setup since the identity is pinned in compose, but worth
  knowing if following the class slides literally.

---

# Hardware day (2026-09-07) — board arrived, and it's an A7

## 13. "openFPGALoader isn't working" — no, the bitstream was for the wrong FPGA

**Symptom:** loading `example1-arty-s7-25.bit` with `-b arty_a7_100t`
"succeeded" (`Load SRAM ... Done`) but the status readout showed
`ID Error: ID error` and `Done: 0`, and nothing ran.

**Root cause:** the board that arrived is an **Arty A7-100T** (xc7a100t,
IDCODE `0x3631093`), not the Arty S7-25 all the scripts targeted. The FPGA
rejects a bitstream whose embedded part IDCODE doesn't match — that whole
register dump *is* the board answering correctly over JTAG.

**Correct fix:** rebuild for the A7: part `xc7a100tcsg324-1`, board_part
`digilentinc.com:arty-a7-100:part0:1.1`, the A7 master XDC pins, and a
100MHz (not 12MHz) single-ended `sys_clock`. A7 variants now live alongside
the S7 ones: `example1/build-a7.tcl`, `mb-hello/build-hw-a7.tcl`,
`mb-hello/make-vitis-a7.py`, `constraints/Arty-A7-100-Master-example1.xdc`.
Recognize the signature: **`ID Error` + `Done 0` = wrong-part bitstream, not
a cable/driver problem.**

## 14. MicroBlaze never ran: held in reset by a dangling `ext_reset_in`

**Symptom:** mb-hello bitstream programmed fine (DONE=1) but no UART output,
and xsdb said `Cannot stop MicroBlaze. MicroBlaze is not being clocked`
(misleading — see below).

**Diagnosis that worked** (after ruling out reset-button polarity, pin
placement, XVC, and the serial path): a diagnostic bitstream wired three
status signals to LEDs — `clk_wiz.locked` (LD4), a counter heartbeat on the
MB clock (LD5), and `proc_sys_reset.mb_reset` (LD6). Result: LD4 on, LD5
blinking, **LD6 solid on** → clock fine, CPU permanently in reset.

**Root cause:** our script applied the board `reset` automation only to the
clocking wizard's reset pin. `proc_sys_reset/ext_reset_in` was left
unconnected — and since its polarity expects the active-low button, the tied
default reads as *asserted*, so `mb_reset` never deasserts. Compile-only
validation (and Vitis builds) can never catch this; it only shows on
hardware. (The xsdb "not being clocked" message was a red herring here — see
issue 15: it appears over the XVC bridge even when the CPU runs fine.)

**Correct fix:** also apply the board reset automation to
`ext_reset_in` (now in both `build-hw.tcl` and `build-hw-a7.tcl`, with a
guard that errors if the pin ends up unconnected). After the fix the
hello-world prints on the serial port and the red RESET button restarts it.

## 15. MicroBlaze debug over openFPGALoader's XVC does NOT work — bake the ELF into the bitstream instead

The hoped-for flow — xsdb in the container downloading/running ELFs through
the XVC bridge (`connect -xvc-url`, `targets`, `dow`, `con`) — **fails**:
every MDM debug operation (`stop`, `dow`) errors with `Cannot stop
MicroBlaze. MicroBlaze is not being clocked`, even when the CPU is
*provably running* (heartbeat LED + serial output) and with the bridge
slowed to 1MHz. Chain enumeration and `fpga -f` programming over the same
bridge work every time, so it's specifically openFPGALoader v1.1.1's XVC
server mishandling the longer BSCAN/USER2 debug transactions (AWS saw
similar MDM-over-XVC trouble: aws/aws-fpga#641). Don't trust that error
message — check a heartbeat/reset LED before chasing clocking bugs.

Notes on what *does* work with xsdb over the bridge (xsct is disabled in
2026.1, xsdb is not; `vitis -s` Python has no run/debug calls at all):

```tcl
connect -xvc-url tcp:host.docker.internal:2542
targets -set -filter {name =~ "xc7a*"}
fpga -f <bitstream>          # programming: reliable
# stop / dow / con           # debug ops: broken through this bridge
```

**The working run-on-hardware path** is `updatemem`: bake the ELF into BRAM
so the program runs at power-on, no debugger involved:

```sh
updatemem -meminfo <impl>/system_wrapper.mmi -data hello.elf \
  -bit <impl>/system_wrapper.bit -proc system_i/microblaze_0 -out boot.bit
```

Program `boot.bit` from macOS with openFPGALoader (or `fpga -f` via xsdb)
and press the board's RESET button to re-run. This covers everything the
course needs (run software on the soft CPU + serial I/O); what's lost is
only interactive breakpoint debugging from the Vitis GUI. Upgrading
openFPGALoader was considered and skipped — no upstream fix exists for
this. If interactive debug ever becomes a hard requirement, the options are
a different XVC server implementation or the Windows-ARM-VM fallback.

## 16. Smaller hardware-day snags

- **openFPGALoader's XVC default port is 3721, not 2542** — pass
  `--port 2542` (or use 3721 in the `-xvc_url`). Also the XVC server quits
  when stdin hits EOF, so backgrounded it needs stdin held open
  (`sleep 999999 | openFPGALoader ... --xvc --port 2542`).
- **Vivado Hardware Manager over openFPGALoader's XVC is flaky**: the first
  `open_hw_target -xvc_url` worked, later ones failed with
  `No devices detected` even after killing stale in-container
  `hw_server`/`cs_server` processes (which do linger after xsdb/Vivado exits
  and must be pkill'd by their unwrapped names). **xsdb over the same bridge
  was reliable every time** — prefer it for programming/running.
- **AXI Uartlite instantiated by automation defaults to 9600 baud**, not
  115200. Either read the serial console at 9600 or set
  `CONFIG.C_BAUDRATE {115200}` on the uartlite cell before building.
- **The FT2232 drops UART bytes while its JTAG channel is busy** — output
  printed during/right after programming arrives truncated. Press the RESET
  button (with `ext_reset_in` wired) to re-run the program and get clean
  output, or just expect the first line to be mangled after `fpga -f`.
- The macOS serial device has two channels: `…88820` is JTAG (channel A),
  `…88821` is the UART (channel B) — use the `1` suffix with
  `screen`/`cat`.
- **`screen` on `/dev/tty.usbserial-*` exits by itself after ~5 seconds** —
  the `tty.` devices wait for a carrier signal. Use the **`/dev/cu.*`**
  variant, which opens immediately and stays.
- **Power-cycling the board wipes the design** (SRAM configuration) and the
  FPGA boots Digilent's **factory demo from QSPI flash**, which prints on
  the UART at **115200** — read at 9600 that's pure junk bytes. Looks like a
  serial problem; it's just the wrong design running. Reprogram the
  bitstream after every power-up (the `PROG` button also reverts to the
  factory demo).
- A pure-Verilog UART blaster (`projects/uart-test/`) that spams `U` at 9600
  on D10 proved the Mac-side serial path independently of the CPU — a handy
  divide-and-conquer tool to keep around.


# Test-suite day (2026-09-08)

## 17. The entire test suite was unrunnable: Proton Drive "dataless" files return EIO inside the container

**Symptom:** `tests/02-simulation/run.sh` — the smallest, fastest test in the
suite, documented as "under a minute" — ran for **9 minutes** and had to be
interrupted. `ps` inside the container showed it had never got past the first
of its three steps:

```
/opt/Xilinx/2026.1/Vivado/bin/unwrapped/lnx64.o/xvlog src/adder4.v sim/adder4_tb.v
   99.9% CPU, 11:22 elapsed, state R
```

`xvlog` is only the Verilog *parser*; `xelab` and `xsim` never started. It
left `xvlog.log` and `xvlog.pb` behind at **0 bytes** — opened, never written.

**Diagnosis that worked:** three reads, in this order.

1. `xvlog` on a trivial module in the container's **own** filesystem
   (`/tmp`): **2 seconds**. So the tool and Rosetta are fine.
2. Copying the real sources from the mount into `/tmp` to try them there:

   ```
   cp: error reading '/home/user/fpga-work/tests/02-simulation/src/adder4.v':
       Input/output error
   ```

   The container cannot *read* the file, while macOS reads it fine.
3. Counting local blocks vs. apparent size across the tree
   (`du -k` = 0 but `stat -f%z` > 0) found **27 of 43 files dataless** —
   including nearly every `run.sh`, `build.tcl`, and `.v`/`.c` source in the
   suite. The survivors were exactly the files that had been `cat`ed on the
   host earlier in the session.

**Root cause:** `fpga-work` lives in
`~/Library/CloudStorage/ProtonDrive-…`. Proton Drive's File Provider evicts
file *contents* while leaving the directory entries and sizes intact
(`com.apple.decmpfs` xattr, zero local blocks). macOS materializes such a file
on demand when something reads it — but the container reads through Docker's
bind mount, and that path does **not** trigger materialization. It returns
`EIO` instead. Vivado's `xvlog` responds to a read error by spinning on a core
indefinitely rather than exiting, which is what turned an unreadable 848-byte
file into a 9-minute silent hang.

Note the shape of this failure: `ls` looks perfect, `stat` reports the right
size, the host can `cat` everything, and the file is genuinely there. Only the
container sees it as broken, and only for files the cloud has evicted — which
is why it hits whichever tests you happen not to have opened recently, and
looks like a slow or flaky toolchain rather than a storage problem.

**Fix that worked (immediate):** force materialization by reading every file
from the **macOS side**, which is the side that honours on-demand download:

```sh
cd "…/fpga-work" && find . -type f -exec cat {} + > /dev/null
```

43/43 materialized, 43/43 then readable from inside the container, and
`02-simulation` passed in **11 seconds** — same script, same sources, nothing
else changed.

**Fix worth making permanent:** this will recur every time Proton Drive
decides to reclaim space. Either pin the folder ("Keep available offline") or,
better, move `fpga-work` out of `CloudStorage` onto local disk and sync/back
it up by another route. The existing README warning about cloud sync only
mentions *"Edit conflict"* duplicate files during builds — a cosmetic problem.
This one is not cosmetic: it makes builds hang with no error message.

**Recognize it by:** a Vivado tool pinned at ~100% CPU making no progress,
0-byte `.log`/`.pb` files next to it, and `Input/output error` when you try to
`cp` the input file inside the container while it reads fine on the Mac.

---

## 18. Two tests could never have passed — never-run scripts with latent bugs

Both were written 2026-09-07 and had never been executed. Neither failure was
environmental; both were bugs in the test scaffolding itself.

**Test 03 (`make-app.py`) — deleted a file its own build still referenced.**
The Vitis `hello_world` template pins its source list in
`vitis/hello/src/UserConfig.cmake`:

```cmake
set(USER_COMPILE_SOURCES
"helloworld.c"
)
```

The script removed `helloworld.c`, copied in our `main.c`, and left the list
untouched, so CMake configure died with `Cannot find source file:
helloworld.c` followed by `No SOURCES given to target: hello.elf`. Worse, the
real message was hidden — Vitis runs its configure with `> /dev/null` and only
surfaces `CMake Configuration for the Application Failed`. Fix: repoint
`USER_COMPILE_SOURCES` at `main.c` after copying it in.

**Test 06 (`debug-test.tcl`) — an ambiguous target filter.**
`targets -set -filter {name =~ "MicroBlaze*"}` matches *two* entries on this
chain:

```
2  MicroBlaze Debug Module at USER2
3  MicroBlaze #0 (No clock)
```

so xsdb aborted with `more than one targets found`, the three debug
operations never ran, and the script printed the misleading
`SUMMARY: the MicroBlaze target does not even enumerate` — when in fact both
targets enumerate perfectly well. Fix: filter on `"MicroBlaze #*"` to select
only the CPU.

The lesson worth keeping: a test that has never been run is not evidence of
anything, and a *regression* test that has never been run is actively
dangerous — test 06 would have reported "the MDM doesn't enumerate", sending
the next person after a hardware fault that does not exist.

Once the filter was fixed, test 06 reproduced the documented failure exactly
(openFPGALoader v1.1.1): `stop` and `dow` both fail with `Cannot stop
MicroBlaze. MicroBlaze is not being clocked`, and `con` fails with **`Already
running`** — in the same session. That pair is the neatest proof yet that the
"not being clocked" message is simply false.

---

## 19. ILA and VIO DO work over the XVC bridge (the open question, answered)

Test 07's outcome was genuinely unknown. It works — both cores, fully.

**ILA:** 1024 samples captured, the 32-bit counter incrementing by exactly one
per sample with no gaps or corruption (`8b1d1644` → `8b1d1a43`; last minus
first = `0x3FF` over 1024 samples).

**VIO:** read `probe_in0` as `0000`, then `1001` after the switches were
physically flipped, while the ILA's independent switch probe agreed (`sw` went
`0` → `9`). Driving `probe_out0` to `101` lit LD4 and LD6 as predicted.

This narrows issue 15 considerably. The bridge is not bad at on-chip debug in
general — it carries ILA capture uploads and VIO probe traffic reliably. It is
specifically **MDM** transactions that fail. For coursework this is the good
outcome: "add an ILA and capture the bus" is fully supported.

### Two things that made it work

**Retry `open_hw_target`.** The first attempt frequently fails with
`No devices detected on target localhost:3121/xilinx_tcf/Xilinx/host.docker.internal:2542`
*even though the bridge log shows `connection accepted`*. A retry loop
(4 attempts, `refresh_hw_server` between) made it reliable. Combined with
clearing stale `hw_server`/`cs_server` first, this is the whole fix for the
"Hardware Manager is flaky" reputation in issue 16.

**Lowering the JTAG clock was NOT needed.** The first success used
`--freq 1000000`, so that looked like the remedy — but a control run at the
default 10MHz *with the retry loop* succeeded on attempt 1. Retrying is the
fix; the frequency change was a coincidence. (Recorded because it would have
been easy, and wrong, to write down "use 1MHz for ILA".)

### None of this needs the GUI

`tests/07-ila-vio/ila-check.tcl` drives both cores from batch Tcl and dumps
the capture with `write_hw_ila_data -force -csv_file`, which is how the
numbers above were checked by machine rather than by eye. Useful for
regression runs, and useful when the GUI is painful under emulation.

Two API details that cost time:
- VIO probes are named in the `.ltx` after **the nets they are wired to**
  (`sw_IBUF`, `vio_led`), *not* the IP port names, so `get_hw_probes
  probe_in0` silently matches nothing and `set_property` then fails with
  `expects at least one object`.
- `DIRECTION` is not a valid property on a `hw_probe`, so probes cannot be
  classified that way.

---

## End state (as of 2026-09-08)

The image and container reproduce every fix above from files in the repo
(`Dockerfile`, `udev-stub.c`, `udev-stub.map`, `docker-compose.yml`) —
verified by a full rebuild + recreate, after which license checkout, a Verilog
bitstream build, and a Vitis MicroBlaze compile all still pass.

Verified on the Arty A7-100T by the test suite (`tests/README.md`, tests
01–07): bitstream build and programming from macOS, programming from inside
the container over XVC, simulation, a MicroBlaze running C and printing at
9600 baud, serial input reaching the FPGA, and ILA/VIO on-chip debug.

Two things are not settled. **Interactive MicroBlaze debug does not work**
through the XVC bridge (§15, §18) — GUI and CLI alike — so `updatemem`
boot-bitstreams are the standard software flow; the cheapest untried fix is a
newer openFPGALoader than Homebrew's v1.1.1. And **flash boot (test 08) has
never been run**, because it writes persistent flash and needs a jumper fitted
by hand.

The S7-25 scripts carry the same `ext_reset_in` fix but remain
hardware-untested.
