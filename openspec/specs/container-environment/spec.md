# container-environment Specification

## Purpose
Provides an x86-64 Linux environment on the Apple Silicon Mac in which AMD Vivado/Vitis 2026.1 can be installed via its GUI installer and used for CS3375 coursework, with installation, license, and coursework data surviving container rebuilds.

## Requirements

### Requirement: x86-64 container runs GUI applications on the macOS display

The environment SHALL run an x86-64 Ubuntu userland on the Apple Silicon host
(via Rosetta-accelerated emulation) and SHALL display GUI applications that
use X11 or a native widget toolkit (Motif, Java/SWT) launched inside the
container on the macOS host's screen via XQuartz.

Applications built on an embedded Chromium runtime (Electron) SHALL NOT be
expected to run. This is a limitation of user-mode x86-64 emulation itself,
not of the display path or of the emulator chosen, and the environment
therefore makes no claim about them.

#### Scenario: GUI smoke test
- **WHEN** the container is started with `docker compose up` and an X11 application (e.g. `xeyes` or the AMD installer) is launched inside it
- **THEN** its window appears on the macOS desktop and reports `x86_64` architecture from `uname -m` inside the container

#### Scenario: Vivado GUI usable
- **WHEN** Vivado is launched inside the container after installation
- **THEN** the Vivado IDE opens on the macOS display and does not crash at the license/device-enumeration stage (the known Rosetta `udev_enumerate_scan_devices` crash MUST be prevented)

#### Scenario: Electron-based IDE does not run
- **WHEN** the Vitis IDE (an Electron application) is launched inside the container
- **THEN** its Chromium process aborts and no window appears, and this outcome is unchanged by the display target (XQuartz or an in-container X server), by disabling GPU and software rasterization, by running without the Chromium sandbox, or by substituting QEMU for Rosetta
- **AND** the documentation SHALL record this as a known non-capability together with the supported alternative, rather than presenting the IDE as available

### Requirement: Vivado installation persists outside the image

The Vivado/Vitis installation (~51GB) SHALL live on a persistent Docker volume, not in the image, so that the image stays small and the container can be destroyed and recreated without reinstalling. The AMD web installer binary SHALL be provided to the container from the repository's `installer/` directory via a read-only mount.

#### Scenario: Container rebuild preserves installation
- **WHEN** the container is removed and recreated from the compose file after Vivado was installed
- **THEN** Vivado launches from the persistent volume without reinstallation

#### Scenario: Installer available read-only
- **WHEN** the user places the AMD unified installer `.bin` in the repo's `installer/` directory and starts the container
- **THEN** the installer is visible and executable inside the container, and the container cannot modify files in the mounted installer location

### Requirement: License identity is stable across container lifecycles

The container SHALL present a fixed hostname and a fixed MAC address on every run, so the node-locked Vivado Basic Tier license (bound to Host Name + NIC MAC) generated once remains valid indefinitely. License files and Vivado user configuration SHALL persist across container rebuilds.

#### Scenario: Identity survives recreation
- **WHEN** the container is destroyed and recreated
- **THEN** `hostname` and the NIC MAC address inside the container are identical to the values the license was generated against, and Vivado's License Manager reports a valid license without re-registration

### Requirement: The simulator runs under emulation

Vivado's simulator (xsim) SHALL compile, elaborate and run Verilog testbenches inside the container and SHALL produce waveform output, so that designs can be verified without the board attached.

#### Scenario: Self-checking testbench in batch mode
- **WHEN** a testbench is run through `xvlog`/`xelab`/`xsim` in batch mode inside the container
- **THEN** the simulation runs to completion, the testbench's own pass/fail verdict appears on stdout, and a waveform file is written that can be opened in the Vivado GUI

### Requirement: Coursework files are stored in the class directory

Project sources and build outputs the user works on SHALL be read and written through a bind mount to a dedicated subdirectory of the class folder `/Users/ezequiel/Library/CloudStorage/ProtonDrive-ezequielbuckmartinez@proton.me-folder/TTU/Term 8/Computer Architecture`, so coursework is visible in Finder/Proton Drive and is never mixed with the syllabus and slides in the class-folder root.

#### Scenario: Files visible on both sides
- **WHEN** a Vivado project is created inside the container in the coursework directory
- **THEN** its files appear under the class folder's dedicated subdirectory on macOS, and files placed there from macOS are visible inside the container

#### Scenario: Files must be materialized locally
- **WHEN** the coursework directory is inside a cloud-synced folder that has evicted files to on-demand placeholders
- **THEN** reads through the bind mount fail with `Input/output error` even though macOS reads the same files successfully, so the files MUST be materialized from the macOS side (or the directory kept on local disk) before the toolchain is used
