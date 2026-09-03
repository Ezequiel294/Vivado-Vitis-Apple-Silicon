# Proposal: setup-vivado-docker

## Why

CS3375 (Computer Architecture, TTU) requires AMD Vivado/Vitis 2026.1 — Windows/Linux x86-64 only software — to design a soft CPU in Verilog and run C programs on it, targeting Arty A7-100T / Arty S7-25 FPGA boards. The only available machine is an Apple Silicon MacBook Air (M5, 16GB, 512GB), so the toolchain must run in an x86-64 Linux Docker container under Rosetta emulation, built manually (no dependency on third-party images like yokeTH/vivado-mac) so every piece is understood and fixable.

## What Changes

- New Docker-based development environment in this repo (`~/Containers/vivado-vitis`): a thin Ubuntu 22.04 x86-64 image (X11 libs, fonts, locale, libtinfo5, udev LD_PRELOAD stub) plus a `docker-compose.yml` that runs it under Rosetta.
- Vivado/Vitis 2026.1 is installed **manually via AMD's Linux GUI installer** (mirroring the class slides) onto a persistent named volume — never baked into the image. The installer `.bin` is kept in the repo's `installer/` directory and provided to the container via a read-only bind mount.
- GUI display via XQuartz on the macOS host (`DISPLAY=host.docker.internal:0`).
- License stability: container runs with pinned `hostname` and `mac_address` so the node-locked Vivado Basic Tier license (tied to Host Name + NIC MAC per the class slides) stays valid across container rebuilds; license/config persisted on a named volume.
- Board access from the host: `openFPGALoader` (Homebrew) as an XVC (Xilinx Virtual Cable) JTAG bridge that Vivado/Vitis inside the container reaches over TCP, plus `screen` on macOS for the board's USB UART console.
- Coursework output is bind-mounted to a dedicated subdirectory of the user's Proton Drive class folder (`.../TTU/Term 8/Computer Architecture/<subdir>`), keeping generated files separate from syllabus/slides in the class-folder root.
- A `README.md` in this repo with complete instructions: host prerequisites, one-time install walkthrough (container, XQuartz, Vivado installer, license), and day-to-day usage (start environment, synthesize, program board, run/debug Vitis programs, serial console).

## Capabilities

### New Capabilities

- `container-environment`: The Dockerfile + docker-compose service that provides an x86-64 Ubuntu environment able to run the AMD GUI installer and Vivado/Vitis under Rosetta, with persistent install/config volumes, pinned license identity, and the coursework/installer mounts.
- `board-programming`: Host-side connectivity to the Arty board — XVC JTAG bridge reachable from tools inside the container, direct bitstream programming fallback, and USB UART serial console.
- `usage-documentation`: The README covering prerequisites, installation, and daily workflow end-to-end.

### Modified Capabilities

_None — this is a greenfield repo._

## Impact

- New files in this repo: `Dockerfile`, `docker-compose.yml`, `udev-stub.c` (or equivalent), helper scripts as needed, `README.md`.
- Host software required: Docker Desktop with Rosetta enabled, XQuartz, Homebrew `openfpgaloader`.
- Disk: ~70GB free during Vivado install, ~51GB persistent afterward (Docker named volume), well within the 512GB Mac.
- External: AMD account for installer/license; Digilent board files and XDC constraints downloaded during setup.
- User directories touched: only `.../TTU/Term 8/Computer Architecture/<subdir>` (read-write, coursework output); the installer lives in the repo's own `installer/` directory. Assumption to confirm at design time: subdirectory name defaults to `fpga-work`.
