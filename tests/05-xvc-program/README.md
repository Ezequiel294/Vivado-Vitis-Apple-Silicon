# Test 05 — XVC bridge (programming from inside the container)

**Status: ✅ pass** (2026-09-08) — `XVC PROGRAM OK`; the chain enumerated and
`01-leds/leds.bit` downloaded through the bridge.

| | |
|---|---|
| Proves | The JTAG-over-TCP bridge works: tools running in the container can see the board and program it |
| Needs | Container running, board on USB |
| Depends on | 01 (uses `01-leds/leds.bit`) |
| Time | under a minute |

## What it tests

The container has no USB access, so Vivado and Vitis can't reach the board on
their own. `openFPGALoader --xvc` bridges that gap: it listens on a TCP port
and replays JTAG operations onto the real cable.

```
xsdb / Vivado (container)  --TCP:2542-->  openFPGALoader --xvc (Mac)  --USB-->  board
```

This test proves the bridge itself is sound — the device enumerates and a
bitstream downloads through it. That matters because **tests 06 and 07 depend
on this working.** If they fail while this passes, the fault is in the
specific feature (CPU debug, ILA), not in the connection.

For everyday programming you don't need any of this — `openFPGALoader` from
a Mac terminal (test 01) is simpler and more reliable. The bridge exists for
things that must run container-side: Hardware Manager, ILA/VIO, Vitis.

## How to run it (human)

```sh
cd ~/…/fpga-work/tests/05-xvc-program
./run.sh
```

The script starts the bridge, runs xsdb inside the container, programs test
01's design, and shuts the bridge down again. Confirm the switches drive the
LEDs.

### Doing it by hand (two terminals)

Worth knowing, because this is how you'd use Hardware Manager:

**Terminal 1 (Mac)** — the bridge. `--port` is required: openFPGALoader
defaults to 3721, Xilinx tools expect 2542.

```sh
openFPGALoader -b arty_a7_100t --xvc --port 2542
```

**Terminal 2** — xsdb inside the container:

```sh
docker exec -it vivado bash -lc 'source /opt/Xilinx/2026.1/Vitis/settings64.sh && xsdb'
```

At the `xsdb%` prompt (note `;#` for trailing comments — a bare `#` is not a
Tcl comment):

```tcl
connect -xvc-url tcp:host.docker.internal:2542    ;# reach the bridge
targets                                           ;# list the scan chain
targets -set -filter {name =~ "xc7a*"}            ;# select the FPGA
fpga -f /home/user/fpga-work/tests/01-leds/leds.bit
exit
```

Substitute a real filename — `<file>.bit` is a placeholder, not something to
type literally.

**In the Vivado GUI:** Hardware Manager → Open Target → Open New Target →
Local server → and the XVC device appears. "No devices detected" on the first
attempt is common — retry it (see test 07), or fall back to xsdb.

## How to run it (agent)

```sh
./run.sh -y
```

Fully machine-checkable up to the LED confirmation:

- `XVC PROGRAM OK` in the output ⇒ enumeration and download both worked
- `CONNECT FAILED` ⇒ bridge not running or unreachable
- `NO FPGA ON THE CHAIN` ⇒ bridge up but no device — usually a stale
  `hw_server` in the container

The bridge is **single-client**: nothing else may hold it, and it can't run
at the same time as plain `openFPGALoader` programming or an open `screen`
session on the JTAG channel. `lib.sh` starts it with `sleep 999999 |` holding
stdin open, because openFPGALoader quits when its stdin reaches EOF — a
backgrounded bridge without that dies immediately.

## Pass criteria

`XVC PROGRAM OK`, the scan chain lists `xc7a100t`, and the board runs the
programmed design.

## If it fails

| Symptom | Cause |
|---|---|
| `CONNECT FAILED` | Bridge isn't running, or died on stdin EOF. Check `/tmp/xvc-bridge.log` |
| `No devices detected` / empty chain | Stale `hw_server`/`cs_server` in the container: `docker exec vivado pkill -x hw_server` |
| Bridge won't start | Something else holds the FTDI port — close `screen`, kill other bridges |
| Works once, fails after | Same stale-server problem; `lib.sh` cleans up on exit, manual sessions don't |
