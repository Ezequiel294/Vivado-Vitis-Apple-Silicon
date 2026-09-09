# Test 03 — MicroBlaze hardware platform for the Arty A7-100T.
#
# MicroBlaze + 32KB local BRAM + AXI UartLite on the USB-UART + MDM debug.
# Produces system_wrapper.xsa (for Vitis) and system_wrapper.bit.
#
# Run through ../common/lib.sh (vivado_batch), not directly.

set root [file dirname [file normalize [info script]]]
set proj $root/vivado

file delete -force $proj
create_project mb_hello $proj -part xc7a100tcsg324-1
set_property board_part digilentinc.com:arty-a7-100:part0:1.1 [current_project]

create_bd_design "system"

create_bd_cell -type ip -vlnv \
    [lindex [lsort -dictionary [get_ipdefs -all -filter {NAME == microblaze}]] end] microblaze_0
if {[catch {
    apply_bd_automation -rule xilinx.com:bd_rule:microblaze -config { \
        local_mem {32KB} ecc {None} cache {None} debug_module {Debug Only} \
        axi_periph {Enabled} axi_intc {0} clk {New Clocking Wizard (100 MHz)} } \
        [get_bd_cells microblaze_0]
} err]} {
    error "MicroBlaze automation failed: $err"
}

# --- clock and reset ----------------------------------------------------
set cw [lindex [get_bd_cells -quiet -filter {VLNV =~ "*clk_wiz*"}] 0]
# The Arty A7's sys_clock is a 100MHz single-ended oscillator on E3. Without
# this the wizard expects a differential pair and board automation silently
# creates a generic diff clock port instead of binding to the board.
set_property CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} $cw

set clkpin [get_bd_pins -quiet -of_objects $cw -filter {TYPE == clk && DIR == I}]
set rstpin [get_bd_pins -quiet -of_objects $cw -filter {TYPE == rst && DIR == I}]
if {[catch {
    apply_bd_automation -rule xilinx.com:bd_rule:board \
        -config {Board_Interface {sys_clock ( System Clock ) } Manual_Source {Auto}} $clkpin
} err]} { puts "BOARD_AUTOMATION(clk): $err" }
if {[catch {
    apply_bd_automation -rule xilinx.com:bd_rule:board \
        -config {Board_Interface {reset ( Reset ) } Manual_Source {Auto}} $rstpin
} err]} { puts "BOARD_AUTOMATION(rst): $err" }
if {[get_bd_ports -quiet -filter {NAME =~ "*diff_clock*"}] ne ""} {
    error "sys_clock board interface did not apply - generic diff clock created"
}

# The reset button must ALSO reach proc_sys_reset's ext_reset_in. Left
# unconnected the pin reads as permanently asserted and the CPU never leaves
# reset — the design still builds and passes validation, and the failure is
# invisible until you run it on real hardware. This cost hours once; the
# guard below makes sure it can never come back silently.
set psr [lindex [get_bd_cells -quiet -filter {VLNV =~ "*proc_sys_reset*"}] 0]
if {[catch {
    apply_bd_automation -rule xilinx.com:bd_rule:board \
        -config {Board_Interface {reset ( Reset ) } Manual_Source {Auto}} \
        [get_bd_pins $psr/ext_reset_in]
} err]} { puts "BOARD_AUTOMATION(ext_reset): $err" }
if {[get_bd_nets -quiet -of_objects [get_bd_pins $psr/ext_reset_in]] eq ""} {
    error "proc_sys_reset ext_reset_in is unconnected - CPU would be held in reset"
}

# --- UART ---------------------------------------------------------------
create_bd_cell -type ip -vlnv \
    [lindex [lsort -dictionary [get_ipdefs -all -filter {NAME == axi_uartlite}]] end] axi_uartlite_0
# Set the baud rate explicitly. The automation default is 9600, which is easy
# to mistake for 115200 and produces nothing but garbage on the terminal.
set_property CONFIG.C_BAUDRATE {9600} [get_bd_cells axi_uartlite_0]
if {[catch {
    apply_bd_automation -rule xilinx.com:bd_rule:board \
        -config {Board_Interface {usb_uart} Manual_Source {Auto}} \
        [get_bd_intf_pins axi_uartlite_0/UART]
} err]} { puts "UART_BOARD_AUTOMATION: $err" }
if {[catch {
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
        -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} \
                  Master {/microblaze_0 (Periph)} Slave {/axi_uartlite_0/S_AXI} \
                  ddr_seg {Auto} intc_ip {New AXI Interconnect} master_apm {0} } \
        [get_bd_intf_pins axi_uartlite_0/S_AXI]
} err]} { puts "UART_AXI_AUTOMATION: $err" }

validate_bd_design
regenerate_bd_layout
save_bd_design

make_wrapper -files [get_files system.bd] -top -import
set_property top system_wrapper [current_fileset]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "implementation did not finish - see $proj/mb_hello.runs/impl_1/runme.log"
}

write_hw_platform -fixed -include_bit -force $root/system_wrapper.xsa
puts "BUILD OK: $root/system_wrapper.xsa"
