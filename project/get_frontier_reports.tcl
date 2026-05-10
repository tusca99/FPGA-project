# Run this in Vivado Tcl console after synthesis
# Simple version - no problematic options

# 1. Frontier utilization
report_utilization -cells [get_cells core_inst/frontier_inst] -file frontier_utilization.rpt

# 2. All nets in frontier with fanout
set frontier_nets [get_nets -of_objects [get_cells core_inst/frontier_inst]]
set fh [open frontier_nets_fanout.rpt w]
puts $fh "Net Name | Fanout | Driver | Load Count"
puts $fh "------------------------------------------"
foreach net $frontier_nets {
    set name [get_property NAME $net]
    set fanout [get_property FLAT_PIN_COUNT $net]
    set driver_pins [get_pins -of_objects $net -filter {DIRECTION == OUT}]
    if {[llength $driver_pins] > 0} {
        set driver [get_property REF_NAME [lindex $driver_pins 0]]
    } else {
        set driver "none"
    }
    set loads [llength [get_pins -of_objects $net -filter {DIRECTION == IN}]]
    puts $fh "$name | $fanout | $driver | $loads"
}
close $fh

# 3. High fanout nets - global top 200
report_high_fanout_nets -max_nets 200 -file frontier_high_fanout.rpt

# 4. Route status for frontier nets
if {[llength $frontier_nets] > 0} {
    report_route_status -of_objects $frontier_nets -file frontier_route_status.rpt
}

# 5. Congestion report
report_design_analysis -congestion -cells [get_cells core_inst/frontier_inst] -file frontier_congestion.rpt

# 6. Pin count summary
set all_pins [get_pins -of_objects [get_cells core_inst/frontier_inst]]
set inputs [llength [get_pins -of_objects [get_cells core_inst/frontier_inst] -filter {DIRECTION == IN}]]
set outputs [llength [get_pins -of_objects [get_cells core_inst/frontier_inst] -filter {DIRECTION == OUT}]]
set fh [open frontier_pin_summary.rpt w]
puts $fh "Frontier Instance: core_inst/frontier_inst"
puts $fh "Total Pins: [llength $all_pins]"
puts $fh "Inputs: $inputs"
puts $fh "Outputs: $outputs"
close $fh

puts "Reports generated."
