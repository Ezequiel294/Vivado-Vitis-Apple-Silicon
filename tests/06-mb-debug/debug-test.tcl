# Test 06 — can we drive the MicroBlaze debug module over the XVC bridge?
#
# This is a REGRESSION TEST for a known-broken feature. Today every debug
# operation fails; the point is to detect the day one of them starts working.
#
# Run with: xsdb debug-test.tcl <boot.bit> <hello.elf>   (container paths)

set bit [lindex $argv 0]
set elf [lindex $argv 1]
if {$bit eq "" || $elf eq ""} {
    puts "USAGE: xsdb debug-test.tcl <bitstream> <elf>"
    exit 1
}
foreach f [list $bit $elf] {
    if {![file exists $f]} { puts "NO SUCH FILE: $f"; exit 1 }
}

proc try {label script} {
    if {[catch {uplevel 1 $script} err]} {
        puts "RESULT $label FAIL: $err"
        return 0
    }
    puts "RESULT $label OK"
    return 1
}

# --- baseline: the parts that are known to work -------------------------
if {[catch {connect -xvc-url tcp:host.docker.internal:2542} err]} {
    puts "RESULT connect FAIL: $err"
    puts "BASELINE BROKEN - the bridge itself is down, this test proves nothing"
    exit 1
}
puts "RESULT connect OK"

puts "--- scan chain ---"
puts [targets]
puts "------------------"

if {![try "select-fpga" {targets -set -filter {name =~ "xc7a*"}}]} {
    puts "BASELINE BROKEN - no FPGA on the chain"
    exit 1
}
# Program the CPU design so there is a running MicroBlaze to talk to.
if {![try "fpga-program" {fpga -f $bit}]} {
    puts "BASELINE BROKEN - could not program over the bridge (see test 05)"
    exit 1
}
after 2000

# --- the actual subject of the test -------------------------------------
# From here on, everything exercises the MDM (MicroBlaze Debug Module).
# "MicroBlaze*" also matches "MicroBlaze Debug Module at USER2", so
# targets -set aborts with "more than one targets found" and the three
# operations below never run. Match only the CPU ("MicroBlaze #0").
if {![try "select-mb" {targets -set -filter {name =~ "MicroBlaze #*"}}]} {
    puts "SUMMARY: the MicroBlaze target does not even enumerate"
    exit 0
}

set n_ok 0
incr n_ok [try "stop" {stop}]
incr n_ok [try "dow"  {dow $elf}]
incr n_ok [try "con"  {con}]

puts ""
if {$n_ok == 0} {
    puts "SUMMARY: MDM-DEBUG-STILL-BROKEN (0/3 debug operations worked)"
} elseif {$n_ok == 3} {
    puts "SUMMARY: MDM-DEBUG-NOW-WORKING (3/3) - the limitation is fixed!"
} else {
    puts "SUMMARY: MDM-DEBUG-PARTIAL ($n_ok/3) - changed behaviour, investigate"
}
exit 0
