# Test 09 — MicroBlaze benchmarking platform for the Arty A7-100T.
#
# Homework 2's configuration 3: Microcontroller preset, hardware multiplier
# AND divider, 128 kB local memory, AXI Timer, MDM enabled, 100 MHz.
# Produces system_wrapper.xsa (for Vitis) and system_wrapper.bit.
#
# The three guards at the end are the point of this file. The Dhrystone
# template refuses to instantiate without a UART, an AXI Timer and 30 kB of
# memory, and it computes DMIPS/MHz from the processor clock — so a design
# that is wrong in any of those ways either fails confusingly several minutes
# later in Vitis, or produces a plausible-looking number that is wrong.
#
# Run through ../common/lib.sh (vivado_batch), not directly.

set root [file dirname [file normalize [info script]]]
set proj $root/vivado

file delete -force $proj
create_project mb_dhry $proj -part xc7a100tcsg324-1
set_property board_part digilentinc.com:arty-a7-100:part0:1.1 [current_project]

create_bd_design "system"

create_bd_cell -type ip -vlnv \
    [lindex [lsort -dictionary [get_ipdefs -all -filter {NAME == microblaze}]] end] microblaze_0
if {[catch {
    apply_bd_automation -rule xilinx.com:bd_rule:microblaze -config { \
        local_mem {128KB} ecc {None} cache {None} debug_module {Debug Only} \
        axi_periph {Enabled} axi_intc {0} clk {New Clocking Wizard (100 MHz)} } \
        [get_bd_cells microblaze_0]
} err]} {
    error "MicroBlaze automation failed: $err"
}

# --- processor configuration -------------------------------------------
# Homework 2 starts every configuration from the Microcontroller preset and
# then varies only the hardware multiplier and divider. This is config 3:
# both present. For config 1 set C_USE_HW_MUL 0 and C_USE_DIV 0; for config 2
# set C_USE_HW_MUL 1 and C_USE_DIV 0. Nothing else changes.
set_property -dict [list \
    CONFIG.C_USE_HW_MUL {1} \
    CONFIG.C_USE_DIV {1} \
    CONFIG.C_USE_BARREL {0} \
    CONFIG.C_USE_FPU {0} \
] [get_bd_cells microblaze_0]

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

# --- AXI Timer ----------------------------------------------------------
# Dhrystone measures elapsed time by reading this counter directly
# (XPAR_XTMRCTR_0_BASEADDR). Without it the template will not instantiate.
create_bd_cell -type ip -vlnv \
    [lindex [lsort -dictionary [get_ipdefs -all -filter {NAME == axi_timer}]] end] axi_timer_0
if {[catch {
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
        -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} \
                  Master {/microblaze_0 (Periph)} Slave {/axi_timer_0/S_AXI} \
                  ddr_seg {Auto} intc_ip {New AXI Interconnect} master_apm {0} } \
        [get_bd_intf_pins axi_timer_0/S_AXI]
} err]} { puts "TIMER_AXI_AUTOMATION: $err" }

validate_bd_design
regenerate_bd_layout
save_bd_design

# --- guards -------------------------------------------------------------
# 1. The AXI Timer must be present AND addressable by the CPU. An unmapped
#    timer builds fine and then makes Dhrystone read a constant, reporting an
#    absurd or infinite score.
if {[get_bd_cells -quiet -filter {VLNV =~ "*axi_timer*"}] eq ""} {
    error "no AXI Timer in the design - Dhrystone cannot measure time"
}
# "Mapped" means the CPU has an address segment for it. Ask the processor's
# own data address space what it can see, rather than asking the timer.
set dataseg [get_bd_addr_segs -quiet microblaze_0/Data/*]
set tmrseg ""
set lmbseg ""
foreach s $dataseg {
    if {[string match -nocase "*timer*" $s]} { set tmrseg $s }
    if {[string match -nocase "*lmb*" $s] || [string match -nocase "*local_memory*" $s]} {
        set lmbseg $s
    }
}
if {$tmrseg eq ""} {
    error "the AXI Timer is not mapped into the processor's address space.\nSegments found: $dataseg"
}

# 2. 128 kB of local memory. Homework 2 fixes this for all three
#    configurations, and the Dhrystone template needs at least 0x7800 bytes.
if {$lmbseg eq ""} {
    error "could not find the local memory address segment.\nSegments found: $dataseg"
}
# RANGE comes back as a hex byte count (0x00020000), not "128K".
set lmbrange [get_property RANGE $lmbseg]
if {[regexp {^(\d+)([KMG])$} $lmbrange -> num unit]} {
    set lmbbytes [expr {$num * [dict get {K 1024 M 1048576 G 1073741824} $unit]}]
} else {
    set lmbbytes [expr {$lmbrange}]
}
if {$lmbbytes != 131072} {
    error "local memory is $lmbrange ([expr {$lmbbytes / 1024}] kB), expected 128 kB - re-run block automation with local_mem {128KB}"
}

# 3. 100 MHz processor clock. Dhrystone divides by this to report DMIPS/MHz,
#    so a design clocked at anything else yields a wrong number that still
#    looks reasonable.
set clkmhz [get_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $cw]
if {$clkmhz ne "100.000" && $clkmhz ne "100"} {
    error "processor clock is $clkmhz MHz, expected 100 - DMIPS/MHz would be wrong"
}
puts "GUARDS OK: AXI Timer mapped, local memory [expr {$lmbbytes / 1024}] kB, clock $clkmhz MHz"

make_wrapper -files [get_files system.bd] -top -import
set_property top system_wrapper [current_fileset]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "implementation did not finish - see $proj/mb_dhry.runs/impl_1/runme.log"
}

write_hw_platform -fixed -include_bit -force $root/system_wrapper.xsa
puts "BUILD OK: $root/system_wrapper.xsa"
