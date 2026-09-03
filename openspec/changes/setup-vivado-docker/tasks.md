# Tasks: setup-vivado-docker

## 1. Host prerequisites

- [x] 1.1 Install Docker Desktop, enable "Use Rosetta for x86_64/amd64 emulation on Apple Silicon" (Settings → General), and verify `docker run --rm --platform linux/amd64 ubuntu:22.04 uname -m` prints `x86_64`
- [x] 1.2 Install XQuartz, enable "Allow connections from network clients", relog/restart XQuartz, and verify `xhost +localhost` succeeds in a terminal
- [x] 1.3 Install openFPGALoader via Homebrew and verify `openFPGALoader --detect` runs (board detection itself is task 7.3, no board needed yet)
- [x] 1.4 Create the coursework subdirectory `fpga-work/` (with `projects/`, `bitstreams/`, `constraints/` inside) under the Proton Drive class folder and verify it appears in Finder and syncs

## 2. Repository files

- [x] 2.1 Write `udev-stub.c` (no-op implementations of the `udev_*` symbols Vivado calls) and verify it compiles to a shared library with no undefined-symbol errors when linked at runtime (`LD_PRELOAD` smoke test against `/bin/true` in the container)
- [x] 2.2 Write the `Dockerfile` (ubuntu:22.04, X11 client libs, fontconfig + fonts, `en_US.UTF-8` locale, `libtinfo5`, non-root user, compiled udev stub) and verify `docker compose build` completes and the image is under ~3GB
- [x] 2.3 Write `docker-compose.yml` per design (platform amd64; pinned `hostname`/`mac_address` with a do-not-change comment; `DISPLAY` and `LD_PRELOAD` env; `./installer` read-only at `/installer`; coursework bind mount; `xilinx-install` and `xilinx-config` named volumes; `shm_size: 2gb`) and verify `docker compose config` validates

## 3. Container bring-up

- [x] 3.1 Start the container and verify identity: `uname -m` is `x86_64`, `hostname` is `vivado-box`, NIC MAC matches the compose value, `/installer` is read-only, coursework dir is writable, locale is `en_US.UTF-8`
- [x] 3.2 Run an X11 GUI smoke test (`xeyes` or `xclock`) from inside the container and verify the window renders on the macOS desktop

## 4. Vivado/Vitis installation (manual, GUI)

- [x] 4.1 Download the AMD Unified Installer 2026.1 Linux `.bin` (AMD account required) into the repo's `installer/` directory, confirm ≥80GB free disk on the Mac, and verify the installer launches with its GUI from `/installer` inside the container
- [x] 4.2 Complete the GUI install onto `/opt/Xilinx`: product **Vivado** (bundles Vitis), devices **Artix-7 + Spartan-7 only**, cable drivers unchecked (no USB in container); verify Vivado and Vitis binaries exist on the volume and `vivado -version` reports 2026.1
- [x] 4.3 Recreate the container (`docker compose down && up`) and verify Vivado still launches from the persistent volume — proves image/volume separation

## 5. License

- [x] 5.1 In Vivado License Manager, confirm View Host Information shows the pinned hostname and MAC, generate the free node-locked Vivado Basic Tier license on the AMD site against those values (OS: Linux, type: Ethernet MAC), load the emailed `.lic`, and verify View License Status shows valid entries
- [x] 5.2 Recreate the container and verify the license is still reported valid without any re-registration — proves identity pinning plus config persistence

## 6. Board files and constraints

- [x] 6.1 Install Digilent board files for arty-a7-100 and arty-s7-25 into the Vivado installation on the volume and verify both boards appear in Vivado's New Project board selector
- [x] 6.2 Download `Arty-A7-100-Master.xdc` and `Arty-S7-25-Master.xdc` into `fpga-work/constraints/` and verify they are readable from inside the container

## 7. End-to-end validation: Verilog path (class Unit 2)

- [x] 7.1 Create the Unit 2 example project in `fpga-work/projects/` (Example1.v + the board's XDC), run synthesis, implementation, and bitstream generation inside the container, and verify a `.bit` is produced and copied to `fpga-work/bitstreams/`
- [x] 7.2 Verify the Vivado project files are visible from Finder in the Proton Drive subdirectory (bind-mount round-trip)
- [ ] 7.3 With the Arty board on USB, program the bitstream from macOS with `openFPGALoader -b <board>` and verify the LED/switch behavior from the slides — this is the baseline programming path working end to end

## 8. XVC path (Hardware Manager + Vitis readiness)

- [ ] 8.1 Start `openFPGALoader --xvc` on the host, open the target from Vivado Hardware Manager inside the container via `open_hw_target -xvc_url host.docker.internal:2542`, and verify the device is detected and programmable from Hardware Manager
- [ ] 8.2 Verify the serial console: run a design/demo with UART output and confirm `screen /dev/tty.usbserial-* 115200` on macOS shows it

## 9. Vitis validation (the unverified risk — do early once Units require it)

- [x] 9.1 Build a minimal MicroBlaze (or class-provided) hardware platform in Vivado, export XSA, create a Vitis hello-world, and verify it compiles inside the container
- [ ] 9.2 Run the hello-world on the board through the XVC bridge from Vitis ("Run on Hardware") and verify its output on the macOS serial console; if Vitis fails under Rosetta, record the failure mode and escalate the Windows-ARM-VM fallback decision to the user

## 10. Documentation

- [x] 10.1 Write `README.md` covering prerequisites, one-time setup (container, XQuartz, GUI install selections, license flow, board files), and verify it matches what was actually done in tasks 1–6 (commands copy-pasteable)
- [ ] 10.2 Add the daily-workflow section (start/stop, file locations, synth→bitstream→program via both paths, Vitis run/debug, serial console) plus troubleshooting notes (XQuartz refusing connections, XVC bridge down, board undetected, Proton Drive sync churn) and verify a dry-run session succeeds using only README commands
