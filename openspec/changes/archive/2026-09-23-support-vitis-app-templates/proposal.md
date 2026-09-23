## Why

The IDE-free workflow built in the last change creates exactly one kind of
application: a hello-world whose single source file the user replaces with their
own `main.c`. That covers coursework where the student writes the program, but
not coursework where AMD ships the program. CS3375 Unit 6 (Performance
Evaluation) and Homework 2 both require running the **Dhrystone** benchmark,
which the course slides reach through the Vitis IDE's Examples library — a
library our tooling cannot currently touch, and an IDE that does not run here.

The benchmark itself is entirely within reach: `dhrystone` is one of 35 app
templates the headless `vitis -s` client can instantiate, and it needs none of
the broken JTAG-debugger path. What is missing is a way to *ask* for it, and a
way to set the compiler flags the assignment mandates (`-O3`, no debug) — both
of which are IDE dialogs today with documented headless equivalents.

## What Changes

- `tools/make-app.sh` and `tools/make-app.py` gain a `--template` option, so any
  app template in the Vitis install can be instantiated, not just `hello_world`.
- When a template other than `hello_world` is chosen, the tooling stops
  injecting the project's `main.c` over the template's sources. Templates such as
  `dhrystone` ship their own multi-file source set, BSP library dependencies
  (`xiltimer`) and linker constraints; overwriting them breaks the app.
- `tools/make-app.sh` gains options for the two build settings the assignment
  names — optimization level and debug level — which are the IDE's
  **Build → Settings** page and map to documented `set_app_config` keys.
- `tools/run-sw.sh` keeps the app's sources in sync with the project's `main.c`
  only for apps that own a `main.c`, so rebuilding a template-based app does not
  clobber it.
- A ninth test, `tests/09-dhrystone`, runs the Dhrystone benchmark end to end.
  It is the first test to exercise a 128 kB local memory through `updatemem`,
  and the first to assert on a program's numeric output rather than a string.
- The serial helper gains a way to capture a legible transcript. Dhrystone's
  result lines end in bare `LF`, which stair-steps in a terminal — the same
  problem the course slides solve by setting TeraTerm's "Receive new-line" to
  LF. Screenshots of benchmark output are a graded deliverable, so this stops
  being cosmetic.
- `README.md` gains instructions for choosing a template and setting build
  options, and lists the new test.

No breaking changes: every existing invocation of `make-app.sh` and
`run-sw.sh` keeps its current behavior, because the new options all default to
what the tooling does today.

## Capabilities

### New Capabilities

None. This extends the IDE-replacement tooling that the
`usage-documentation` capability already owns.

### Modified Capabilities

- `usage-documentation`: the requirement that soft-CPU software can be built and
  run without the Vitis IDE is extended to cover applications supplied by the
  toolchain's own template library (not only user-written sources) and the build
  settings that the IDE exposes as dialogs.
- `board-programming`: the boot-bitstream flow is required to work for local
  memories substantially larger than the default, and the serial-console
  requirement is extended to cover capturing a faithful transcript of program
  output, including output that uses bare `LF` line endings.

## Impact

- `tools/make-app.sh`, `tools/make-app.py`, `tools/run-sw.sh`
- `tests/common/lib.sh` (serial capture helper)
- New: `tests/09-dhrystone/` (run script, README, hardware build script)
- `README.md`, `journal.md`
- No image or Dockerfile change; the `dhrystone` template and the `mb-size`
  binary that reports code size are both already present in the 2026.1 install.
