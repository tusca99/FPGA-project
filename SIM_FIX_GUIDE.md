# 🚀 How to Fix and Run Simulations

## Quick Start (2 steps)

### Step 1: Backup Current TCL
```bash
cd /path/to/FPGA-project
cp project/recreate_vivado_project.tcl project/recreate_vivado_project.tcl.backup
```

### Step 2: Use Current TCL Script
```bash
# Recreate the project from the canonical script
vivado -mode batch -source project/recreate_vivado_project.tcl

# Optional: clean cache first if Vivado is holding stale state
rm -rf .vivado/FPGA-project/
vivado -mode batch -source project/recreate_vivado_project.tcl
```

---

## Why This Works

The current Tcl script only scans the active design trees and keeps the legacy `uart_modular/` copy out of the project. That avoids duplicate design units such as `baud_gen`, `uart_rx`, and `uart_tx`, while Vivado still resolves the dependency order from the instantiated entities.

---

## Running Simulations

Once the project is recreated with the current script:

### Run UART Loopback (Simplest, No RNG Dependencies)
```bash
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs loopback
vivado project/.vivado/FPGA-project/FPGA-project.xpr
# In GUI: Tools → Run Simulation → Behavioral Simulation
```

### Run RNG Hybrid Test
```bash
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs rng
vivado project/.vivado/FPGA-project/FPGA-project.xpr
# In GUI: Select zzz_tb_rng_hybrid from hierarchy, then run simulation
```

### Run Percolation Core Test
```bash
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs percolation
vivado project/.vivado/FPGA-project/FPGA-project.xpr
# In GUI: Run Simulation
```

### Run Percolation with UART
```bash
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs percolation_uart
vivado project/.vivado/FPGA-project/FPGA-project.xpr
# In GUI: Run Simulation
```

---

## Expected Results

### zzz_tb_rng_hybrid
- Duration: ~6000 clock cycles (100 ns each)
- Pass: `busy` goes low and `all_valid` goes high
- Output: 64 samples of 32-bit random words

### percolation_core_tb
- Duration: ~25 μs
- Pass: Reports StepCount > 0
- Output: Step/Spanning/Occupied statistics

### uart_msg_loopback_tb
- Duration: Variable (depends on message size)
- Pass: Loopback latency measured
- Output: Frame count and latency in cycles

---

## Troubleshooting

### Still getting "Failed to link design"?
1. Check that the current TCL script was used
2. Verify no old project cache: `rm -rf project/.vivado/FPGA-project/`
3. Confirm all files exist: `ls -la project/percolation_core/percolation_lfsr32.vhd`
4. Manually open project and check File → Project Settings → Sources, verify order

### Missing entity errors?
Check compiler output (View → Output → Compilation) for specific entity names and review `project/recreate_vivado_project.tcl` for typos

### Simulation won't elaborate?
Usually means entity not found at that compilation stage. Check the current script and the compile order in Vivado's Sources view.

---

## File Reference

- **Current script**: `project/recreate_vivado_project.tcl`
- **Backup**: `project/recreate_vivado_project.tcl.backup` (created if Step 1 used)

---

## Next Steps After Successful Simulation

1. Run all three testbenches to validate RNG, Percolation, and UART independently
2. Once each passes individually, integrate them end-to-end in `percolation_uart_top_tb`
3. Create a Python test harness to validate UART commands and statistics
4. Benchmark and measure latency baseline (UART frame time vs. core time)

---

**Last Updated**: 2026-04-10  
**Created by**: Copilot FPGA Agent
