# Vivado/Vitis 2026.1 on Apple Silicon (Docker + Rosetta)

x86-64 Linux container that runs AMD **Vivado/Vitis 2026.1** on an Apple Silicon
Mac for CS3375 (Computer Architecture, TTU). Everything is defined by files in
this repo — no third-party images. Verified end to end on an **Arty A7-100T**;
the **Arty S7-25** is supported by the same setup but has never been tested on
hardware.

**How it works:** a thin Ubuntu 22.04 (amd64) image runs under Docker Desktop's
Rosetta emulation. Vivado/Vitis is installed once, via its normal GUI installer,
onto a persistent Docker volume. GUIs display through XQuartz. The board is
programmed from macOS (`openFPGALoader`), because Docker on macOS has no USB
passthrough; Vivado/Vitis reach the board's JTAG over TCP (XVC) when needed.

| Piece | Where |
|---|---|
| Vivado/Vitis install (~71GB) | Docker volume `xilinx-install` → `/opt/Xilinx` |
| License + Vivado config | Docker volume `xilinx-config` → `~/.Xilinx` |
| Coursework (projects, bitstreams, XDCs) | a folder you choose on the Mac ↔ `~/fpga-work` in the container |
| Test suite (8 tests) + helper scripts | `./tests/` and `./tools/` in this repo — **copy both into your `fpga-work` folder to run them** |
| AMD installer `.bin` | `./installer/` (read-only in container; deletable after install) |

---

## 1. Prerequisites (macOS)

```sh
brew install --cask docker xquartz
brew install openfpgaloader
```

**Docker Desktop settings** (Settings → General / Resources):
- Virtual Machine Manager: **Apple Virtualization framework** — *not* "Docker
  VMM". Docker VMM silently falls back to QEMU, which is ~10x slower and makes
  Vivado unusable.
- **"Use Rosetta for x86_64/amd64 emulation on Apple Silicon": ON**
- Memory: **10 GB** (8 GB gets the AMD installer OOM-killed mid-download)
- Disk: at least ~110 GB of Docker disk space free during installation

Verify Rosetta is really active (must print a `rosetta` entry):

```sh
docker run --rm --privileged --platform linux/arm64 ubuntu:22.04 \
  sh -c 'mount -t binfmt_misc none /proc/sys/fs/binfmt_misc 2>/dev/null; ls /proc/sys/fs/binfmt_misc/' | grep rosetta
```

**XQuartz** (one time): open XQuartz → Settings → Security → check
**"Allow connections from network clients"**, then quit and reopen XQuartz.

## 2. Build and start the container

First pick where coursework lives on your Mac (e.g. a `fpga-work` subfolder of
your class folder), create it with `projects/`, `bitstreams/`, `constraints/`,
`tests/` and `tools/` inside, and put its **absolute path** in the
`/CHANGE/ME/fpga-work` line of `docker-compose.yml`.

For `tests/` and `tools/`, copy this repo's `./tests` and `./tools`
directories into that folder rather than creating them empty — see
[The test suite](#the-test-suite) below. They have to live under the mounted
folder to work.

```sh
cd <path to this repo>
docker compose build
docker compose up -d
/opt/X11/bin/xhost +localhost        # allow the container to draw on XQuartz
docker exec vivado xeyes             # smoke test: eyes should appear on screen
```

Notes:
- The compose file pins `hostname: vivado-box` and `mac_address:
  02:42:ac:11:00:02`. The AMD license is node-locked to these — **never change
  them**.
- `udev-stub.c` builds into a fake `libudev` inside the image. It prevents two
  Vivado crashes under Rosetta (`udev_enumerate_scan_devices` abort at GUI
  start and a `realloc(): invalid pointer` in FlexLM license checkout). It is
  applied both via `LD_PRELOAD` and as the system `libudev.so.1`.

## 3. Install Vivado/Vitis (one time, ~2h)

1. From https://www.xilinx.com/support/download.html download the **AMD Unified
   Installer for FPGAs & Adaptive SoCs 2026.1 — Linux Self Extracting Web
   Installer** (`.bin`, needs a free AMD account) into this repo's `installer/`
   directory, then `chmod +x installer/*.bin`.
2. Launch it in the container (window appears via XQuartz):
   ```sh
   docker exec -d vivado /installer/FPGAs_AdaptiveSoCs_Unified_SDI_2026.1_0616_1700_Lin64.bin
   caffeinate -dims &                 # keep the Mac awake during the install
   ```
3. In the wizard: sign in → **Download and Install Now** → product **Vivado** →
   **Vivado ML Standard** → customization:
   - check **Vitis Embedded Development** (needed for the soft-CPU units;
     Vitis HLS is *not* a substitute),
   - Devices → 7 Series: **Artix-7** and **Spartan-7** only,
   - install path **`/opt/Xilinx`** (the persistent volume — anywhere else is
     wiped with the container).
4. If the installer window vanishes: it was probably OOM-killed — confirm VM
   memory is 10GB and relaunch; it resumes downloads where it stopped.
5. Afterwards you can delete `installer/*.bin` to reclaim ~400MB, and the
   download cache is auto-removed by the installer.

## 4. License (one time)

Vivado 2026.1 refuses to start without a license. It must be generated against
the container's pinned identity:

- Host name: **vivado-box**
- Host ID (Ethernet MAC): **02:42:AC:11:00:02**, OS: **Linux 64-bit**

At https://www.xilinx.com/getlicense choose the free **Vivado ML Standard
node-locked** certificate, enter the identity above, and AMD emails
`Xilinx.lic`. Save it anywhere in `fpga-work/`, then:

```sh
docker exec vivado cp /home/user/fpga-work/Xilinx.lic /home/user/.Xilinx/Xilinx.lic
```

The license lives on the `xilinx-config` volume and survives container
rebuilds. Verify:

```sh
docker exec vivado bash -lc 'source /opt/Xilinx/2026.1/Vivado/settings64.sh && vivado -mode batch -nolog -nojournal -source <(echo "puts [version -short]")'
```

## 5. Board files and constraints (one time)

Digilent board definitions (already installed on the volume; redo after a
`docker volume rm` only):

```sh
curl -fsSL -o /tmp/vb.zip https://github.com/Digilent/vivado-boards/archive/refs/heads/master.zip
unzip -q /tmp/vb.zip -d /tmp 'vivado-boards-master/new/board_files/arty-a7-100/*' 'vivado-boards-master/new/board_files/arty-s7-25/*'
docker cp /tmp/vivado-boards-master/new/board_files/arty-a7-100 vivado:/opt/Xilinx/2026.1/Vivado/data/boards/board_files/
docker cp /tmp/vivado-boards-master/new/board_files/arty-s7-25  vivado:/opt/Xilinx/2026.1/Vivado/data/boards/board_files/
```

Master XDC constraint files live in `fpga-work/constraints/`
(`Arty-A7-100-Master.xdc`, `Arty-S7-25-Master.xdc`, from
https://github.com/Digilent/digilent-xdc). Copy and uncomment pins per project.
For ready-made A7 examples see the `.xdc` files under `fpga-work/tests/` —
`01-leds/leds.xdc` (switches + LEDs) and `04-serial-input/uart_echo.xdc`
(clock + UART + LEDs).

## 6. Board basics (Arty A7-100T)

Facts that save real debugging time:

- **One USB cable does everything**: power, JTAG programming, and the serial
  console all run over the single micro-USB connection (an FT2232 chip with
  two channels). No wall adapter needed.
- **Programming is volatile.** Everything loaded with `openFPGALoader` goes
  into FPGA SRAM and is **lost at power-off**. After every unplug/power-up,
  reprogram your bitstream. (Persisting a design to the board's QSPI flash is
  possible but not needed for the class.)
- **At power-up the board runs Digilent's factory demo** from flash, chatting
  on the UART at 115200. Junk bytes on a 9600 console mean "factory demo",
  not "broken board".
- **Two serial devices appear on the Mac** for the one board:
  `/dev/cu.usbserial-XXXX0` is JTAG (leave it alone), `...XXXX1` is the UART
  console (see [Serial console](#serial-console)).
- **Buttons**: `PROG` makes the FPGA reload from flash (i.e. back to the
  factory demo — you'll have to reprogram). The red `RESET` is routed into
  our MicroBlaze designs and **restarts the running program** — handy to
  re-print output. `BTN0-3`, `SW0-3` are free for designs; the green LEDs
  `LD4-LD7` are `led[0..3]` in the example XDCs (LD0-3 are the RGB ones).
- **Only one program can hold each FTDI channel** — close `screen` before
  another tool needs the UART, and stop an `--xvc` bridge before using
  `openFPGALoader` directly.
- Wrong-board bitstreams are rejected quietly: `ID Error` + `Done 0` in the
  openFPGALoader status output means the `.bit` was built for another part.

## 7. What works, what doesn't

*Verified on hardware 2026-09-07; whole test suite run 2026-09-08.*

| Flow | Status |
|---|---|
| Verilog design → bitstream → program from macOS (path A) → LEDs/switches | ✅ works |
| Simulation (xsim testbenches, VCD waveforms) | ✅ works |
| Programming from *inside* the container over the XVC bridge (xsdb `fpga -f`) | ✅ works |
| Vivado Hardware Manager over XVC | ⚠️ works, but `open_hw_target` often fails the first time — retry it |
| **ILA / VIO on-chip debug over XVC** | ✅ **works** (verified 2026-09-08) — waveform capture and live probes |
| Vitis builds (platform + app, `vitis -s` Python API) | ✅ works |
| **Vitis IDE (the GUI)** | ❌ **does not start** — Electron/Chromium crashes under Rosetta |
| Running software on the MicroBlaze via `updatemem` boot-bitstream | ✅ works — the standard flow |
| Serial console from macOS (`screen`, 9600) | ✅ works, both directions — output *and* typed input |
| RESET button re-running the soft-CPU program | ✅ works |
| **Interactive debug of the MicroBlaze** (breakpoints, step, `dow`/`con`, Vitis GUI "Run/Debug on Hardware") | ❌ **does not work** |
| Booting a design from the board's QSPI flash | ❓ never attempted (test 08 — writes flash, needs a jumper) |

The one broken row has a single root cause: openFPGALoader's XVC server
mishandles the MicroBlaze Debug Module's transactions (journal §15). The
failure is narrow — **ILA and VIO work fine over the same bridge** (journal
§19), so on-chip debug as a whole is available; only the CPU debug module
fails. The Vitis GUI fails identically to the command line (same
`hw_server → XVC → MDM` path), so there is no GUI-only workaround.

Debug instead with `xil_printf` over the serial console, LEDs, and the RESET
button to re-run — which is what `tools/run-sw.sh` is built around. If
breakpoints ever become essential, the options are a different XVC server or a
Windows-ARM VM with native cable drivers.

---

## Daily workflow

### Start / stop

```sh
open -a Docker; open -a XQuartz
cd <path to this repo> && docker compose up -d
/opt/X11/bin/xhost +localhost              # once per XQuartz start
```

Stop with `docker compose stop` (or `down`; both keep the installation,
license, and coursework).

⚠️ **If your coursework folder is in iCloud/Proton Drive/Dropbox**, force the
files back onto local disk before a session — the container gets
`Input/output error` on cloud-evicted placeholders and builds hang with no
message (journal §17):

```sh
cd "/path/to/your/fpga-work" && find . -type f -exec cat {} + > /dev/null
```

### Launch the tools

```sh
docker exec -d vivado bash -lc 'source /opt/Xilinx/2026.1/Vivado/settings64.sh && vivado'
# Vitis has NO working GUI here (§7) — it is scripted instead:
docker exec vivado bash -lc 'source /opt/Xilinx/2026.1/Vitis/settings64.sh && vitis -s <script>.py'
```

First GUI start takes a minute or two (emulation). Work in
`~/fpga-work/projects/<name>` — those files appear in your coursework folder
on the Mac. Follow the class slides for the GUI flow (RTL project → add
sources → add XDC → target board → synth → impl → bitstream), and put final
`.bit` files in `~/fpga-work/bitstreams/` so they're easy to find from macOS.

### Program the board — path A (from macOS)

```sh
openFPGALoader --detect                                  # board visible?
openFPGALoader -b arty_a7_100t <path to .bit>            # Arty A7-100T
openFPGALoader -b arty_s7_25   <path to .bit>            # Arty S7-25
```

The `.bit` path is the `fpga-work/bitstreams/...` file in your coursework folder.

Path A is the default and covers the everyday loop. **Path B** below routes
JTAG through the container instead, and is needed only for ILA/VIO and
container-side tools. Neither path compiles anything — both just load a
bitstream Vivado already produced:

| Step | What it means | Who does it |
|---|---|---|
| **Compile** | Verilog / block design → `.bit` | **Vivado only**, always in the container |
| **Program** | send an existing `.bit` to the FPGA over JTAG | openFPGALoader on the Mac (path A) **or** xsdb / Hardware Manager over XVC (path B) |
| **Debug** | watch the design *while it runs* — ILA, VIO | Hardware Manager over XVC (path B only) |

### Path B — the XVC bridge (JTAG over TCP)

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

**It cannot do MicroBlaze breakpoint debugging** or Vitis "Run on Hardware"
(§7). Use the boot-bitstream flow below instead.

Three rules that save time:

- **`--port 2542` is required.** openFPGALoader's XVC default is 3721; Xilinx
  tools expect 2542.
- **The bridge is single-client.** One of Hardware Manager *or* xsdb at a
  time, path A can't be used while it runs, and `screen` must be closed.
- **Retry `open_hw_target`.** The first attempt often fails with "No devices
  detected" even though the bridge logged the connection; a retry usually
  works. If it keeps failing, clear stale servers:
  `docker exec vivado pkill -x hw_server`.

#### Using it (two terminals)

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

### Write and run C on the MicroBlaze (the Vitis IDE replacement)

**The Vitis IDE does not start here** — it is an Electron app and Chromium
crashes under emulation (§7, journal §20). That costs you the editor, the
project wizards and the build buttons. It does **not** cost you Vitis: the
compiler, the BSP generator and the linker are separate command-line tools
that work fine. Vivado's GUI is unaffected, so the class flow — design the
hardware in Vivado, write C for it in Vitis — is intact. Only the C gets
compiled by a script instead of a button.

Two scripts replace the IDE. Both live in `fpga-work/tools/`:

| Script | Replaces | When |
|---|---|---|
| `make-app.sh` | New Platform Project + New Application Project wizards | once per project |
| `run-sw.sh` | the Build and Run buttons | every code change |

#### 1. In Vivado (GUI, exactly as the class slides describe)

Build the block design, **Generate Bitstream**, then:

> **File → Export → Export Hardware… → tick "Include bitstream"**

Save the `.xsa` into the project directory. This is the handoff from hardware
to software, and forgetting it is the most common way to get stuck.

#### 2. Create the platform and application (once per project)

```sh
cd ~/…/fpga-work
./tools/make-app.sh -d projects/<yours>
```

This builds the BSP — the drivers and headers generated for *your* block
design, which is how `xil_printf()` knows how to reach your UART — then
creates the app from the `hello_world` template. Several minutes.

It also writes a starter `projects/<yours>/src/main.c`. **That is the file to
edit**: `run-sw.sh` copies it over the app's source on every build, so edits
made anywhere else are silently overwritten.

Useful flags: `-a <name>` for a second app against the same platform
(default `hello`), `-c <cpu>` if the processor is not `microblaze_0`,
`--help` for the rest.

#### 3. Edit, build, run (every change)

```sh
# edit projects/<yours>/src/main.c in any editor on the Mac
./tools/run-sw.sh -d projects/<yours>
screen /dev/cu.usbserial-*1 9600        # press RESET on the board
```

`run-sw.sh` recompiles the C, bakes the ELF into the bitstream with
`updatemem`, and programs the board. The baking step is needed because Vitis
"Run on Hardware" cannot work over the XVC bridge (§7): a bitstream configures
*hardware*, while your program lives in the CPU's BRAM, so the two are merged
before download. The program then starts at power-on and the RESET button
re-runs it.

Both scripts find things rather than assuming names, so they work with
GUI-made projects (`design_1_wrapper.bit`, `<Project>.runs/impl_1`) as well as
the scripted tests (`system_wrapper.bit`, `vivado/…`).

The underlying command, if you want to run it by hand:

```sh
updatemem -meminfo <impl>/<top>_wrapper.mmi -data <app>.elf \
  -bit <impl>/<top>_wrapper.bit -proc <design>_i/microblaze_0 -out boot.bit
```

Debug with `xil_printf` over the serial console, plus LEDs — there is no
breakpoint debugger (§7).

### Serial console

```sh
screen /dev/cu.usbserial-*1 9600           # exit: Ctrl-A then K, then y
```

- Use the **`cu.`** device — `screen` on the `tty.` variant exits after a few
  seconds, waiting for a carrier that never comes.
- Use the **`1`**-suffixed device — channel B is the UART, channel A is JTAG.
- **9600 baud** is the AXI Uartlite automation default (set
  `CONFIG.C_BAUDRATE {115200}` on the IP before building for faster). Junk
  characters mean a baud mismatch — usually the 115200 factory demo after a
  power-up.
- Output printed while JTAG is programming can arrive truncated; press RESET
  for a clean run.

### Batch builds (no GUI)

```sh
docker exec -w /home/user/fpga-work/tests/01-leds vivado bash -lc \
  'source /opt/Xilinx/2026.1/Vivado/settings64.sh && vivado -mode batch -source build.tcl'
```

Every test in `fpga-work/tests/` is a worked reference to copy from:
`01-leds/build.tcl` (plain Verilog), `03-mb-hello/build-hw.tcl` (a MicroBlaze
block design), `07-ila-vio/build.tcl` (debug cores).

### The test suite

Eight tests covering everything this environment can do, each with a README
saying what it proves and how to check it. Use them to verify the environment
after any change, and as working examples.

> **⚠️ Copy `tests/` and `tools/` into your coursework folder first — they do
> not run from this repo.**
>
> ```sh
> cp -R tests tools "/path/to/your/fpga-work/"   # the path from docker-compose.yml
> cd "/path/to/your/fpga-work/tests" && ./run-all.sh
> ```
>
> Only `fpga-work` is bind-mounted, so the container cannot see this repo at
> all. `tests/common/lib.sh` derives container paths by stripping the
> `fpga-work` root off host paths; run from anywhere else and every
> `docker exec` targets a path that does not exist. Copy **both** directories —
> `tools/run-sw.sh` sources `../tests/common/lib.sh`.

Status as of 2026-09-08: **01–07 pass, 08 (flash boot) not yet run.** Details
and per-test pass criteria are in `tests/README.md`.

The copy here is **sources only** — build outputs (`vivado/`, `vitis/`,
`.bit`, `.xsa`, `.ltx`, logs) are gitignored, so a fresh copy rebuilds from
scratch. Test 03 takes 20+ minutes the first time; the rest are minutes.

### Helper scripts (`tools/`)

Copied to `fpga-work/tools/` by the same command above:

| Script | What it is for |
|---|---|
| `make-app.sh` | create a Vitis platform + app for a project — replaces the IDE's wizards, run once per project |
| `make-app.py` | the part that runs inside the container (invoked by `make-app.sh`, not directly) |
| `run-sw.sh` | rebuild C → bake the ELF into the bitstream → program the board; the everyday loop |

`--help` on either shell script prints its usage. Full workflow:
[Write and run C on the MicroBlaze](#write-and-run-c-on-the-microblaze-the-vitis-ide-replacement).

**After pulling repo updates, re-copy both directories** — the copies in
`fpga-work/` are what actually run, and they do not update themselves:

```sh
cp -R tests tools "/path/to/your/fpga-work/"
```

---

## Troubleshooting

**`vitis -w …` opens nothing and exits 0** — expected: the Vitis IDE cannot
run here (§7, journal §20). Its launcher backgrounds the real binary with
output discarded, so the crash is invisible. Use the scripted flow instead:
[Write and run C on the MicroBlaze](#write-and-run-c-on-the-microblaze-the-vitis-ide-replacement).

**`cmake: command not found` when rebuilding an app** — `settings64.sh` does
not put `cmake` on PATH; it ships under `tps/lnx64/cmake-*/bin/`. `make` is
not a substitute (the generator is Ninja). Use `tools/run-sw.sh`, which
handles this — or if you are building by hand, note that `mb-size` lives in
`/opt/Xilinx/2026.1/gnu/microblaze/lin/bin` while `mb-gcc` is in
`/opt/Xilinx/2026.1/Vitis/gnu/microblaze/lin/bin` (journal §21).

**No window appears / "cannot open display"** — XQuartz must be running with
network clients allowed, and `xhost +localhost` must have been run *since
XQuartz last started*. Test with `docker exec vivado xeyes`. If it persists,
check XQuartz is listening: `lsof -iTCP:6000 -sTCP:LISTEN`.

**Everything is extremely slow** — Rosetta is probably off and you're on QEMU.
Run the `binfmt_misc` check from section 1; fix Docker's VMM setting (Apple
Virtualization framework + Rosetta checkbox) and restart Docker Desktop.

**Installer/Vivado process disappears** — OOM kill. Docker Desktop → Resources
→ Memory ≥ 10GB. Evidence: `docker exec vivado cat /sys/fs/cgroup/memory.events`
shows a nonzero `oom_kill`.

**Vivado crashes with `realloc(): invalid pointer` or at startup** — the udev
stub isn't in place (rebuild the image; both `LD_PRELOAD` and the
`libudev.so.1` symlink are set by the Dockerfile).

**"Valid license was not found"** — the container identity must still be
`vivado-box` / `02:42:AC:11:00:02` (don't edit those compose lines), and
`~/.Xilinx/Xilinx.lic` must exist (section 4).

**Board not detected on macOS** — `openFPGALoader --detect`; try another USB-C
cable/adapter (data cable, not charge-only), check the board's power LED, and
make sure no other program (screen, another bridge) holds the FTDI port.

**Hardware Manager can't open the XVC target** — the bridge must be running on
the Mac (`openFPGALoader -b <board> --xvc --port 2542`) *with the board
connected*, and the URL must be exactly `host.docker.internal:2542`. Stale
`hw_server`/`cs_server` processes inside the container also break later
sessions: `docker exec vivado pkill -9 hw_server; docker exec vivado pkill -9
cs_server`, restart the bridge, and prefer xsdb over Hardware Manager.

**Programming "succeeds" but the design doesn't run, status shows `ID Error`
and `Done 0`** — the bitstream was built for the wrong FPGA (e.g. an S7-25
`.bit` on an A7-100T board). Rebuild for your board's part.

**MicroBlaze design is dead / xsdb says "MicroBlaze is not being clocked"** —
that message also appears when the CPU is merely *held in reset*. Make sure
`proc_sys_reset/ext_reset_in` is connected to the board reset (see
`tests/03-mb-hello/build-hw.tcl`, which errors out if it is left dangling); a
dangling `ext_reset_in` holds the CPU in reset forever
while the clock is actually fine.

**A Vivado tool sits at 100% CPU forever with no output, next to 0-byte
`.log` files** — cloud storage has evicted your sources to placeholders. macOS
downloads those on demand, but Docker's bind mount does not: the container
gets `Input/output error` while the same file reads fine on the Mac, and tools
like `xvlog` spin instead of erroring. Re-read everything from the macOS side
to force it back down (`cd "…/fpga-work" && find . -type f -exec cat {} + >
/dev/null`), or better, move `fpga-work` off cloud storage onto local disk.
Full write-up in journal §17.

**Cloud sync makes "Edit conflict" copies during builds** — Vivado writes its
build tree faster than the sync can follow. Cosmetic for generated files
(delete the copies); for long builds, pause sync or keep heavy scratch
projects outside `fpga-work`.

**Wiping and starting over** — `docker compose down`, then
`docker volume rm vivado-vitis_xilinx-install vivado-vitis_xilinx-config`
(deletes the installation and license; coursework in the class folder is never
touched).
