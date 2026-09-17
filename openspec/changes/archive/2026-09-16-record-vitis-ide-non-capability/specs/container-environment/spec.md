## MODIFIED Requirements

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
