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
#   PROJ      (required)  the Vivado project directory
#   XSA       (optional)  path to the .xsa; default: the only *.xsa inside PROJ
#   APP       (optional)  application name, default "hello"
#   SRC       (optional)  your C file; default PROJ/src/main.c if it exists,
#                         otherwise the template's hello world is kept
#   CPU       (optional)  processor instance, default "microblaze_0"
#   TEMPLATE  (optional)  Vitis app template, default "hello_world". Anything
#                         else (e.g. "dhrystone") brings its own sources, BSP
#                         libraries and linker settings, and SRC is ignored
#                         unless you passed it explicitly.
#   OPT       (optional)  optimization level: -O0 -O1 -O2 -O3 -Os
#   DEBUG     (optional)  debug level: -g1 -g2 -g3, or "none" for no debug info
#
# OPT and DEBUG are the Vitis IDE's Build > Settings page. Setting either one
# on an application that already exists updates it and rebuilds, so you can
# measure the same program at a different optimization level.
#
# Safe to re-run: it creates what is missing and leaves the rest alone.
import glob
import os
import shutil

import vitis

proj = os.environ["PROJ"]
app_name = os.environ.get("APP", "hello")
cpu = os.environ.get("CPU", "microblaze_0")
template = os.environ.get("TEMPLATE") or "hello_world"
opt = os.environ.get("OPT") or ""
debug = os.environ.get("DEBUG") or ""
ws = f"{proj}/vitis"

xsa = os.environ.get("XSA") or next(iter(sorted(glob.glob(f"{proj}/*.xsa"))), None)
if not xsa or not os.path.exists(xsa):
    raise SystemExit(
        f"No .xsa found in {proj}.\n"
        "In Vivado: Generate Bitstream, then File > Export > Export Hardware,\n"
        "choose 'Include bitstream', and save it into the project directory."
    )

# SRC only reaches the app when the template does not supply its own program.
# "dhrystone" ships dhry_1.c, dhry_2.c and platform.c; dropping our main.c on
# top of that would leave two main() definitions and a broken source list.
src_given = bool(os.environ.get("SRC"))
src = os.environ.get("SRC") or f"{proj}/src/main.c"
use_src = src_given or template == "hello_world"

def apply_build_settings(app):
    """Set the compiler flags an assignment specifies.

    These are the IDE's Build > Settings page. Going through set_app_config
    rather than editing UserConfig.cmake by hand means the key is validated
    against the toolchain and the setting survives a regenerated file.
    """
    changed = []
    for key, value in (
        ("USER_COMPILE_OPTIMIZATION_LEVEL", opt),
        # "none" is how you ask for no debug information at all; the
        # underlying setting wants an empty value for that.
        ("USER_COMPILE_DEBUG_LEVEL", "" if debug == "none" else debug),
    ):
        if not value and not (key.endswith("DEBUG_LEVEL") and debug == "none"):
            continue
        # get_app_config hands back a list, and quotes the value it stored:
        # a level set to -O3 reads back as ['"-O3"'].
        current = app.get_app_config(key=key)
        if not isinstance(current, str):
            current = ",".join(current or [])
        if current.strip('"') == value:
            continue
        app.set_app_config(key=key, values=value)
        changed.append(f"{key} = {value or '(none)'}")
    for line in changed:
        print(f"Build setting: {line}")
    return bool(changed)


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
    if opt or debug:
        app = client.get_component(name=app_name)
        if apply_build_settings(app):
            app.build()
        else:
            print("Build settings already as requested — nothing to do")
    else:
        print(f"App '{app_name}' already exists — rebuild it with tools/run-sw.sh")
else:
    # Catch a misspelled template here, with the real list, rather than
    # letting create_app_component fail somewhere less legible.
    try:
        available = client.get_templates(type="EMBD_APP") or []
        available = [t if isinstance(t, str) else str(t.get("name", t)) for t in available]
    except Exception:
        available = []
    if available and template not in available:
        raise SystemExit(
            f"No Vitis app template named '{template}'.\n"
            f"Installed templates: {', '.join(sorted(available))}"
        )

    print(f"Creating app '{app_name}' from the {template} template")
    try:
        app = client.create_app_component(
            name=app_name, platform=xpfm, template=template
        )
    except Exception as exc:
        # A template states what hardware it needs (dhrystone, for one,
        # requires a UART and an AXI Timer and at least 30 kB of memory).
        # When the design does not provide it, creation fails partway and
        # leaves a directory that would make the next run think the app is
        # already there.
        if os.path.isdir(app_dir):
            shutil.rmtree(app_dir, ignore_errors=True)
        raise SystemExit(
            f"Vitis refused to create an app from the '{template}' template "
            f"for this design:\n  {exc}\n"
            "That usually means the block design is missing hardware the "
            "template requires\n(dhrystone, for example, needs an AXI Timer "
            "and a UART), or the local memory is too small."
        )

    if use_src and os.path.exists(src):
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
    elif not use_src:
        print(f"Keeping the {template} template's own sources")
    else:
        print(f"No {src} — keeping the template's hello world for now")

    apply_build_settings(app)
    app.build()

elf = f"{app_dir}/build/{app_name}.elf"
print(f"APP OK: {elf}" if os.path.exists(elf) else f"WARNING: no ELF at {elf}")
