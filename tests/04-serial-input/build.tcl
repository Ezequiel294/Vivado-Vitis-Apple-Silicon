# Test 04 — build the UART echo design for the Arty A7-100T.
# Run through ../common/lib.sh (vivado_batch), not directly.

set root [file dirname [file normalize [info script]]]
set proj $root/vivado

file delete -force $proj
create_project uart_echo $proj -part xc7a100tcsg324-1
set_property board_part digilentinc.com:arty-a7-100:part0:1.1 [current_project]

add_files              $root/src/uart_echo.v
add_files -fileset constrs_1 $root/uart_echo.xdc
set_property top uart_echo [current_fileset]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "implementation did not finish - see $proj/uart_echo.runs/impl_1/runme.log"
}

file copy -force $proj/uart_echo.runs/impl_1/uart_echo.bit $root/uart_echo.bit
puts "BUILD OK: $root/uart_echo.bit"
