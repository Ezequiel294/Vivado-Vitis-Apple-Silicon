## Why

The archived baseline says the environment displays GUI applications launched
inside the container on the macOS screen. That is now known to be too strong:
the **Vitis IDE does not start at all**. It is an Electron app, and Chromium
aborts under user-mode x86-64 emulation regardless of the display path —
verified against XQuartz, a local Xvfb inside the container, and QEMU
substituted for Rosetta, all producing the same SIGTRAP (journal §20).

No scenario in the baseline is falsified — the two scenarios under that
requirement cover `xeyes`/the AMD installer and Vivado, which do work. But a
reader would reasonably conclude that Vitis's GUI works too, and it does not.
A spec that over-promises is worse than one that admits a gap, particularly
for the classmates this environment is meant to be shareable with.

The second half is the flip side: the capability that *replaced* the IDE is
absent from the specs. The repository now ships tooling that creates a Vitis
platform and application and rebuilds them without the IDE, and that is the
path by which C actually reaches the board. It is verified and in daily use,
but the baseline is silent on it.

## What Changes

- Narrow the container-environment GUI requirement to what is actually true —
  X11/Java-toolkit GUIs display correctly — and record the Electron/Chromium
  IDE as an explicit non-capability, with the evidence that rules out the
  display path and the choice of emulator as causes.
- Add a requirement that the repository ships tooling to create a Vitis
  platform and application, and to rebuild and run C on the soft CPU, without
  the IDE.

No code changes. The tooling and documentation this describes already exist
and are committed; this change brings the specs in line with them.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `container-environment`: the "x86-64 container runs GUI applications on the
  macOS display" requirement is reworded to cover X11/Java GUIs only, and
  gains a scenario recording the Vitis IDE as a non-capability.
- `usage-documentation`: gains a requirement that the repository provides a
  scripted path from a Vivado hardware design to C running on the soft CPU,
  since the IDE cannot provide it.

## Impact

- Specs only: `openspec/specs/container-environment/spec.md` and
  `openspec/specs/usage-documentation/spec.md`.
- No source, tooling, or documentation edits. `README.md` (the IDE-replacement
  section and its troubleshooting entries), `journal.md` §20–21, and
  `tools/make-app.sh`, `tools/make-app.py`, `tools/run-sw.sh` already satisfy
  what is being specified; they are the evidence, not the work.
- No effect on the test suite. Tests 01–07 continue to pass unchanged; nothing
  here describes behaviour they verify.
