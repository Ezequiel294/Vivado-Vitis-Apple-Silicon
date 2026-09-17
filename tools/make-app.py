# make-app.py — create a Vitis platform + application for a Vivado design.
#
# This is what replaces the Vitis IDE's "New Platform / New Application
# Project" wizards, which we cannot use (the IDE does not run here — see
# journal section 20). It does exactly what those wizards do.
#
# Run it through ../tools/make-app.sh rather than directly; that wrapper
# handles the container and the environment variables.
#
# Inputs, all via environment variables:
#   PROJ  (required)  the Vivado project directory
#   XSA   (optional)  path to the .xsa; default: the only *.xsa inside PROJ
#   APP   (optional)  application name, default "hello"
#   SRC   (optional)  your C file; default PROJ/src/main.c if it exists,
#                     otherwise the template's hello world is kept
#   CPU   (optional)  processor instance, default "microblaze_0"
#
# Safe to re-run: it creates what is missing and leaves the rest alone.
import glob
import os
import shutil

import vitis

proj = os.environ["PROJ"]
app_name = os.environ.get("APP", "hello")
cpu = os.environ.get("CPU", "microblaze_0")
ws = f"{proj}/vitis"

xsa = os.environ.get("XSA") or next(iter(sorted(glob.glob(f"{proj}/*.xsa"))), None)
if not xsa or not os.path.exists(xsa):
    raise SystemExit(
        f"No .xsa found in {proj}.\n"
        "In Vivado: Generate Bitstream, then File > Export > Export Hardware,\n"
        "choose 'Include bitstream', and save it into the project directory."
    )

src = os.environ.get("SRC") or f"{proj}/src/main.c"

client = vitis.create_client(workspace=ws)

# --- platform: the BSP and drivers for YOUR hardware --------------------
plat_dir = f"{ws}/plat"
if not glob.glob(f"{plat_dir}/export/plat/*.xpfm"):
    print(f"Creating platform from {os.path.basename(xsa)} (cpu: {cpu})")
    plat = client.create_platform_component(
        name="plat", hw_design=xsa, os="standalone", cpu=cpu
    )
    plat.build()
else:
    print("Platform already exists, reusing it")
xpfm = glob.glob(f"{plat_dir}/export/plat/*.xpfm")[0]

# --- application --------------------------------------------------------
app_dir = f"{ws}/{app_name}"
if os.path.isdir(app_dir):
    print(f"App '{app_name}' already exists — rebuild it with tools/run-sw.sh")
else:
    print(f"Creating app '{app_name}' from the hello_world template")
    app = client.create_app_component(
        name=app_name, platform=xpfm, template="hello_world"
    )

    if os.path.exists(src):
        # Replace the template's source with yours. The template pins its
        # file list in UserConfig.cmake (USER_COMPILE_SOURCES =
        # "helloworld.c"); deleting helloworld.c without updating that list
        # makes CMake fail with "Cannot find source file: helloworld.c".
        for stale in ("helloworld.c", "main.c"):
            stale_path = f"{app_dir}/src/{stale}"
            if os.path.exists(stale_path):
                os.remove(stale_path)
        shutil.copy(src, f"{app_dir}/src/main.c")

        cfg = f"{app_dir}/src/UserConfig.cmake"
        with open(cfg) as fh:
            text = fh.read()
        text = text.replace('"helloworld.c"', '"main.c"')
        assert '"main.c"' in text, f"could not repoint USER_COMPILE_SOURCES in {cfg}"
        with open(cfg, "w") as fh:
            fh.write(text)
        print(f"Using your source: {src}")
    else:
        print(f"No {src} — keeping the template's hello world for now")

    app.build()

elf = f"{app_dir}/build/{app_name}.elf"
print(f"APP OK: {elf}" if os.path.exists(elf) else f"WARNING: no ELF at {elf}")
