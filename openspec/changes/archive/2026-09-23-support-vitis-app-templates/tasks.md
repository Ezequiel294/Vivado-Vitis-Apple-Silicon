## 1. Template support in the app tooling

- [x] 1.1 Add a `TEMPLATE` environment input to `tools/make-app.py` (default `hello_world`) and pass it to `create_app_component(template=...)`; verify by creating an app with an explicit `-t hello_world` and confirming the resulting tree is byte-for-byte what the current tooling produces
- [x] 1.2 Gate the `main.c` injection in `tools/make-app.py` on the template being `hello_world` or `SRC` having been passed explicitly; verify a `dhrystone` app is created with `dhry_1.c`, `dhry_2.c` and `platform.c` present and no `main.c`, and that its `UserConfig.cmake` is left untouched
- [x] 1.3 Fail with a message naming the template when `create_app_component` rejects it (template not installed, or the design lacks the UART/AXI Timer/memory it requires) instead of letting a half-made app persist; verified against the `Test_Microblaze` design, which has an AXI Timer but too little local memory — the error names the template and quotes Vitis's own reason (`requires at least 0x7800 bytes of any memory`), and no app directory is left behind
- [x] 1.4 Add `-t|--template` to `tools/make-app.sh`, forwarded via `docker exec -e TEMPLATE=...`; verify `./tools/make-app.sh --help` lists it and that omitting it reproduces today's behavior

## 2. Build settings (optimization and debug level)

- [x] 2.1 Add `OPT` and `DEBUG` inputs to `tools/make-app.py` that call `set_app_config("USER_COMPILE_OPTIMIZATION_LEVEL", ...)` and `set_app_config("USER_COMPILE_DEBUG_LEVEL", ...)` before `app.build()`; verify by reading back `get_app_config` for both keys and by grepping the built app's `UserConfig.cmake` for `-O3`
- [x] 2.2 Make the "app already exists" branch apply any build settings that were passed and rebuild, printing what it changed, rather than returning without acting; verify by re-running against an existing app with a different `-O` level and confirming the ELF is relinked and the new flag appears in the build output
- [x] 2.3 Add `-O|--opt` and `-g|--debug` to `tools/make-app.sh` (accepting `none` for "no debug info"); verify `--help` lists them and that `-O3 -g none` produces a build whose printed compile flags contain `-O3` and no `-g`

## 3. Protecting template sources on rebuild

- [x] 3.1 Change `tools/run-sw.sh` to sync `$PROJ/src/main.c` into the app only when `$APP_DIR/src/main.c` already exists; verify by rebuilding a `dhrystone` app twice and confirming its source set is unchanged, and by rebuilding the existing `Test_Microblaze` hello app and confirming an edit to `projects/Test_Microblaze/src/main.c` still reaches the binary

## 4. Serial capture

- [x] 4.1 Add a `capture_serial` helper to `tests/common/lib.sh` that sets the port with `stty`, reads the port, tees raw bytes to a log file, and prints a CR-inserted copy so bare-`LF` output does not stair-step; verified against the board running the hello app (lines at the left margin, log byte-identical to what was sent) and, for the bare-`LF` case the hello app does not produce, against the helper's own substitution — the end-to-end bare-`LF` proof is task 5.2's Dhrystone run
- [x] 4.2 Give the helper a timeout and a stop-on-pattern argument so a test can use it unattended; verify it returns non-zero on timeout and zero when the pattern appears

## 5. Test 09 — Dhrystone

- [x] 5.1 Write `tests/09-dhrystone/build-hw.tcl` building a Microcontroller-preset MicroBlaze with 128 kB local memory, an AXI Timer, MDM enabled and a 100 MHz clock on the A7-100T, keeping test 03's `ext_reset_in` guard and adding guards for the AXI Timer, the 128 kB memory and the clock frequency; verify the script errors out if the timer is removed, and otherwise produces a bitstream, an `.mmi` and an `.xsa`
- [x] 5.2 Write `tests/09-dhrystone/run.sh` that builds the hardware, creates the app from the `dhrystone` template at `-O3` with no debug, bakes the ELF into the bitstream, programs the board, and captures the serial transcript; verify it runs start to finish against the board
- [x] 5.3 Make the pass criterion machine-checkable: the transcript must contain `The Dhrystone App has run successfully` and a non-zero `Dhrystones per Second` value, with the code-size lines from the build preserved in the run output; verify the test reports FAIL when the board is programmed with test 03's bitstream instead
- [x] 5.4 Write `tests/09-dhrystone/README.md` in the suite's established shape (what it proves / how a human runs it / how an agent runs it / pass criteria / failure table), including the timer-wrap symptom, the 9600 baud and channel-B port details, and a section on deriving Homework 2's other two processor configurations from this one; verify the file covers every heading the other eight test READMEs use
- [x] 5.5 Add test 09 to `tests/README.md` and to `tests/run-all.sh`; verify `run-all.sh` lists it and that its long runtime is called out the way test 08's jumper requirement is

## 6. Documentation

- [x] 6.1 Extend the README's "Write and run C on the MicroBlaze" section with template selection and build settings — what `-t` is for, that template apps keep their own sources, and how to set `-O3`/no-debug — with the Dhrystone benchmark as the worked example; verify a reader can get from an exported `.xsa` to a benchmark number using only the README
- [x] 6.2 Document serial capture in the README next to the existing `screen` instructions: when to use each, the bare-`LF` stair-stepping symptom, and that the capture helper cannot send input; verify both paths are shown with a real command line
- [x] 6.3 List test 09 in the README's test-suite section and add the benchmarking row to the §7 works/doesn't table; verify the table still reads correctly alongside the Vitis IDE row
- [x] 6.4 Add a journal section recording what was established about the template library — that `dhrystone` is one of 35 headless templates, that `set_app_config` is the IDE's Build Settings page, that `print_elf_size` is why `mb-size` had to be on `PATH`, and the 128 kB `updatemem` result once known; verify the section follows the journal's existing numbering and one-line-heading convention

## 7. End-to-end verification

- [x] 7.1 Run test 09 on the board and confirm the benchmark prints plausible numbers — this is the first exercise of `updatemem` on a 128 kB local memory, so record the outcome either way in the journal
- [x] 7.2 Re-run tests 01 through 05 and 07 to confirm the `run-sw.sh` and `lib.sh` changes broke nothing; `run-all.sh -y` reports 01-05 and 07 pass and 06 still broken (its expected result). Note the `-y` caveat the suite prints itself: the visual checks in 01, 03, 04 and 07 were skipped, so those tests verified builds and downloads only — test 03's serial output was confirmed separately by hand, since that is the path `run-sw.sh` and `lib.sh` actually changed
- [x] 7.3 Confirm no existing invocation changed behavior: run `./tools/make-app.sh -d projects/Test_Microblaze` and `./tools/run-sw.sh -d projects/Test_Microblaze` with no new flags and verify the hello app still builds, bakes and prints over serial
