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
| Coursework (projects, bitstreams, XDCs) | `…/TTU/Term 8/Computer Architecture/fpga-work` ↔ `~/fpga-work` in the container |
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

```sh
cd ~/Containers/vivado-vitis
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
https://github.com/Digilent/digilent-xdc). Copy and uncomment pins per project;
`Arty-S7-25-Master-example1.xdc` is the Unit 2 variant (switches + LEDs).

---

## Daily workflow

### Start / stop

```sh
open -a Docker; open -a XQuartz
cd ~/Containers/vivado-vitis && docker compose up -d
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
`~/fpga-work/projects/<name>` — those files appear in the Proton Drive class
folder on the Mac. Follow the class slides for the GUI flow (RTL project → add
sources → add XDC → target board → synth → impl → bitstream), and put final
`.bit` files in `~/fpga-work/bitstreams/` so they're easy to find from macOS.

### Program the board — path A (host, no container)

```sh
openFPGALoader --detect                                  # board visible?
openFPGALoader -b arty_s7_25  <path to .bit>             # Arty S7-25
openFPGALoader -b arty_a7_100t <path to .bit>            # Arty A7-100T
```

The `.bit` path is the `fpga-work/bitstreams/...` file in the class folder.

### Program/debug — path B (XVC: Hardware Manager & Vitis)

Vivado Hardware Manager and Vitis "Run on Hardware" need JTAG. USB never
reaches the container, so run a JTAG-over-TCP bridge **on the Mac**:

```sh
openFPGALoader -b arty_s7_25 --xvc                       # serves port 2542, leave running
```

Then inside Vivado (Hardware Manager → Tcl console):

```tcl
open_hw_manager
connect_hw_server
open_hw_target -xvc_url host.docker.internal:2542
```

The FPGA appears as a device and can be programmed/debugged normally. Vitis
uses the same running bridge for downloading ELFs to the soft CPU.

### Serial console (UART from the soft CPU)

```sh
screen /dev/tty.usbserial-*1 115200        # exit: Ctrl-A then K, then y
```

### Batch builds (optional, no GUI)

`fpga-work/projects/example1/build.tcl` (Unit 2 LED/switch design) and
`fpga-work/projects/mb-hello/build-hw.tcl` (MicroBlaze + UART platform → XSA)
are working references:

```sh
docker exec vivado bash -lc 'source /opt/Xilinx/2026.1/Vivado/settings64.sh && cd ~/fpga-work/projects/example1 && vivado -mode batch -source build.tcl'
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
the Mac (`openFPGALoader -b <board> --xvc`) *with the board connected*, and the
URL must be exactly `host.docker.internal:2542`.

**Proton Drive makes "Edit conflict" copies during builds** — Vivado writes its
build tree fast enough to race the sync. Harmless for generated files (delete
the copies), but for long builds consider pausing Proton Drive sync, or keep
heavy scratch projects outside `fpga-work` and copy results in.

**Wiping and starting over** — `docker compose down`, then
`docker volume rm vivado-vitis_xilinx-install vivado-vitis_xilinx-config`
(deletes the installation and license; coursework in the class folder is never
touched).
