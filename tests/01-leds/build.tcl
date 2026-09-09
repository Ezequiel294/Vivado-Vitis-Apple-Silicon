# Test 01 — build the switch/LED design for the Arty A7-100T.
# Run through ../common/lib.sh (vivado_batch), not directly.

set root [file dirname [file normalize [info script]]]
set proj $root/vivado

file delete -force $proj
create_project leds $proj -part xc7a100tcsg324-1
set_property board_part digilentinc.com:arty-a7-100:part0:1.1 [current_project]

add_files              $root/src/leds.v
add_files -fileset constrs_1 $root/leds.xdc
set_property top leds [current_fileset]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "implementation did not finish - see $proj/leds.runs/impl_1/runme.log"
}

file copy -force $proj/leds.runs/impl_1/leds.bit $root/leds.bit
puts "BUILD OK: $root/leds.bit"
