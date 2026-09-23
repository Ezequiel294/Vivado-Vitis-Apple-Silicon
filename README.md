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
| **Vitis IDE (the GUI)** | ❌ **does not start** — Electron/Chromium crashes under emulation (Rosetta *and* QEMU alike) |
| Running software on the MicroBlaze via `updatemem` boot-bitstream | ✅ works — the standard flow |
| Benchmarking (Dhrystone from the Vitis Examples library, `-O3`, code size) | ✅ works — scripted, no IDE (test 09) |
| Serial console from macOS (`screen`, 9600) | ✅ works, both directions — output *and* typed input |
| RESET button re-running the soft-CPU program | ✅ works |
| **Interactive debug of the MicroBlaze** (breakpoints, step, `dow`/`con`, Vitis GUI "Run/Debug on Hardware") | ❌ **does not work** |
| Booting a design from the board's QSPI flash | ❓ never attempted (test 08 — writes flash, needs a jumper) |

In practice this costs you one thing: **there is no breakpoint debugger.**
Debug with `xil_printf` over the serial console, LEDs, and the RESET button to
re-run — which is what `tools/run-sw.sh` is built around. Everything else on
the list has a working path, and the steps below use it.

The root cause, and what the alternatives would be, are in
[reference.md](reference.md).

---

## Daily workflow

*This section is the steps. For what the tools are actually doing, which
alternative paths exist, and why some things are done the way they are, see
[reference.md](reference.md).*

### 1. Start a session

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
message:

```sh
cd "/path/to/your/fpga-work" && find . -type f -exec cat {} + > /dev/null
```

### 2. Build hardware in Vivado

```sh
docker exec -d vivado bash -lc 'source /opt/Xilinx/2026.1/Vivado/settings64.sh && vivado'
```

First GUI start takes a minute or two (emulation). Work in
`~/fpga-work/projects/<name>` — those files appear in your coursework folder on
the Mac. Follow the class slides for the GUI flow (RTL project → add sources →
add XDC → target board → synth → impl → bitstream), and put final `.bit` files
in `~/fpga-work/bitstreams/` so they're easy to find from macOS.

> Vitis has **no working GUI** here. You do not need it — the steps below
> replace it. See [reference.md](reference.md) for why.

### 3. Program the board

```sh
openFPGALoader --detect                                  # board visible?
openFPGALoader -b arty_a7_100t <path to .bit>            # Arty A7-100T
openFPGALoader -b arty_s7_25   <path to .bit>            # Arty S7-25
```

The `.bit` path is the `fpga-work/bitstreams/...` file in your coursework
folder. This is all you need for plain Verilog designs.

*(There is a second path that routes JTAG through the container, needed only
for ILA/VIO on-chip debug — see [reference.md](reference.md).)*

### 4. Write and run C on the MicroBlaze

**Step 1 — in Vivado**, build the block design, **Generate Bitstream**, then:

> **File → Export → Export Hardware… → tick "Include bitstream"**

Save the `.xsa` into the project directory. Forgetting this is the most common
way to get stuck.

**Step 2 — create the app** (once per project):

```sh
cd ~/…/fpga-work
./tools/make-app.sh -d projects/<yours>
```

Several minutes. It writes a starter `projects/<yours>/src/main.c` — **that is
the file to edit.**

**Step 3 — edit, build, run** (every change):

```sh
# edit projects/<yours>/src/main.c in any editor on the Mac
./tools/run-sw.sh -d projects/<yours>
./tools/serial.sh                          # then press RESET on the board
```

#### Using a Vitis example instead of your own code

Some assignments hand you the program (Dhrystone, for instance). Name it with
`-t` instead of writing a `main.c`:

```sh
./tools/make-app.sh -d projects/<yours> -a dhry -t dhrystone
```

#### Compiler flags an assignment asks for

"Compile it with `-O3` and no debug" becomes:

```sh
./tools/make-app.sh -d projects/<yours> -a dhry -t dhrystone -O -O3 -g none
```

`-O` takes `-O0`/`-O1`/`-O2`/`-O3`/`-Os`; `-g` takes `-g1`/`-g2`/`-g3` or
`none`. Run it again on an existing app to change the setting and rebuild.

#### Other flags

`-a <name>` for a second app against the same platform (default `hello`),
`-c <cpu>` if the processor is not `microblaze_0`. `--help` prints the rest.

### Serial console

```sh
./tools/serial.sh                          # watch, log to serial.log, Ctrl-C to stop
./tools/serial.sh -o dhry.log -t 60        # 60 seconds, to a log you name
./tools/serial.sh -u "run successfully"    # stop when that text appears
```

`serial.sh` only listens. When the program expects you to **type**, use
`screen` instead:

```sh
screen /dev/cu.usbserial-*1 9600           # exit: Ctrl-A + K, then y
```

- Use the **`cu.`** device — `screen` on the `tty.` variant exits after a few
  seconds, waiting for a carrier that never comes.
- Use the **`1`**-suffixed device — channel B is the UART, channel A is JTAG.
- **9600 baud.** Junk characters mean a baud mismatch — usually the 115200
  factory demo after a power-up.
- Output printed while JTAG is programming can arrive truncated; press RESET
  for a clean run.
- If `screen` stair-steps the output down the screen, that is the program's
  line endings, not a fault — use `serial.sh`.

### The test suite

Nine tests that verify everything this environment can do, each with a README
saying what it proves and how to check it.

> **⚠️ Copy `tests/` and `tools/` into your coursework folder first — they do
> not run from this repo.**
>
> ```sh
> cp -R tests tools "/path/to/your/fpga-work/"   # the path from docker-compose.yml
> cd "/path/to/your/fpga-work/tests" && ./run-all.sh
> ```
>
> Re-copy after pulling repo updates — the copies in `fpga-work/` are what
> actually run.

Status: **01–07 and 09 pass**; 08 (flash boot) not yet run. Per-test detail is
in `tests/README.md`; why two tests are excluded from `run-all.sh` is in
[reference.md](reference.md).

### Helper scripts (`tools/`)

| Script | What it is for |
|---|---|
| `make-app.sh` | create a Vitis platform + app for a project — run once per project |
| `run-sw.sh` | rebuild C → bake into the bitstream → program the board; the everyday loop |
| `serial.sh` | watch the serial console and save a transcript |
| `make-app.py` | runs inside the container (invoked by `make-app.sh`, not directly) |

`--help` on any of the shell scripts prints its usage.

## Troubleshooting

**`vitis -w …` opens nothing and exits 0** — expected: the Vitis IDE cannot
run here (§7, journal §20). Its launcher backgrounds the real binary with
output discarded, so the crash is invisible. Use the scripted flow instead:
[Write and run C on the MicroBlaze](#4-write-and-run-c-on-the-microblaze).

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
