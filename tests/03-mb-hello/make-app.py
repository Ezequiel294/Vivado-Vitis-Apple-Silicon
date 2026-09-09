# Test 03 — build the Vitis platform and application.
#
# XSCT is disabled in Vitis 2026.1, so scripting goes through the Python
# client API:  vitis -s make-app.py
#
# Idempotent: if the workspace already exists this only rebuilds, because the
# create_* calls fail on an existing component.
import glob
import os
import shutil

import vitis

here = os.path.dirname(os.path.abspath(__file__))
ws = f"{here}/vitis"
xsa = f"{here}/system_wrapper.xsa"

assert os.path.exists(xsa), f"missing {xsa} — run build-hw.tcl first"

client = vitis.create_client(workspace=ws)

# --- platform -----------------------------------------------------------
if not glob.glob(f"{ws}/mb_plat/export/mb_plat/*.xpfm"):
    plat = client.create_platform_component(
        name="mb_plat", hw_design=xsa, os="standalone", cpu="microblaze_0"
    )
    plat.build()
xpfm = glob.glob(f"{ws}/mb_plat/export/mb_plat/*.xpfm")[0]

# --- application --------------------------------------------------------
# Start from the hello_world template (it brings the linker script and BSP
# wiring), then replace its source with ours.
#
# This script only *creates*. Rebuilds go through the CMake tree Vitis
# generates (see run.sh) — the Python API documents calls for creating
# components, not for reopening an existing workspace.
app_dir = f"{ws}/hello"
if os.path.isdir(app_dir):
    print(f"APP EXISTS: {app_dir} (rebuild with cmake, see run.sh)")
else:
    app = client.create_app_component(name="hello", platform=xpfm, template="hello_world")
    for stale in ("helloworld.c", "main.c"):
        p = f"{app_dir}/src/{stale}"
        if os.path.exists(p):
            os.remove(p)
    shutil.copy(f"{here}/src/main.c", f"{app_dir}/src/main.c")
    # The hello_world template pins its source list in UserConfig.cmake
    # (USER_COMPILE_SOURCES = "helloworld.c"). Deleting that file without
    # updating the list makes CMake fail during configure with
    #   Cannot find source file: helloworld.c
    #   No SOURCES given to target: hello.elf
    # so point the list at the source we actually copied in.
    cfg = f"{app_dir}/src/UserConfig.cmake"
    with open(cfg) as fh:
        text = fh.read()
    text = text.replace('"helloworld.c"', '"main.c"')
    assert '"main.c"' in text, f"could not repoint USER_COMPILE_SOURCES in {cfg}"
    with open(cfg, "w") as fh:
        fh.write(text)
    app.build()

elf = f"{app_dir}/build/hello.elf"
assert os.path.exists(elf), f"missing {elf}"
print(f"APP OK: {elf}")
