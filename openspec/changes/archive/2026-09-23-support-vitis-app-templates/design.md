## Context

See `proposal.md` — Why. The facts below were established by reading the 2026.1
install and the existing tooling, and they constrain every decision here.

- `vitis -s` exposes `client.get_templates(type='EMBD_APP')`, which lists 35
  templates on this install; `dhrystone` is one of them. So template support is
  a parameter, not a new mechanism.
- The app-component generator rewrites `APP_NAME` in the copied `CMakeLists.txt`
  to the *component* name. The existing `hello` app was built from the
  `hello_world` template and produced `hello.elf`. Template-based apps therefore
  need no change to how `run-sw.sh` finds the ELF.
- `component.set_app_config(key, values)` is AMD's documented API for build
  settings, and its own docstrings use `USER_COMPILE_OPTIMIZATION_LEVEL` and
  `USER_COMPILE_DEBUG_LEVEL` as the examples — the two settings an assignment
  names. Values land in the app's `UserConfig.cmake`.
- The `dhrystone` template's `CMakeLists.txt` ends with
  `print_elf_size(CMAKE_SIZE dhrystone)`, and `hello_world`'s does the same.
  Code size is already printed by every build; nothing needs adding for it.
- `dhrystone.tcl` refuses the template unless the design has a UART, an AXI
  Timer and ≥30000 bytes of memory. The template also pulls in the `xiltimer`
  BSP library and sets its own linker constraints (`stack 16k heap 16k`).
- `dhry_1.c` takes no input (`Number_Of_Runs = ITERATIONS`, 160000 on
  MicroBlaze) and prints its results with integer arithmetic through
  `xil_printf`, so no floating-point `printf` support is needed.

## Goals / Non-Goals

**Goals:**

- Make template choice and build settings parameters of the existing tooling,
  with defaults that leave every current invocation behaving identically.
- Prove the path end to end with a test that is machine-checkable, not
  eyeball-only.
- Keep "where do I edit my C?" answerable with one path for user-written apps,
  while template apps keep their own sources untouched.

**Non-Goals:**

- Doing Homework 2. The test builds **one** processor configuration; deriving
  the other two is the user's coursework, and the test README explains how.
- Making the serial capture helper interactive. `screen` stays the documented
  way to type at a program.
- Any attempt to revive the JTAG debugger. Benchmarking does not need it.

## Decisions

### Decision 1: `--template` as a parameter, `hello_world` as the default

`make-app.sh -t <name>` passes `TEMPLATE` through to `make-app.py`, which
forwards it to `create_app_component(template=...)`.

Rejected: a separate `make-benchmark.sh`. The two flows differ by one string
and one conditional; splitting them would duplicate the platform-creation half
and give the user two scripts to choose between.

### Decision 2: source injection is decided by whether the app owns a `main.c`

`make-app.py` injects the project's `main.c` only when the template is
`hello_world` (or when `-s` was passed explicitly). `run-sw.sh` then syncs
`$PROJ/src/main.c` into the app **only if `$APP_DIR/src/main.c` already
exists**.

This is the whole mechanism — no marker file, no new flag, no template name
recorded anywhere. An app created from `hello_world` has a `main.c` because we
put one there; `dhrystone` has `dhry_1.c`, `dhry_2.c` and `platform.c` and no
`main.c`, so the sync is skipped by construction.

Rejected: writing a `.template` marker into the app directory (new state to
keep correct, and invisible to a user reading the tree); adding
`run-sw.sh --no-sync` (a flag the user must remember, on every rebuild,
forever, or silently destroy their app).

### Decision 3: build settings go through `set_app_config`, not text edits

`make-app.py` calls `app.set_app_config("USER_COMPILE_OPTIMIZATION_LEVEL", …)`
and the same for `USER_COMPILE_DEBUG_LEVEL`, **before** `app.build()`.

Rejected: `sed` on `UserConfig.cmake`. It would work today, but the API
validates the key against `get_config_info` and is what the IDE itself calls,
so it stays correct if AMD reshapes the file. The `-O3` requirement also has to
survive a rebuild, which a regenerated `UserConfig.cmake` would silently undo.

`make-app.sh` must be able to change these on an **existing** app without
recreating it — the assignment's workflow is "build, read the number, change a
setting, build again". So the "app already exists" branch stops being a pure
no-op: it applies any build settings that were passed and rebuilds.

### Decision 4: the test builds one configuration and checks it by machine

`tests/09-dhrystone` builds a single MicroBlaze: Microcontroller preset,
128 kB local memory, AXI Timer, MDM enabled, 100 MHz — Homework 2's
configuration 3 (hardware multiplier and divider). It then creates the app from
the `dhrystone` template at `-O3` with no debug, bakes, programs, and captures
the serial output.

Pass is machine-checkable: the transcript must contain
`The Dhrystone App has run successfully` and a non-zero `Dhrystones per Second`
value. That keeps it out of the "judged by eye" category that the test-suite
requirement forces tests to declare.

Rejected: building all three configurations. Three Vivado implementation runs
of a 128 kB-BRAM design under emulation is an hour-plus, which makes the test
useless as a regression check, and the analysis is the graded part anyway.

### Decision 5: serial capture is a separate read-only helper

A `capture_serial` helper in `tests/common/lib.sh` sets the port with `stty`,
then reads it with `cat`, tee-ing raw bytes to a log file and passing a
CR-inserted copy to the terminal so bare-`LF` output does not stair-step. It
takes a timeout and a "stop when this string appears" pattern so the test can
use it unattended.

This is the macOS equivalent of the course slides' "set TeraTerm's Receive
new-line to LF" step. `screen` stays documented for interactive use, where
typing matters; the capture helper cannot send input and says so.

Capture starts **after** programming finishes, never during: the FT2232 drops
UART bytes while JTAG traffic is in flight (journal §12).

### Decision 6: the hardware build script asserts its own preconditions

`build-hw.tcl` for test 09 keeps the `ext_reset_in` guard that test 03
introduced, and adds guards for the two things this template checks at app
creation — that an AXI Timer is present, and that local memory is 128 kB — so a
mistake surfaces at hardware build time with a clear message, instead of as a
confusing template rejection several minutes later.

## Risks / Trade-offs

- **`updatemem` has never been exercised on a 128 kB local memory here; every
  proven bake used the default size.** → This is the single genuinely unverified
  step, and it is why the test exists. The `.mmi` simply describes more BRAMs and
  `updatemem` is built for it, but if it fails, the test fails loudly at the bake
  step rather than producing a board that sits silent. Run test 09 before
  building all three homework configurations.

- **The AXI Timer is 32 bits and wraps every 42.9 s at 100 MHz.** Dhrystone
  corrects for one wrap but not two. → 160000 iterations at the slide's
  ~37,700 Dhrystones/s is about 4 s, and Dhrystone barely multiplies, so even the
  no-multiplier configuration should stay far inside one wrap. The test README
  names the symptom: if a slower configuration reports a *shorter* time than a
  faster one, suspect wrap rather than the measurement.

- **`DMIPS/MHz` is computed from `XPAR_CPU_CORE_CLOCK_FREQ_HZ`.** → A design not
  actually clocked at 100 MHz yields a wrong figure that still looks plausible.
  The hardware guard checks the clock.

- **Changing build settings on an existing app now triggers a rebuild where the
  old code did nothing.** → Mild surprise, but the alternative is a flag that
  silently does not take effect, which is worse for an assignment that grades
  the compiler flags. The script prints what it changed.

- **The capture helper cannot send input.** → Documented. Every template we care
  about here is non-interactive; `screen` covers the rest.

## Migration Plan

None. All new options default to current behavior, no existing project
directory changes shape, and no image rebuild is involved — the `dhrystone`
template and `mb-size` are already in the installed toolchain.
