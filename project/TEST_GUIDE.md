# Simulation Test Guide

## Compilation Order & Dependencies

### Tier 1: Core Utilities (RTL/)
```
1. a_rng_pkg.vhd (defines types/constants)
2. AES modules: reg.vhd, sbox.vhd, add_round_key.vhd, mix_columns.vhd, etc.
3. aes_enc.vhd (top-level AES)
4. rng_trivium.vhd (Trivium PRNG engine)
```

### Tier 2: Application RNG (project/rng/)
```
5. a_rng_pkg.vhd (package from project/rng - same as RTL version)
6. z_rng_trivium_array.vhd (64x Trivium instances)
7. zz_rng_hybrid_64.vhd (Hybrid RNG combining AES + Trivium)
```

Legacy AES-CTR PRNG is not part of the current build.

### Tier 3: Percolation Core (project/percolation_core/)
```
9. percolation_core.vhd (uses rng_hybrid_64 + BFS connectivity)
```

### Tier 4: UART Stack (project/uart_message_bin/)
```
10. baud_gen.vhd
11. uart_tx.vhd, uart_rx.vhd
12. uart_msg_tx.vhd, uart_msg_rx.vhd
13. uart_msg_loopback_top.vhd
```

## Testbenches Available

| Testbench | Source | Top Module Tested | Purpose |
|-----------|--------|-------------------|---------|
| `zzz_tb_rng_hybrid.vhd` | project/rng/ | rng_hybrid_64 | Verify RNG seed→words pipeline (64 Trivium rows) |
| `percolation_core_tb.vhd` | project/percolation_core/ | percolation_core | Verify grid generation + BFS connectivity |
| `percolation_uart_top_tb.vhd` | project/percolation_core/ | percolation_uart_top | Verify UART command→core integration |
| `uart_msg_loopback_tb.vhd` | project/uart_message_bin/ | uart_msg_loopback_top | UART frame loopback benchmark |

## Vivado Commands

### Rebuild Project
```bash
cd project/
vivado -mode batch -source recreate_vivado_project.tcl
```

### Simulate (Vivado GUI)
```bash
cd project/.vivado/FPGA-project/
vivado FPGA-project.xpr
# Then: Flow > Run Simulation > Behavioral Simulation
```

### Simulate (Batch via TCL - loopback testbench)
```bash
cd project/
vivado -mode batch -source recreate_vivado_project.tcl loopback
# Then: open_project, run_simulation, etc.
```

### Simulate Percolation Core Directly
```bash
cd project/
vivado -mode batch -source recreate_vivado_project.tcl percolation
```

### Simulate RNG Hybrid (fastest standalone test)
```bash
cd project/rng/
# Manually add: a_rng_pkg.vhd → zzz_tb_rng_hybrid.vhd 
# (with RTL AES/Trivium in library)
```

## Expected Testbench Behavior

### RNG Hybrid TB (`zzz_tb_rng_hybrid.vhd`)
- **Duration**: ~6000 clock cycles (100 ns CLK)
- **Pass Criteria**: `busy='0'` and `all_valid='1'` within 6000 cycles
- **Output**: 64 rows of 32-bit random words, plus site_open flags based on threshold

### Percolation Core TB (`percolation_core_tb.vhd`)
- **Duration**: 25 μs
- **Test**: 8×8 grid, 16 runs, p=0.6
- **Pass Criteria**: StepCount > 0, can read SpanningCount

### UART Loopback TB (`uart_msg_loopback_tb.vhd`)
- **Duration**: Depends on message size
- **Test**: Fixed-length binary messages, loopback with latency tracking
- **Pass Criteria**: RX matches TX, latency measured

## Common Issues & Fixes

### Issue: "Cannot find entity rng_trivium"
**Fix**: Ensure RTL/rng_trivium.vhd is compiled BEFORE project/rng/z_rng_trivium_array.vhd
- Check Vivado compile order (Design → Open Elaborated Design)
- Manually drag RTL files before project/rng files in Source panel

### Issue: "Package rng_pkg not found"
**Fix**: Ensure a_rng_pkg.vhd from **either** RTL or project/rng is compiled first
- The Vivado TCL script should exclude RTL version automatically
- If error persists, check Project Settings → Simulation → Include files

### Issue: "Duplicate entity declaration"
**Fix**: This means both RTL and project/rng versions of a file are being compiled
- Vivado TCL should prevent this; if it happens, manually remove one from the project

### Issue: Simulation runs but produces no output
**Fix**: Check testbench reset sequence
- Most testbenches expect: Rst='0' for 20 ns, then Rst='1'
- Verify all output signals are being monitored in simulation

## Next Steps for Validation

1. **Start with RNG**: Run `zzz_tb_rng_hybrid.vhd` first (simplest, no external deps)
2. **Then Percolation**: Run `percolation_core_tb.vhd` (uses RNG internally)
3. **Finally UART**: Run `uart_msg_loopback_tb.vhd` and `percolation_uart_top_tb.vhd`

---

**Last Updated**: 2026-04-10
