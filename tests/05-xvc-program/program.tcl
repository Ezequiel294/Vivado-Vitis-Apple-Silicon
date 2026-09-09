# Test 05 — program the board from inside the container over the XVC bridge.
# Run with: xsdb program.tcl <path-to-bitstream-inside-container>
#
# Tcl comments after a command need ";#", not a bare "#".

set bit [lindex $argv 0]
if {$bit eq ""} { puts "USAGE: xsdb program.tcl <bitstream>"; exit 1 }
if {![file exists $bit]} { puts "NO SUCH FILE: $bit"; exit 1 }

puts "XVC: connecting to the bridge on the Mac"
if {[catch {connect -xvc-url tcp:host.docker.internal:2542} err]} {
    puts "CONNECT FAILED: $err"
    exit 1
}

puts "XVC: scan chain"
puts [targets]

if {[catch {targets -set -filter {name =~ "xc7a*"}} err]} {
    puts "NO FPGA ON THE CHAIN: $err"
    exit 1
}

puts "XVC: programming $bit"
if {[catch {fpga -f $bit} err]} {
    puts "PROGRAM FAILED: $err"
    exit 1
}

puts "XVC PROGRAM OK"
exit 0
