set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set project_name FPGA-project
set part_name xc7a100tcsg324-1
set project_root [file normalize [file join $repo_root project .vivado]]
set project_dir [file join $project_root $project_name]

set synth_top uart_msg_loopback_top
set sim_top uart_msg_loopback_tb

if {[file exists $project_dir]} {
    file delete -force $project_dir
}

create_project -force $project_name $project_dir -part $part_name
set_property target_language VHDL [current_project]
set_property simulator_language VHDL [current_project]

# Add files in explicit compilation order to resolve cross-directory dependencies
# This ensures RTL utilities (AES, Trivium) compile before RNG app modules that use them

# === TIER 1: Core utilities and package ===
add_files -norecurse [file join $repo_root project rng a_rng_pkg.vhd]

# === TIER 2: AES encryption and dependencies (RTL) ===
add_files -norecurse [file join $repo_root RTL reg.vhd]
add_files -norecurse [file join $repo_root RTL sbox.vhd]
add_files -norecurse [file join $repo_root RTL gfmult_by2.vhd]
add_files -norecurse [file join $repo_root RTL sub_byte.vhd]
add_files -norecurse [file join $repo_root RTL shift_rwos.vhd]
add_files -norecurse [file join $repo_root RTL add_round_key.vhd]
add_files -norecurse [file join $repo_root RTL column_calculator.vhd]
add_files -norecurse [file join $repo_root RTL mix_columns.vhd]
add_files -norecurse [file join $repo_root RTL key_sch_round_function.vhd]
add_files -norecurse [file join $repo_root RTL key_schedule.vhd]
add_files -norecurse [file join $repo_root RTL controller.vhd]
add_files -norecurse [file join $repo_root RTL aes_enc.vhd]

# === TIER 3: Trivium RNG engine (RTL) ===
add_files -norecurse [file join $repo_root RTL rng_trivium.vhd]

# === TIER 4: Application RNG modules (project/rng) ===
# Now that rng_trivium is compiled, we can safely add trivium_array and hybrid
add_files -norecurse [file join $repo_root project rng b_rng_aes_ctr_prng.vhd]
add_files -norecurse [file join $repo_root project rng z_rng_trivium_array.vhd]
add_files -norecurse [file join $repo_root project rng zz_rng_hybrid_64.vhd]

# === TIER 5: Percolation core ===
add_files -norecurse [file join $repo_root project percolation_core percolation_lfsr32.vhd]
add_files -norecurse [file join $repo_root project percolation_core percolation_core.vhd]
add_files -norecurse [file join $repo_root project percolation_core percolation_uart_top.vhd]

# === TIER 6: UART stack ===
add_files -norecurse [file join $repo_root project uart_message_bin baud_gen.vhd]
add_files -norecurse [file join $repo_root project uart_message_bin uart_tx.vhd]
add_files -norecurse [file join $repo_root project uart_message_bin uart_rx.vhd]
add_files -norecurse [file join $repo_root project uart_message_bin uart_msg_tx.vhd]
add_files -norecurse [file join $repo_root project uart_message_bin uart_msg_rx.vhd]
add_files -norecurse [file join $repo_root project uart_message_bin uart_msg_loopback_top.vhd]

# === TESTBENCHES (simulation-only) ===
add_files -fileset sim_1 -norecurse [file join $repo_root project rng zzz_tb_rng_hybrid.vhd]
add_files -fileset sim_1 -norecurse [file join $repo_root project percolation_core percolation_core_tb.vhd]
add_files -fileset sim_1 -norecurse [file join $repo_root project percolation_core percolation_uart_top_tb.vhd]
add_files -fileset sim_1 -norecurse [file join $repo_root project uart_message_bin uart_msg_loopback_tb.vhd]

# === Constraints ===
add_files -fileset constrs_1 -norecurse [file join $repo_root project constraint pins.xdc]

# Set top-level modules
set_property top $synth_top [get_filesets sources_1]
set_property top $sim_top [get_filesets sim_1]

# Save project
save_project_as -force -name $project_name -dir $project_root

puts "======================================"
puts "Project created successfully!"
puts "Location: [file join $project_dir ${project_name}.xpr]"
puts "======================================"
puts ""
puts "Available simulation targets:"
puts "  loopback        - UART loopback benchmark"
puts "  rng             - RNG hybrid module test"
puts "  percolation     - Percolation core test"
puts "  percolation_uart - Percolation with UART integration"
puts ""
puts "Usage: vivado -mode batch -source $script_dir/recreate_vivado_project.tcl [target]"
puts ""

# Handle mode selection
set requested_mode ""
if {[llength $argv] > 0} {
    set requested_mode [lindex $argv 0]
}

switch -- $requested_mode {
    "" {
        puts "Default mode: uart_msg_loopback_top (synthesis) / uart_msg_loopback_tb (simulation)"
    }
    loopback {
        set synth_top uart_msg_loopback_top
        set sim_top uart_msg_loopback_tb
        set_property top $synth_top [get_filesets sources_1]
        set_property top $sim_top [get_filesets sim_1]
        puts "Mode: UART Loopback Benchmark"
    }
    rng {
        set sim_top tb_rng_hybrid
        set_property top $sim_top [get_filesets sim_1]
        puts "Mode: RNG Hybrid (simulation only)"
    }
    percolation {
        set synth_top percolation_core
        set sim_top percolation_core_tb
        set_property top $synth_top [get_filesets sources_1]
        set_property top $sim_top [get_filesets sim_1]
        puts "Mode: Percolation Core"
    }
    percolation_uart {
        set synth_top percolation_uart_top
        set sim_top percolation_uart_top_tb
        set_property top $synth_top [get_filesets sources_1]
        set_property top $sim_top [get_filesets sim_1]
        puts "Mode: Percolation with UART"
    }
    default {
        puts "Unknown mode: $requested_mode"
        puts "Use: loopback, rng, percolation, or percolation_uart"
    }
}

save_project_as -force -name $project_name -dir $project_root
