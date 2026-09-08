# Vivado/Vitis 2026.1 on Apple Silicon (Docker + Rosetta)

x86-64 Linux container that runs AMD **Vivado/Vitis 2026.1** on an Apple Silicon
Mac for CS3375 (Computer Architecture, TTU), targeting the **Arty S7-25** /
**Arty A7-100T** boards. Everything is defined by files in this repo — no
third-party images.

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
- **At power-up the board runs Digilent's factory demo** from flash. It
  chats on the UART at 115200 — if your serial console is at 9600 you'll see
  junk bytes. That junk means "factory demo", not "broken board".
- **Two serial devices appear on the Mac** for the one board:
  `/dev/cu.usbserial-XXXX0` is JTAG (leave it alone) and
  `/dev/cu.usbserial-XXXX1` is the UART console. Use the **`cu.`** devices —
  `screen` on the `tty.` variants exits after a few seconds (it waits for a
  carrier signal that never comes).
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

## 7. What works, what doesn't (verified on hardware 2026-09-07)

| Flow | Status |
|---|---|
| Verilog design → bitstream → program from macOS (path A) → LEDs/switches | ✅ works |
| Programming from *inside* the container over the XVC bridge (xsdb `fpga -f`) | ✅ works |
| Vivado Hardware Manager over XVC | ⚠️ works but flaky — retry/fall back to xsdb |
| Vitis builds (platform + app, `vitis -s` Python API) | ✅ works |
| Running software on the MicroBlaze via `updatemem` boot-bitstream | ✅ works — the standard flow |
| Serial console from macOS (`screen`, 9600) | ✅ works |
| RESET button re-running the soft-CPU program | ✅ works |
| **Interactive debug of the MicroBlaze** (breakpoints, step, `dow`/`con`, Vitis GUI "Run/Debug on Hardware") | ❌ **does not work** |

The one broken thing is a single root cause: openFPGALoader's XVC server
mishandles the MDM debug transactions (journal §15). The Vitis **GUI** fails
the same way as the command line — both sit on the identical
`hw_server → XVC → MDM` path; there is no GUI-only trick around it. Debug
workflow instead: `xil_printf` over the serial console + LEDs, and the RESET
button to re-run. If breakpoint debugging ever becomes essential, the options
are another XVC server implementation or a Windows-ARM VM with native tools.

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

### Launch the tools

```sh
docker exec -d vivado bash -lc 'source /opt/Xilinx/2026.1/Vivado/settings64.sh && vivado'
docker exec -d vivado bash -lc 'source /opt/Xilinx/2026.1/Vitis/settings64.sh  && vitis -w ~/fpga-work/projects/<name>/vitis'
```

First GUI start takes a minute or two (emulation). Work in
`~/fpga-work/projects/<name>` — those files appear in your coursework folder
on the Mac. Follow the class slides for the GUI flow (RTL project → add
sources → add XDC → target board → synth → impl → bitstream), and put final
`.bit` files in `~/fpga-work/bitstreams/` so they're easy to find from macOS.

### Program the board — path A (host, no container)

```sh
openFPGALoader --detect                                  # board visible?
openFPGALoader -b arty_s7_25  <path to .bit>             # Arty S7-25
openFPGALoader -b arty_a7_100t <path to .bit>            # Arty A7-100T
```

The `.bit` path is the `fpga-work/bitstreams/...` file in your coursework folder.

### Path B — the XVC bridge (JTAG over TCP): what it is and when to use it

**XVC = Xilinx Virtual Cable**, a protocol that carries JTAG over a TCP
socket. Instead of a physical cable plugged into the machine running the
tool, the tool opens a socket and something on the other end wiggles the
JTAG pins on its behalf.

It exists here because **the container has no USB.** Docker on macOS can't
pass through the board's FTDI chip, so Vivado inside the container has no
way to reach the Arty by itself. openFPGALoader plays the part of the
cable:

```
Vivado / xsdb / Vitis  --TCP:2542-->  openFPGALoader --xvc  --USB-->  Arty A7-100T
   (in container)                          (on the Mac)
```

`host.docker.internal` is how the container addresses your Mac.

First, a distinction worth being clear about — three different steps, and
each tool does exactly one of them:

| Step | Meaning | Who does it |
|---|---|---|
| **Compile** | Synthesis → implementation → generate a `.bit` from your Verilog/block design | **Vivado only** (GUI or batch Tcl), always in the container |
| **Program** | Send an already-built `.bit` to the FPGA over JTAG | openFPGALoader (path A) **or** xsdb `fpga -f` / Hardware Manager over XVC (path B) |
| **Debug** | Talk to the design *while it runs* — ILA waveforms, VIO, CPU breakpoints | Hardware Manager / Vitis, over XVC only |

openFPGALoader never compiles anything, and neither does `fpga -f`; both
take a filename because they load a bitstream Vivado already produced. Path
A and path B are the same operation by different routes.

**Use cases for the bridge:**

1. **On-chip debug — ILA and VIO. This is the real reason XVC exists.** An
   Integrated Logic Analyzer instantiated in your design records internal
   signals to on-chip memory; Hardware Manager reads them back over JTAG
   and draws waveforms. VIO gives you virtual buttons/LEDs to drive a
   running design from the GUI. openFPGALoader cannot do any of this — it
   only pushes bitstreams. If a lab says "add an ILA and capture the bus,"
   the bridge is the only path.
2. **Software debug on the MicroBlaze** — Vitis downloading an ELF,
   breakpoints, stepping. ❌ **Broken in this setup** (see the limitation
   note below); use the `updatemem` boot-bitstream flow instead.
3. **Programming from inside the container** — Hardware Manager's "Program
   Device", or xsdb `fpga -f`. Works, but redundant with path A; only worth
   it when you're already in the GUI and don't want to switch terminals.
4. **Scan-chain inspection** — confirming the device enumerates as
   `xc7a100t_0`, reading DONE status. Mostly diagnostic.

**When to skip it:** the everyday loop — edit Verilog, build in Vivado,
load the `.bit`, look at the LEDs — never needs XVC. Compile in the
container, program from the Mac with path A. Reach for the bridge only for
ILA/VIO, or when testing the Vitis hardware flow.

The bridge is **single-client**: only one of Hardware Manager *or* xsdb can
hold it at a time, and neither can be connected while you use path A.

#### Using the bridge

It takes **two terminals**:

**Terminal 1 (Mac): start the bridge and leave it running.** This is the
"virtual cable" — the container connects to it. `--port` is required
(openFPGALoader's XVC default is 3721, but our tools expect 2542):

```sh
openFPGALoader -b arty_a7_100t --xvc --port 2542         # Ctrl-C quits
```

**Terminal 2: open the xsdb console inside the container** (xsdb is the
JTAG tool that ships with Vitis; 2026.1 disabled xsct but xsdb works):

```sh
docker exec -it vivado bash -lc 'source /opt/Xilinx/2026.1/Vitis/settings64.sh && xsdb'
```

You now have an `xsdb%` prompt. Type these **at that prompt**, one at a
time:

```tcl
connect -xvc-url tcp:host.docker.internal:2542    ;# reach the bridge on the Mac
targets                                           ;# list what's on the JTAG chain
targets -set -filter {name =~ "xc7a*"}            ;# select the FPGA
fpga -f ~/fpga-work/bitstreams/<file>.bit         ;# program it
exit
```

`targets` should list the `xc7a100t` (and, for MicroBlaze designs, the MDM
and CPU). If `connect` fails, the bridge in terminal 1 isn't running or
died — restart it.

**Known limitation:** MicroBlaze *debug* operations (`stop`, `dow`, `con`,
breakpoints — i.e. Vitis "Run/Debug on Hardware") do **not** work through
openFPGALoader's XVC server; they fail with a bogus "MicroBlaze is not
being clocked" even when the CPU is running fine (see journal §15). Vivado
Hardware Manager over the bridge is also flaky ("No devices detected" —
fall back to xsdb).

**To run software on the MicroBlaze, bake the ELF into the bitstream**
(this is the standard flow for this setup — runs at power-on, RESET button
re-runs it):

```sh
updatemem -meminfo <impl_dir>/system_wrapper.mmi -data hello.elf \
  -bit <impl_dir>/system_wrapper.bit -proc system_i/microblaze_0 -out boot.bit
```

### Serial console (UART from the soft CPU)

```sh
screen /dev/cu.usbserial-*1 9600           # exit: Ctrl-A then K, then y
```

Use the **`cu.`** device (the `tty.` variant exits after a few seconds) and
the `1`-suffixed one (channel B = UART; channel A is JTAG). The
automation-created AXI Uartlite defaults to **9600 baud** (set
`CONFIG.C_BAUDRATE {115200}` on it before building if you want faster).
Junk bytes = a baud mismatch — usually the factory demo (115200) after a
power-up. Output printed while JTAG is busy programming can arrive
truncated — press the board's RESET button to re-run the program and get a
clean line.

### Batch builds (optional, no GUI)

Every test in `fpga-work/tests/` is a worked reference you can copy from —
`01-leds/build.tcl` for a plain Verilog design, `03-mb-hello/build-hw.tcl`
for a MicroBlaze platform, `07-ila-vio/build.tcl` for debug cores:

```sh
docker exec -w /home/user/fpga-work/tests/01-leds vivado bash -lc \
  'source /opt/Xilinx/2026.1/Vivado/settings64.sh && vivado -mode batch -source build.tcl'
```

### The test suite

`fpga-work/tests/` holds eight tests covering everything this environment can
do, each with its own README saying what it proves and how to check it. Run
`tests/run-all.sh`, or see `tests/README.md` for the status table. Use it to
confirm the environment after any change, and as a source of working examples.

### Software loop for your own MicroBlaze projects

```sh
fpga-work/tools/run-sw.sh -d projects/<yours>      # rebuild ELF → bake → flash
```

---

## Troubleshooting

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
`build-hw-a7.tcl`); a dangling `ext_reset_in` holds the CPU in reset forever
while the clock is actually fine.

**Cloud sync (Proton Drive, iCloud, …) makes "Edit conflict" copies during
builds** — if your coursework folder is inside a synced directory, Vivado
writes its build tree fast enough to race the sync. Harmless for generated
files (delete the copies), but for long builds consider pausing sync, or keep
heavy scratch projects outside `fpga-work` and copy results in.

**Wiping and starting over** — `docker compose down`, then
`docker volume rm vivado-vitis_xilinx-install vivado-vitis_xilinx-config`
(deletes the installation and license; coursework in the class folder is never
touched).
