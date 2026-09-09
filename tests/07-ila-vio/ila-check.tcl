# Test 07, headless — drive the ILA and VIO over the XVC bridge from batch Tcl.
#
# The test README defers this to the Vivado GUI, but every operation the GUI
# performs has a Tcl equivalent, and the ILA capture can be dumped to CSV and
# checked by machine. That turns "outcome unknown" into a real answer.
#
# Run inside the container with the bridge up on the Mac:
#   vivado -mode batch -source ila-check.tcl

set here [file dirname [file normalize [info script]]]
set ltx  $here/ila_vio.ltx
set csv  $here/ila_capture.csv

proc note {m} { puts "ILACHK: $m" }

open_hw_manager
connect_hw_server -quiet
note "hw_server connected"

# Hardware Manager over openFPGALoader's XVC is flaky ("No devices
# detected") even when the bridge accepts the connection, so retry a few
# times with a refresh in between before calling it a failure.
set opened 0
for {set attempt 1} {$attempt <= 4} {incr attempt} {
    catch {refresh_hw_server}
    if {![catch {open_hw_target -xvc_url host.docker.internal:2542} err]} {
        set opened 1
        note "target open (attempt $attempt)"
        break
    }
    note "open-target attempt $attempt failed: $err"
    catch {close_hw_target -quiet}
    after 3000
}
if {!$opened} {
    note "OPEN-TARGET FAILED after 4 attempts"
    exit 1
}

set dev [lindex [get_hw_devices] 0]
if {$dev eq ""} { note "NO DEVICE ON CHAIN"; exit 1 }
current_hw_device $dev
note "device = $dev"

set_property PROBES.FILE      $ltx $dev
set_property FULL_PROBES.FILE $ltx $dev
refresh_hw_device $dev
note "probes file loaded"

# ---------------- ILA ----------------
set ilas [get_hw_ilas -of_objects $dev -quiet]
note "ILA cores = $ilas"
if {$ilas eq ""} {
    note "ILA-RESULT: NO-CORES"
} else {
    set ila [lindex $ilas 0]
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    if {[catch {
        run_hw_ila -trigger_now $ila
        wait_on_hw_ila -timeout 60 $ila
        set data [upload_hw_ila_data $ila]
        write_hw_ila_data -force -csv_file $csv $data
    } err]} {
        note "ILA-RESULT: FAIL $err"
    } else {
        note "ILA-RESULT: CAPTURED -> $csv"
    }
}

# ---------------- VIO ----------------
set vios [get_hw_vios -of_objects $dev -quiet]
note "VIO cores = $vios"
if {$vios eq ""} {
    note "VIO-RESULT: NO-CORES"
} else {
    set vio [lindex $vios 0]
    if {[catch {
        refresh_hw_vio $vio
        # Probe names are hierarchical (e.g. "vio_i/probe_in0"), so a bare
        # "probe_in0" matches nothing. Enumerate and match by suffix.
        # The .ltx names VIO probes after the nets they are wired to
        # ("sw_IBUF", "vio_led"), not after the IP port names, so select by
        # direction rather than by guessing a name.
        set allp [get_hw_probes -of_objects $vio]
        note "VIO probes = $allp"
        set pin  ""
        set pout ""
        foreach pr $allp {
            set dir "?"
            catch {set dir [get_property DIRECTION $pr]}
            note "  probe $pr direction=$dir"
            if {$dir eq "INPUT"}  { set pin  $pr }
            if {$dir eq "OUTPUT"} { set pout $pr }
        }
        if {$pin eq ""}  { foreach pr $allp { if {[string match "*sw*"  $pr]} { set pin  $pr } } }
        if {$pout eq ""} { foreach pr $allp { if {[string match "*led*" $pr]} { set pout $pr } } }
        if {$pin eq "" || $pout eq ""} { error "could not classify probes: $allp" }
        note "using input=$pin output=$pout"
        set_property INPUT_VALUE_RADIX  BINARY $pin
        set_property OUTPUT_VALUE_RADIX BINARY $pout
        refresh_hw_vio $vio
        note "VIO-READ: probe_in0 (switches) = [get_property INPUT_VALUE $pin]"
        # 101 -> vio_led[2:0] -> LD6 on, LD5 off, LD4 on (LD7 is the heartbeat)
        set_property OUTPUT_VALUE 101 $pout
        commit_hw_vio $pout
        note "VIO-DRIVE: probe_out0 set to 101 (expect LD6 on, LD5 off, LD4 on)"
        refresh_hw_vio $vio
        note "VIO-READBACK: probe_out0 = [get_property OUTPUT_VALUE $pout]"
        note "VIO-RESULT: OK"
    } err]} {
        note "VIO-RESULT: FAIL $err"
    }
}

close_hw_target -quiet
disconnect_hw_server -quiet
note "done"
exit 0
