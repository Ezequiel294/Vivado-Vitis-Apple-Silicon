# Journal — issues hit while building this environment

Chronological record of every problem encountered getting Vivado/Vitis 2026.1
running in Docker on the MacBook Air M5, what was tried, and what the actual
fix was. Written 2026-09-03, at the point where everything works except the
board-in-hand steps (board not yet available).

---

## 1. Rosetta was silently OFF — Docker was using QEMU

**Symptom:** `docker run --platform linux/amd64 … uname -m` printed `x86_64`,
so everything *looked* fine, but the VM's binfmt handler for x86-64 was
`/usr/bin/qemu-x86_64` (~10x slower than Rosetta; Vivado would have been
unusable).

**Diagnosis that worked:** read the binfmt registrations from inside the VM:

```sh
docker run --rm --privileged --platform linux/arm64 ubuntu:22.04 \
  sh -c 'mount -t binfmt_misc none /proc/sys/fs/binfmt_misc; ls /proc/sys/fs/binfmt_misc/'
```

**Tried:** setting `UseVirtualizationFramework: true` and
`UseVirtualizationFrameworkRosetta: true` in
`~/Library/Group Containers/group.com.docker/settings-store.json` and
restarting Docker → **no effect**, still qemu.

**Root cause:** `UseLibkrun: true` — Docker Desktop was on the **Docker VMM
(libkrun)** backend, which ignores the Rosetta setting entirely.

**Correct fix:** switch the VMM to **Apple Virtualization framework**
(`UseLibkrun: false`, done via Docker Desktop settings + restart) with the
Rosetta checkbox on. Verified by the `rosetta` binfmt entry
(`interpreter /run/rosetta/rosetta`) appearing in the list above.

---

## 2. AMD installer died silently mid-download (twice) — OOM kill

**Symptom:** installer GUI window vanished after ~30-60 min with no error;
23GB of the 27.7GB download present; no installer process left running.

**Diagnosis that worked:** installer logs
(`~/.Xilinx/xinstall/xinstall-*.log`) showed
`Used memory: 7865 MB. Total memory: 7934 MB` right before death, and the
kernel confirmed it: `cat /sys/fs/cgroup/memory.events` → `oom_kill 1`, plus
`docker inspect vivado` → `OOMKilled: true`. The installer's JVM eats nearly
8GB by itself.

**Correct fix:** raise the Docker VM memory **8GB → 10GB** (`MemoryMiB: 10240`,
i.e. Docker Desktop → Resources → Memory). The installer resumes interrupted
downloads, so nothing was lost. With 10GB it completed in ~30 min.

Related habit adopted: run `caffeinate -dims` on the Mac during long installs.

---

## 3. Vivado refused to start: "valid license was not found"

**Symptom:** first `vivado` GUI launch after install popped the License
Manager error dialog instead of the IDE. (Not a Rosetta bug — 2026.1 Standard
requires a license up front, matching the class slides.)

**Wrinkle:** the License Manager's "View Host Information" screen wasn't
reachable from the error dialog, but it wasn't needed — the identity is pinned
in `docker-compose.yml`.

**Correct fix:** generate the free **Vivado ML Standard node-locked** license
at xilinx.com/getlicense against host name `vivado-box`, Ethernet MAC
`02:42:AC:11:00:02`, Linux 64-bit, and copy the emailed `Xilinx.lic` to
`~/.Xilinx/Xilinx.lic` (persistent volume). These compose values must never
change or the license dies.

---

## 4. Vivado crashed in license checkout: `realloc(): invalid pointer`

**Symptom:** `vivado -version` and the bare GUI worked, but any *licensed*
startup (batch mode with the license installed) aborted with
`realloc(): invalid pointer` (glibc abort, hs_err log written).

**Diagnosis that worked:** the hs_err stack showed
`libXil_lmgr11.so` (FlexLM) → **system** `/lib/x86_64-linux-gnu/libudev.so.1`
→ `udev_enumerate_scan_devices` → realloc abort. This is the known
Vivado-under-Rosetta udev bug (docker/for-mac#7320), but our `LD_PRELOAD`
stub did NOT intercept it because **FlexLM loads libudev via
`dlopen`/`dlsym`, which bypasses LD_PRELOAD symbol interposition.**

**Correct fix:** don't just preload the stub — **replace the system library**:
symlink `/lib/x86_64-linux-gnu/libudev.so.1 → /opt/stub/libudev-stub.so`
(now done in the Dockerfile). Keep LD_PRELOAD too (belt and suspenders).
License checkout then worked; FlexLM reads the MAC by other means, so the
node-locked check still passes.

---

## 5. The libudev replacement broke apt (versioned symbols)

**Symptom:** after fix #4, `apt-get` printed
`no version information available (required by libapt-pkg.so.6.0)` and then
crashed with an ld.so assertion; later, after partial fixes,
`undefined symbol: udev_enumerate_get_udev, version LIBUDEV_183`.

**Root cause:** real libudev exports its symbols under the version tag
`LIBUDEV_183`; binaries like apt link against those versioned symbols. The
plain stub had no version info and was missing some symbols.

**Tried:** temporarily restoring the real symlink just to run apt (works but
means the stub and OS tools can't coexist — unacceptable).

**Correct fix (all three parts needed):**
1. compile the stub with `-Wl,-soname,libudev.so.1`,
2. add a version script (`udev-stub.map`) exporting `udev_*` under
   `LIBUDEV_183`,
3. extend `udev-stub.c` with the extra symbols apt/others reference
   (`udev_enumerate_get_udev` and ~25 more no-ops).

After that, `apt-get check` passes AND Vivado license checkout still works.
Baked into the Dockerfile.

---

## 6. Vivado Tcl `add_files` doesn't expand `~`

**Symptom:** `add_files ~/fpga-work/...` → `ERROR: [Vivado 12-172] File or
Directory '~/fpga-work/...' does not exist` (while `create_project` with `~`
worked, confusingly).

**Correct fix:** use `$env(HOME)/...` in all Vivado Tcl scripts.

---

## 7. MicroBlaze IP: wrong version selected by scripting

**Symptom:** `ERROR: [BD 5-216] VLNV <xilinx.com:ip:microblaze:9.5> is not
supported for the current part. The latest supported version… <11.0>`.

**Root cause:** picking the IP def with plain `lsort` — string sort puts
`9.5` after `11.0`.

**Correct fix:** `lsort -dictionary` (numeric-aware) when selecting from
`get_ipdefs`.

---

## 8. Board automation wired a generic diff clock instead of the board clock

**Symptom (several rounds):**
- `get_bd_pins clk_wiz_1/clk_in1` → no such pin;
- automation with `Board_Interface {sys_clock}` "succeeded" but the generated
  wrapper had `diff_clock_rtl_clk_p/n` ports — a generic differential clock,
  not the board oscillator, which would never work on hardware.

**Tried:** targeting the `CLK_IN1_D` interface pin; using the GUI display-name
config string `{sys_clock ( System Clock ) }` → still fell back to the
generic diff clock.

**Root cause (from the board file):** the Arty **S7-25's `sys_clock` is a
12MHz single-ended** oscillator, while the clocking wizard defaults to a
differential input (`CLK_IN1_D`); the automation can't bind single-ended
board clock → diff input and silently creates a generic port instead.

**Correct fix:** before the board automation, run
`set_property CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin}` on the
clk_wiz cell so it exposes plain `clk_in1`, then apply the `sys_clock` board
automation to that pin. Also added a guard that errors out if any
`*diff_clock*` port exists after automation. (The MMCM multiplies 12MHz →
100MHz internally; working script: `fpga-work/projects/mb-hello/build-hw.tcl`.)

---

## 9. Generated Verilog wrappers had syntax errors — corrupted headers

**Symptom:** synthesis failed with `syntax error near '='` at line 7 of
**Vivado-generated** files (`system_wrapper.v`, `system.v`). Inspection showed
the `//Host : … running 64-bit Ubuntu"` header comment followed by raw,
uncommented lines of `/etc/os-release` (`VERSION_ID="22.04"…`).

**Root cause:** Vivado's OS-detection shells out to `lsb_release`; without it,
it falls back to parsing `/etc/os-release` badly and pastes multi-line output
into a single-line Verilog comment.

**Correct fix:** install `lsb-release` in the image. Header becomes one clean
line; generated files compile.

---

## 10. Vitis scripting: XSCT is dead in 2026.1

**Symptom 1:** `xsct` → `ERROR: xlsclients is not available` → fixed by
installing `x11-utils`. But then:

**Symptom 2:** `[ERROR]********** XSCT is disabled in Vitis 2026.1 release`.

**Correct fix:** use the **Vitis unified Python API** instead:
`vitis -s script.py` with `vitis.create_client(workspace=…)`,
`create_platform_component(hw_design=<xsa>, os="standalone",
cpu="microblaze_0")`, `create_app_component(template="hello_world")`, then
`.build()`. Working script pattern preserved in this journal's companion
scripts under `fpga-work/projects/mb-hello/`.

---

## 11. Vitis platform build failed in `dtc`

**Symptom:** `create_platform_component` → `Error in generating Processor
List. [fdt.py][ERROR]: dt_compile: unable to compile…` with no useful detail.

**Diagnosis that worked:** running AMD's bundled binary directly:
`/opt/Xilinx/2026.1/Vitis/bin/dtc --version` →
`error while loading shared libraries: libyaml-0.so.2`.

**Correct fix:** install `libyaml-0-2` in the image. Platform + hello-world
then built cleanly (this was the moment Vitis-under-Rosetta was proven to
work — the project's biggest open risk).

---

## 12. Smaller snags

- **`docker cp` of board files nested wrongly:** copying
  `arty-a7-100` into `…/board_files/` landed its `E.0` version dir at the top
  level (target dir didn't exist yet). Vivado still found the board via
  `board.xml`, but the layout was fixed to the proper
  `board_files/arty-a7-100/E.0/` nesting.
- **Proton Drive "Edit conflict" copies:** Vivado's build tree churns fast
  enough inside the synced `fpga-work/` folder that Proton Drive created
  `… (# Edit conflict … #).vdi` duplicates of intermediates. Harmless —
  delete them; pause sync during long builds if it gets noisy.
- **Quitting Docker Desktop from scripts is unreliable:** `osascript quit`
  sometimes leaves it running; the user ended up restarting it manually when
  changing VM settings.
- **Vivado License Manager GUI couldn't show Host Information pre-license** —
  irrelevant in this setup since the identity is pinned in compose, but worth
  knowing if following the class slides literally.

---

## End state (for whoever reads this cold)

Image/container fully reproduce all fixes from the repo (`Dockerfile`,
`udev-stub.c`, `udev-stub.map`, `docker-compose.yml`) — verified by a full
rebuild + recreate after which license checkout, a Verilog bitstream build
(`example1`), and a Vitis MicroBlaze hello-world compile all pass. Remaining
unverified: anything requiring the physical Arty board (openFPGALoader
programming, XVC/Hardware Manager, serial console, Vitis run-on-hardware).
