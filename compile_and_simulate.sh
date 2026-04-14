#!/bin/bash
# FPGA Project Simulation Compiler
# Compiles VHDL files in correct dependency order and runs xsim testbenches
# Usage: ./compile_and_simulate.sh [testbench_name]

set -e

PROJECT_ROOT="/media/leonardo-pieripoli/Storage/Archivio/PhysicsOfData/ProgrammableHardware/FPGA-project"
WORK_DIR="$PROJECT_ROOT/xsim_work"
TESTBENCH="${1:-uart_msg_loopback_tb}"

echo "==============================================="
echo "FPGA Project - xsim Compilation & Simulation"
echo "==============================================="
echo "Work directory: $WORK_DIR"
echo "Testbench: $TESTBENCH"
echo ""

# Clean previous work
if [ -d "$WORK_DIR" ]; then
    echo "Cleaning previous work..."
    rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "Compiling VHDL files in dependency order..."
echo ""

# Extract file list function
compile_file() {
    local filepath=$1
    local filename=$(basename "$filepath")
    if [ -f "$filepath" ]; then
        echo "  Compiling: $filename"
        xvhdl --work work --2008 "$filepath" 2>&1 | grep -i "error" || true
    else
        echo "  WARNING: File not found: $filepath"
    fi
}

# === TIER 1: Packages ===
echo "=== TIER 1: Packages ==="
compile_file "$PROJECT_ROOT/project/rng/a_rng_pkg.vhd"
echo ""

# === TIER 2: AES and dependencies ===
echo "=== TIER 2: AES Encryption ==="
compile_file "$PROJECT_ROOT/RTL/reg.vhd"
compile_file "$PROJECT_ROOT/RTL/sbox.vhd"
compile_file "$PROJECT_ROOT/RTL/gfmult_by2.vhd"
compile_file "$PROJECT_ROOT/RTL/sub_byte.vhd"
compile_file "$PROJECT_ROOT/RTL/shift_rwos.vhd"
compile_file "$PROJECT_ROOT/RTL/add_round_key.vhd"
compile_file "$PROJECT_ROOT/RTL/column_calculator.vhd"
compile_file "$PROJECT_ROOT/RTL/mix_columns.vhd"
compile_file "$PROJECT_ROOT/RTL/key_sch_round_function.vhd"
compile_file "$PROJECT_ROOT/RTL/key_schedule.vhd"
compile_file "$PROJECT_ROOT/RTL/controller.vhd"
compile_file "$PROJECT_ROOT/RTL/aes_enc.vhd"
echo ""

# === TIER 3: Trivium RNG ===
echo "=== TIER 3: Trivium PRNG ==="
compile_file "$PROJECT_ROOT/RTL/rng_trivium.vhd"
echo ""

# === TIER 4: Application RNG ===
echo "=== TIER 4: Application RNG Modules ==="
compile_file "$PROJECT_ROOT/project/rng/b_rng_aes_ctr_prng.vhd"
compile_file "$PROJECT_ROOT/project/rng/z_rng_trivium_array.vhd"
compile_file "$PROJECT_ROOT/project/rng/zz_rng_hybrid_64.vhd"
echo ""

# === TIER 5: Percolation Core ===
echo "=== TIER 5: Percolation Core ==="
compile_file "$PROJECT_ROOT/project/percolation_core/percolation_lfsr32.vhd"
compile_file "$PROJECT_ROOT/project/percolation_core/percolation_core.vhd"
compile_file "$PROJECT_ROOT/project/percolation_core/percolation_uart_top.vhd"
echo ""

# === TIER 6: UART Stack ===
echo "=== TIER 6: UART Stack ==="
compile_file "$PROJECT_ROOT/project/uart_message_bin/baud_gen.vhd"
compile_file "$PROJECT_ROOT/project/uart_message_bin/uart_tx.vhd"
compile_file "$PROJECT_ROOT/project/uart_message_bin/uart_rx.vhd"
compile_file "$PROJECT_ROOT/project/uart_message_bin/uart_msg_tx.vhd"
compile_file "$PROJECT_ROOT/project/uart_message_bin/uart_msg_rx.vhd"
compile_file "$PROJECT_ROOT/project/uart_message_bin/uart_msg_loopback_top.vhd"
echo ""

# === TIER 7: Testbenches ===
echo "=== TIER 7: Testbenches ==="

case "$TESTBENCH" in
    uart_msg_loopback_tb)
        echo "Compiling UART loopback testbench..."
        compile_file "$PROJECT_ROOT/project/uart_message_bin/uart_msg_loopback_tb.vhd"
        TB_ENTITY="uart_msg_loopback_tb"
        ;;
    percolation_core_tb)
        echo "Compiling Percolation core testbench..."
        compile_file "$PROJECT_ROOT/project/percolation_core/percolation_core_tb.vhd"
        TB_ENTITY="percolation_core_tb"
        ;;
    tb_rng_hybrid|zzz_tb_rng_hybrid)
        echo "Compiling RNG hybrid testbench..."
        compile_file "$PROJECT_ROOT/project/rng/zzz_tb_rng_hybrid.vhd"
        TB_ENTITY="tb_rng_hybrid"
        ;;
    percolation_uart_top_tb)
        echo "Compiling Percolation UART testbench..."
        compile_file "$PROJECT_ROOT/project/percolation_core/percolation_uart_top_tb.vhd"
        TB_ENTITY="percolation_uart_top_tb"
        ;;
    *)
        echo "Unknown testbench: $TESTBENCH"
        echo "Available: uart_msg_loopback_tb, percolation_core_tb, tb_rng_hybrid, percolation_uart_top_tb"
        exit 1
        ;;
esac
echo ""

echo "==============================================="
echo "Elaborating design..."
echo "==============================================="
xelab -work work --debug typical "$TB_ENTITY" 2>&1 | tail -20

echo ""
echo "==============================================="
echo "Design elaboration complete!"
echo "==============================================="
echo ""
echo "To run simulation interactively:"
echo "  cd $WORK_DIR"
echo "  xsim -gui work.$TB_ENTITY"
echo ""
echo "To run simulation in batch mode:"
echo "  xsim work.$TB_ENTITY -runall"
echo ""
