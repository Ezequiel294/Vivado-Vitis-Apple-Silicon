# Test 07 — build a design containing an ILA and a VIO debug core.
# Run through ../common/lib.sh (vivado_batch), not directly.

set root [file dirname [file normalize [info script]]]
set proj $root/vivado

file delete -force $proj
create_project ila_vio $proj -part xc7a100tcsg324-1
set_property board_part digilentinc.com:arty-a7-100:part0:1.1 [current_project]

# --- ILA: 32-bit counter + 4-bit switches, 1024 samples deep --------------
create_ip -name ila -vendor xilinx.com -library ip -module_name ila_0
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES  {2} \
    CONFIG.C_PROBE0_WIDTH   {32} \
    CONFIG.C_PROBE1_WIDTH   {4} \
    CONFIG.C_DATA_DEPTH     {1024} \
    CONFIG.C_TRIGIN_EN      {false} \
    CONFIG.C_TRIGOUT_EN     {false} \
] [get_ips ila_0]

# --- VIO: read the switches, drive three LEDs -----------------------------
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_0
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN     {1} \
    CONFIG.C_PROBE_IN0_WIDTH  {4} \
    CONFIG.C_NUM_PROBE_OUT    {1} \
    CONFIG.C_PROBE_OUT0_WIDTH {3} \
] [get_ips vio_0]

generate_target all [get_ips]

add_files              $root/src/ila_vio_top.v
add_files -fileset constrs_1 $root/ila_vio.xdc
set_property top ila_vio_top [current_fileset]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "implementation did not finish - see $proj/ila_vio.runs/impl_1/runme.log"
}

file copy -force $proj/ila_vio.runs/impl_1/ila_vio_top.bit $root/ila_vio.bit
# Hardware Manager needs the probe file to know what the cores are wired to.
set ltx $proj/ila_vio.runs/impl_1/ila_vio_top.ltx
if {[file exists $ltx]} {
    file copy -force $ltx $root/ila_vio.ltx
    puts "BUILD OK: $root/ila_vio.bit + ila_vio.ltx"
} else {
    puts "WARNING: no .ltx probe file was produced - Hardware Manager will not"
    puts "         be able to name the probes. Debug cores may not have been inserted."
    puts "BUILD OK: $root/ila_vio.bit (no ltx)"
}
