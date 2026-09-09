# Design: setup-vivado-docker

## Context

See `proposal.md` — Why. Constraints that shape the approach:

- Apple Silicon (M5) cannot run Vivado natively; Rosetta-translated x86-64 Linux containers are the fastest emulation path available.
- Docker on macOS has **no USB passthrough** — board access must happen host-side.
- Vivado 2026.1 uses a **node-locked license** bound to Host Name + NIC MAC (per the class slides).
- Known Rosetta bug: Vivado crashes in `udev_enumerate_scan_devices()` (glibc allocator abort) unless udev calls are stubbed out.
- The class uses the **GUI installer flow** (slides show Windows; the Linux installer has identical screens), selecting product "Vivado" (which bundles Vitis) and only Artix-7 + Spartan-7 devices: ~20GB download, ~70GB peak, ~51GB final.
- User preferences: installer `.bin` lives in the repo's `installer/` directory (self-contained, no personal folders mounted); coursework output goes to a subdirectory of the Proton Drive class folder; no dependency on third-party images.

## Goals / Non-Goals

**Goals:**
- Reproducible, understandable environment fully defined by files in this repo (`Dockerfile`, `docker-compose.yml`, stub source, `README.md`).
- Manual GUI install onto persistent storage; container and image remain disposable.
- Full course loop supported: Verilog → bitstream → board, C → ELF → soft CPU, UART console.

**Non-Goals:**
- Automating the Vivado installation (deliberately manual/GUI to mirror the class and keep transparency).
- ILA/ChipScope debugging (assumed to work over XVC if ever needed, but not planned for validation in this change — it was in fact validated later; see Outcomes).
- Windows VM fallback (documented as an option in exploration; only pursued if Vitis proves broken under Rosetta).
- Supporting Intel Macs or Linux hosts.

## Decisions

1. **Container runtime: Docker Desktop with Rosetta enabled** ("Use Rosetta for x86_64/amd64 emulation on Apple Silicon" in Settings → General) — the user's stated choice. The README documents Docker Desktop only. The compose file is runtime-agnostic, so Rosetta-capable alternatives (OrbStack, Colima) would work unchanged if ever wanted, but they are out of scope.

2. **Base image `ubuntu:22.04`, thin image + fat volume.** 22.04 still ships `libtinfo5`, which Vivado needs and 24.04 dropped. The image contains only X11 client libs, fontconfig/fonts, `en_US.UTF-8` locale, `libtinfo5`, misc tools, a non-root user, and the compiled udev stub (~2GB). Vivado installs to named volume `xilinx-install` mounted at `/opt/Xilinx`; `~/.Xilinx` (license + prefs) on named volume `xilinx-config`. Rationale: no 100GB image builds, container fully disposable, install survives everything short of `docker volume rm`.

3. **GUI via XQuartz over TCP** (`DISPLAY=host.docker.internal:0`, "Allow connections from network clients" + `xhost +localhost`). Alternative considered: VNC server in-container (ichi4096's approach) — rejected as an extra moving part; XQuartz gives native-feeling windows. VNC remains a documented fallback if XQuartz rendering misbehaves.

4. **udev stub compiled in the Dockerfile** from a small C file in the repo (no-op implementations of the `udev_*` symbols Vivado touches), applied two ways: `LD_PRELOAD` in the compose environment, **and** the system `/lib/x86_64-linux-gnu/libudev.so.1` symlinked to the stub. The second is required because FlexLM license checkout (`libXil_lmgr11.so`) loads libudev via `dlopen`/`dlsym`, which bypasses LD_PRELOAD interposition — discovered during implementation when licensed startup crashed while `vivado -version` worked. Rationale: the known Rosetta crash; building it ourselves keeps the fix inspectable, per the "no third-party dependency" goal.

5. **License identity pinned in compose**: `hostname: vivado-box`, `mac_address: 02:42:ac:11:00:02`. The license is generated once against these values (Linux OS selection, Ethernet MAC type). Values are arbitrary but must never change after license generation — a comment in the compose file says so.

6. **Mounts:**
   - `./installer` (in this repo) → `/installer`, **read-only** (installer `.bin` source; relative path keeps the compose file self-contained and avoids mounting any personal folder). Directory is disposable after install to reclaim ~20GB.
   - `/Users/ezequiel/Library/CloudStorage/ProtonDrive-ezequielbuckmartinez@proton.me-folder/TTU/Term 8/Computer Architecture/fpga-work` → `/home/user/fpga-work`, read-write. Subdirectory name `fpga-work` (assumption recorded in proposal; trivially renameable in compose). Created on the host before first `up` so Docker doesn't create it root-owned.
   - Named volumes as in Decision 2.

7. **Coursework layout inside `fpga-work/`**: `projects/` for Vivado/Vitis workspaces, `bitstreams/` as the exchange point for host-side programming, `constraints/` for the Digilent XDC masters. Keeps a single bind mount while separating generated trees from files the user cares about. Trade-off (accepted): Vivado build churn inside a Proton Drive-synced folder causes sync traffic; mitigations documented in README (pause sync during long builds, or `.gitignore`-style exclusion if Proton Drive supports it). The user explicitly wants coursework in the cloud folder; durability beats sync noise.

8. **Board access, two paths:**
   - *Baseline:* `openFPGALoader -b arty_s7_25` / `-b arty_a7_100t` on macOS against `.bit` files in `fpga-work/bitstreams/`. Zero container involvement.
   - *Full:* `openFPGALoader --xvc` as host-side JTAG bridge on port 2542; inside the container, `open_hw_target -xvc_url host.docker.internal:2542` (Vivado) and the equivalent hw_server setup for Vitis "Run on Hardware". Needed once the course reaches Vitis software units. No compose `ports:` entry — the connection is outbound from the container. *(Two corrections from implementation: XSCT was removed in 2026.1 — `xsdb` and the `vitis -s` Python API replace it — and "Run on Hardware" does not work over this bridge at all; see Outcomes.)*
   - *Serial:* `screen /dev/cu.usbserial-*1 9600` on macOS (documented; no extra software). *(Planned as `tty.`/115200; both were wrong — the `tty.` device waits for a carrier and exits, and the AXI UartLite automation defaults to 9600. 115200 is the QSPI factory demo.)*

9. **Install both Artix-7 and Spartan-7 device support** even though the user's board is initially one of them — pairing with an A7-100T partner is expected mid-course.

## Risks / Trade-offs

- [Vitis 2026.1 under Rosetta is unverified by any public report] → Milestone ordering: validate the full Verilog path (Unit 2 LED demo) first, then a Vitis hello-world as its own task; if Vitis fails, fall back to a Windows 11 ARM VM (VMware Fusion, free) for software units only — bitstreams and coursework files remain usable.
- [XQuartz rendering glitches with Vivado's Java UI] → Documented VNC fallback (Decision 3); `_JAVA_AWT_WM_NONREPARENTING=1` env var noted in troubleshooting.
- [Proton Drive sync churn during builds] → Mitigations in Decision 7; worst case, move `projects/` to a named volume and keep only sources/bitstreams in the cloud folder (would be a follow-up change).
- [~70GB peak disk during install] → README instructs checking free space first; installer download can be deleted after install.
- [macOS updates breaking Rosetta-in-VM (seen historically on macOS 14)] → Environment is fully file-defined; pin Docker Desktop/macOS versions that work, and the community projects serve as a reference for fixes.
- [openFPGALoader XVC + hw_server interop for Vitis ELF download] → If flaky, alternative bridges exist (xvcd, xc3sprog); validated by an explicit task before the course depends on it.

## Migration Plan

Greenfield — nothing to migrate. Rollback = `docker compose down`, delete named volumes, delete `fpga-work/` subdirectory; the Mac is otherwise untouched (Homebrew/XQuartz uninstallable normally).

## Open Questions

- Exact `hw_server`/XSCT invocation Vitis 2026.1 wants for an XVC-only target (determined during the Vitis validation task; does not change the architecture).
- Whether Proton Drive offers per-folder sync exclusion (affects only the mitigation wording in the README).

## Outcomes (2026-09-08)

How the risks and open questions above actually resolved, once the board was
in hand and the `tests/` suite had been run end to end. Recorded here so the
design doc is not read as a prediction that was never checked.

**Risk: Vitis 2026.1 under Rosetta is unverified** → *Vitis builds fine*
(platform + application, via the `vitis -s` Python API; XSCT is gone in 2026.1).
Only *running* from Vitis fails, and for an unrelated reason — see the next
item. The Windows-ARM-VM fallback was **not** taken.

**Risk: openFPGALoader XVC + hw_server interop for Vitis ELF download** →
*This is the one thing that broke.* Every MicroBlaze Debug Module operation
(`stop`, `dow`, `con`) fails with `Cannot stop MicroBlaze. MicroBlaze is not
being clocked` while the CPU is provably running — openFPGALoader v1.1.1's XVC
server mishandles the longer BSCAN/USER2 shifts the MDM needs. Bitstream
programming and device enumeration over the same bridge are unaffected. The
mitigation is not a different bridge but a different mechanism: `updatemem`
bakes the ELF into the bitstream, so the program runs from power-on with no MDM
traffic at all. Breakpoint debugging is given up; `xil_printf` over serial plus
LEDs replaces it. Kept under test as a regression (test 06, inverted exit
codes) so a fixed openFPGALoader would be noticed. Journal §15, §18.

**Non-goal that became a validated capability: ILA/VIO.** Listed above as out
of scope, but it was the biggest open question once MDM debug failed, so it was
tested. **Both work over the same bridge** — 1024 ILA samples captured cleanly,
VIO reading switches live and driving LEDs (journal §19, test 07). This is what
keeps the MDM limitation tolerable: on-chip debug as a whole is available; only
the CPU debug module is unreachable.

**Risk: Proton Drive sync churn during builds** → Worse than anticipated. The
predicted problem (duplicate "Edit conflict" files) is cosmetic. The real one
is *file eviction*: macOS turns synced files into dataless placeholders and
materializes them on demand, but a read through Docker's bind mount does not
trigger that — the container gets `EIO` while the Mac reads the same file
fine, and `xvlog` spins on a core indefinitely instead of erroring. Mitigation
documented (re-read from the macOS side before a session); the real fix is to
move `fpga-work` off cloud storage. Journal §17.

**Open question: the exact hw_server/XSCT invocation Vitis wants for an
XVC-only target** → Moot. XSCT no longer exists in 2026.1, and the flow it
would have served does not work over this bridge. `xsdb` handles the operations
that do work (`connect -xvc-url`, `targets`, `fpga -f`).

**Open question: whether Proton Drive offers per-folder sync exclusion** → Not
pursued; superseded by the eviction problem above, for which the recommendation
is to move the folder off cloud storage entirely rather than tune the sync.

**Out of scope, not validated:** flash boot. A test for it (08) ships with the
suite, but the course does not require booting without a computer attached, and
the test writes persistent QSPI flash and needs the JP1 jumper fitted by hand —
so it is not a deliverable of this change. Validating it would be its own
change. The Arty S7-25 is likewise unverified on hardware; its scripts carry
the same fixes as the A7 ones.
