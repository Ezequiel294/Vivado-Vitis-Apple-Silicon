## 1. Apply the spec deltas

- [x] 1.1 Archive this change so the two deltas land in the baseline, and verify `openspec/specs/container-environment/spec.md` now scopes the GUI requirement to X11/native-toolkit applications and carries the "Electron-based IDE does not run" scenario
- [x] 1.2 Verify `openspec/specs/usage-documentation/spec.md` now carries the "Soft-CPU software can be built and run without the Vitis IDE" requirement with its three scenarios
- [x] 1.3 Run `openspec validate --strict` and confirm it reports no errors for the updated baseline

## 2. Confirm the documentation already satisfies the new requirements

No documentation edits are expected — these were written alongside the tooling.
Each task is a check that the claim in the spec is actually met; if one fails,
fix the documentation rather than weakening the spec.

- [x] 2.1 Confirm `README.md` §7 lists the Vitis IDE as not working, and that the troubleshooting section explains the silent `vitis -w` exit, matching the non-capability scenario
- [x] 2.2 Confirm the README's "Write and run C on the MicroBlaze" section documents the export-XSA → create-platform → edit/rebuild/program path, naming the single source file the user edits
- [x] 2.3 Confirm the README states that `tests/` and `tools/` must be copied into the mounted coursework directory, since the container cannot see the repository

## 3. Confirm the tooling meets the behaviour specified

- [x] 3.1 Confirm `tools/make-app.sh --help` and `tools/run-sw.sh --help` both run and describe the flow, and that `make-app.sh` refuses with an actionable message when no `.xsa` is present
- [x] 3.2 Re-run `tools/run-sw.sh -d projects/<a GUI-built project> --no-program` and verify it locates the implementation directory and wrapper by search rather than by fixed name, and reports the baked boot bitstream
- [x] 3.3 Verify the end-to-end loop on hardware once: edit the project's `src/main.c`, run `tools/run-sw.sh`, and see the changed output on the serial console at 9600
