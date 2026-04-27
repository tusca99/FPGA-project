set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set project_name FPGA-project
set part_name xc7a100tcsg324-1
set project_root [file normalize [file join $repo_root project .vivado]]
set project_dir [file join $project_root $project_name]

# Keep Vivado from saturating the workstation during elaboration/synthesis.
set_param general.maxThreads 2

if {[file exists $project_dir]} {
    catch {close_project -quiet}

    # Best-effort cleanup: stale Vivado/XSim outputs can be locked by a previous session.
    foreach cleanup_target [list \
        [file join $project_dir ${project_name}.cache] \
        [file join $project_dir ${project_name}.hw] \
        [file join $project_dir ${project_name}.ip_user_files] \
        [file join $project_dir ${project_name}.runs] \
        [file join $project_dir ${project_name}.sim] \
        [file join $project_dir .Xil] \
        [file join $project_dir ${project_name}.xpr] \
    ] {
        if {[file exists $cleanup_target]} {
            if {[catch {file delete -force -- $cleanup_target} delete_err]} {
                puts "WARNING: Could not delete '$cleanup_target': $delete_err"
            }
        }
    }
}

create_project -force $project_name $project_dir -part $part_name
set_property target_language VHDL [current_project]
set_property simulator_language VHDL [current_project]

# Collect and add all VHDL files from the active design trees only.
# This avoids pulling in legacy duplicates such as uart_modular/.
proc collect_vhdl_files {root_dirs} {
    set files {}
    foreach root_dir $root_dirs {
        if {![file exists $root_dir]} {
            continue
        }
        foreach path [glob -nocomplain -directory $root_dir *] {
            if {[file isdirectory $path]} {
                set nested [collect_vhdl_files [list $path]]
                set files [concat $files $nested]
            } elseif {[string match *.vhd [file tail $path]]} {
                lappend files [file normalize $path]
            }
        }
    }
    return [lsort -dictionary $files]
}

# Active VHDL roots only; the top-level uart_modular/ tree is legacy and
# intentionally excluded to prevent duplicate design units in Vivado.
set vhdl_roots [list \
    [file join $repo_root project rng] \
    [file join $repo_root project percolation_core] \
    [file join $repo_root project uart_message_bin] \
]

# Add all VHDL files. Testbenches go to sim_1; the loopback top stays in
# sources_1 so it can be selected as a synthesis or simulation top.
foreach vhdl_file [collect_vhdl_files $vhdl_roots] {
    set file_name [file tail $vhdl_file]

    if {[string match *_tb.vhd $file_name] || [string match tb_*.vhd $file_name]} {
        add_files -fileset sim_1 -norecurse $vhdl_file
    } else {
        add_files -norecurse $vhdl_file
    }
}

# Add constraints
set xdc_file [file join $repo_root project constraint pins.xdc]
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
}

# Let Vivado's dependency analyzer determine compile order based on entity instantiations
puts "Analyzing file dependencies..."
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Compile order determined automatically"

# Set default simulation/synthesis tops
set synth_top percolation_uart_top
set sim_top percolation_uart_top_tb

# Allow mode selection (optional)
set requested_mode ""
if {[llength $argv] > 0} {
    set requested_mode [lindex $argv 0]
}

switch -- $requested_mode {
    loopback {
        set synth_top uart_msg_loopback_top
        set sim_top uart_msg_loopback_tb
    }
    percolation_led {
        set synth_top percolation_led_top
        set sim_top percolation_core_tb
    }
    rng {
        set synth_top percolation_uart_top
        set sim_top tb_rng_hybrid
    }
    percolation {
        set synth_top percolation_core
        set sim_top percolation_core_tb
    }
    percolation_uart {
        set synth_top percolation_uart_top
        set sim_top percolation_uart_top_tb
    }
}

if {[llength $argv] > 0} {
    puts "Mode: $requested_mode"
}

set_property top $synth_top [get_filesets sources_1]
set_property top $sim_top [get_filesets sim_1]

save_project_as -force -name $project_name -dir $project_root

puts "Created Vivado project at [file join $project_dir ${project_name}.xpr]"
puts "Simulation top: $sim_top"
puts "Synthesis top: $synth_top"