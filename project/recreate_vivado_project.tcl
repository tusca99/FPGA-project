set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set project_name FPGA-project
set part_name xc7a100tcsg324-1
set project_root [file normalize [file join $repo_root project .vivado]]
set project_dir [file join $project_root $project_name]
set synth_top uart_msg_loopback_top
set sim_top uart_msg_loopback_tb

proc collect_files {root_dir pattern} {
    if {![file isdirectory $root_dir]} {
        error "Missing source root: $root_dir"
    }

    set files {}
    foreach path [glob -nocomplain -directory $root_dir *] {
        if {[file isdirectory $path]} {
            set nested [collect_files $path $pattern]
            if {[llength $nested] > 0} {
                set files [concat $files $nested]
            }
        } elseif {[string match $pattern [file tail $path]]} {
            lappend files [file normalize $path]
        }
    }

    return [lsort -dictionary $files]
}

proc add_vhdl_tree {root_dir} {
    set source_files {}
    set sim_files {}

    foreach vhdl_file [collect_files $root_dir *.vhd] {
        if {[string match *_tb.vhd [file tail $vhdl_file]]} {
            lappend sim_files $vhdl_file
        } else {
            lappend source_files $vhdl_file
        }
    }

    foreach vhdl_file [lsort -dictionary $source_files] {
        add_files -norecurse $vhdl_file
    }

    foreach vhdl_file [lsort -dictionary $sim_files] {
        add_files -fileset sim_1 -norecurse $vhdl_file
    }
}

if {[file exists $project_dir]} {
    file delete -force $project_dir
}
create_project -force $project_name $project_dir -part $part_name
set_property target_language VHDL [current_project]
set_property simulator_language VHDL [current_project]

foreach source_root [list \
        [file join $repo_root project percolation_core] \
        [file join $repo_root project uart_message_bin]] {
    add_vhdl_tree $source_root
}

foreach constraint_root [list [file join $repo_root project constraint]] {
    foreach xdc_file [collect_files $constraint_root *.xdc] {
        add_files -fileset constrs_1 -norecurse $xdc_file
    }
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

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
    percolation_uart {
        set synth_top percolation_uart_top
        set sim_top percolation_uart_top_tb
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
} else {
    error "Top entity not found in sources_1: $synth_top"
}

set sim_matches [get_files -quiet -of_objects [get_filesets sim_1] -filter "NAME =~ *$sim_top*"]
if {[llength $sim_matches] > 0} {
    set_property top $sim_top [get_filesets sim_1]
} else {
    error "Top entity not found in sim_1: $sim_top"
}

save_project_as -force -name $project_name -dir $project_root

puts "Created Vivado project at [file join $project_dir ${project_name}.xpr]"