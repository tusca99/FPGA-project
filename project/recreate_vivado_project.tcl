set script_dir [file dirname [file normalize [info script]]]
set project_name FPGA-project
set part_name xc7a100tcsg324-1
set project_root [file normalize [file join $script_dir .vivado]]
set project_dir [file join $project_root $project_name]
set synth_top uart_msg_loopback_top
set sim_top uart_msg_loopback_tb

proc collect_files {root_dir pattern} {
    set files {}
    foreach path [glob -nocomplain -directory $root_dir *] {
        if {[file isdirectory $path]} {
            set nested [collect_files $path $pattern]
            if {[llength $nested] > 0} {
                set files [concat $files $nested]
            }
        } elseif {[string match $pattern [file tail $path]]} {
            lappend files $path
        }
    }
    return $files
}

if {[file exists $project_dir]} {
    file delete -force $project_dir
}
create_project -force $project_name $project_dir -part $part_name
set_property target_language VHDL [current_project]

foreach source_root [list \
        [file join $script_dir percolation_core] \
        [file join $script_dir uart_message_bin]] {
    foreach vhdl_file [collect_files $source_root *.vhd] {
        if {[string match *_tb.vhd [file tail $vhdl_file]]} {
            add_files -fileset sim_1 -norecurse $vhdl_file
        } else {
            add_files -norecurse $vhdl_file
        }
    }
}

foreach constraint_root [list [file join $script_dir constraint]] {
    foreach xdc_file [collect_files $constraint_root *.xdc] {
        add_files -fileset constrs_1 -norecurse $xdc_file
    }
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
update_compile_order -fileset constrs_1

set requested_mode ""
if {[llength $argv] > 0} {
    set requested_mode [lindex $argv 0]
}

switch -- $requested_mode {
    "" {
    }
    percolation {
        set synth_top percolation_core
        set sim_top percolation_core_tb
    }
    loopback {
        set synth_top uart_msg_loopback_top
        set sim_top uart_msg_loopback_tb
    }
    default {
        set synth_top $requested_mode
        set sim_top $requested_mode
    }
}

set source_matches [get_files -quiet -of_objects [get_filesets sources_1] -filter "NAME =~ *$synth_top*"]
if {[llength $source_matches] > 0} {
    set_property top $synth_top [get_filesets sources_1]
}

set_property top $synth_top [get_filesets sources_1]

set sim_matches [get_files -quiet -of_objects [get_filesets sim_1] -filter "NAME =~ *$sim_top*"]
if {[llength $sim_matches] > 0} {
    set_property top $sim_top [get_filesets sim_1]
}

set_property top $sim_top [get_filesets sim_1]

save_project_as -force -name $project_name -dir $project_root

puts "Created Vivado project at [file join $project_dir ${project_name}.xpr]"