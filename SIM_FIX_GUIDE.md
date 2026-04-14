# 🚀 How to Fix and Run Simulations

## Quick Start (2 steps)

### Step 1: Backup Original TCL
```bash
cd /media/leonardo-pieripoli/Storage/Archivio/PhysicsOfData/ProgrammableHardware/FPGA-project/project/
cp recreate_vivado_project.tcl recreate_vivado_project.tcl.backup
```

### Step 2: Use Fixed TCL Script
```bash
# Option A: Replace original file
cp recreate_vivado_project_FIXED.tcl recreate_vivado_project.tcl

# Option B: Delete Vivado cache and recreate with FIXED version
rm -rf .vivado/FPGA-project/
vivado -mode batch -source recreate_vivado_project_FIXED.tcl
```

---

## Why This Fixes the "Failed to Link Design" Error

The original TCL script had a flaw:
```tcl
foreach source_root [list \
    [file join $repo_root RTL] \
    [file join $repo_root project rng] \
    ...
]
add_vhdl_tree $source_root
```

**Problem**: Files were added by directory scanning with alphabetical sorting, which didn't guarantee that `RTL/rng_trivium.vhd` compiled **before** `project/rng/z_rng_trivium_array.vhd` (which instantiates it).

**Solution**: The FIXED script explicitly lists files in strict dependency order:
```
1. a_rng_pkg  (package definition)
2. AES modules (reg, sbox, sub_byte, etc.)
3. aes_enc    (top-level AES)
4. rng_trivium ← CRITICAL: Must be here
5. z_rng_trivium_array ← Uses rng_trivium from step 4
6. zz_rng_hybrid_64 ← Uses aes_enc and trivium_array
7. percolation_core ← Uses rng_hybrid_64
8. UART stack
9. Testbenches
```

---

## Running Simulations

Once the project is recreated with the FIXED script:

### Run UART Loopback (Simplest, No RNG Dependencies)
```bash
vivado -mode batch -source recreate_vivado_project_FIXED.tcl loopback
vivado .vivado/FPGA-project/FPGA-project.xpr
# In GUI: Tools → Run Simulation → Behavioral Simulation
```

### Run RNG Hybrid Test
```bash
vivado -mode batch -source recreate_vivado_project_FIXED.tcl rng
vivado .vivado/FPGA-project/FPGA-project.xpr
# In GUI: Select zzz_tb_rng_hybrid from hierarchy, then run simulation
```

### Run Percolation Core Test
```bash
vivado -mode batch -source recreate_vivado_project_FIXED.tcl percolation
vivado .vivado/FPGA-project/FPGA-project.xpr
# In GUI: Run Simulation
```

### Run Percolation with UART
```bash
vivado -mode batch -source recreate_vivado_project_FIXED.tcl percolation_uart
vivado .vivado/FPGA-project/FPGA-project.xpr
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
1. Check that the FIXED TCL script was used
2. Verify no old project cache: `rm -rf project/.vivado/FPGA-project/`
3. Confirm all files exist: `ls -la project/percolation_core/percolation_lfsr32.vhd`
4. Manually open project and check File → Project Settings → Sources, verify order

### Missing entity errors?
Check compiler output (View → Output → Compilation) for specific entity names and review `recreate_vivado_project_FIXED.tcl` for typos

### Simulation won't elaborate?
Usually means entity not found at that compilation stage. Check the dependency order in the FIXED script matches the "Why This Fixes" section above.

---

## File Reference

- **Original script**: `project/recreate_vivado_project.tcl` (has auto-sort issue)
- **Fixed script**: `project/recreate_vivado_project_FIXED.tcl` (explicit order)
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
