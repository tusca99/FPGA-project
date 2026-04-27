# Debug Summary: Inside-Out Analysis

## Findings (from RTL reading)

### Core Logic: ✓ Working
- `percolation_core.vhd`: Completes 16 runs (StepCount=0x10)
- `percolation_bfs_frontier.vhd`: Completes spanning detection (SpanningCount=0x10)  
- Both generate correct occupied totals (TotalOccupied=0x9992)
- **Conclusion**: Data-plane is correct

### UART Wrapper Timing: ✗ Broken measurement
The timing counters in `percolation_uart_top.vhd` are measuring the wrong intervals:

**Current (wrong):**
- `batch_cycles = 0x0ada (2778 cycles)` ← WAY too small
- `rng_init_cycles = 0x0683 (1667 cycles)` 
- `core_run_cycles = 0x0ad99 (44441 cycles)` 
- Sum: 1667 + 44441 = 46108, but batch_cycles ≠ 46108

**Expected:**
- `batch_cycles` should measure entire WAIT_DONE duration (from CfgInit to Done assertion)
- Should be ~≥ 46108 cycles for all 16 runs + RNG warmup

**Root Cause:**
Line 207 in `percolation_uart_top.vhd`:
```vhdl
if batch_timing_active_s = '1' then
    batch_cycles_s <= batch_cycles_s + 1;
end if;
```

This counts while `batch_timing_active_s='1'`. But `batch_timing_active_s` is set to '0' too early, or there's an off-by-one in state transitions. The timing gates don't capture the full request→done window.

## Recent Regression (commit 8e8e4d7)

**Changes that affect timing:**
1. **Frontier line 268**: Removed `if Start='0'` gate on COMPLETE→IDLE
   - Old: Frontier stays in COMPLETE until Start deasserts (multi-cycle pulse)
   - New: Frontier goes to IDLE immediately (1-cycle pulse on Done)
   - Effect: `frontier_done_s` now pulses only 1 cycle instead of staying high

2. **Core line 231**: Removed `(rng_arm_s='1')` AND condition  
   - Old: Start gated on RNG arm handshake
   - New: Start ungated, rng_arm_s becomes dead code
   - Effect: RNG reset sequence may be skipped or misaligned

3. **UART top**: Removed timeout safety (lines 61, 185, 266-276)
   - Old: Timeout after 100k cycles with error state
   - New: No fallback if core doesn't finish
   - Effect: Relies entirely on core_done_s assertion; no recovery

## Suspected Timing Issue

The `batch_cycles` measurement is correct in concept (measures gate active time), but the gate timing itself is wrong. The gate should be:
- **START**: When WAIT_CORE state exits (we assert CfgInit + RunEn)
- **STOP**: When core_done_s='1' (all configured runs finished)

But because `batch_timing_active_s` is set combinationally during state transitions, it may not capture the full duration due to Verilog/VHDL scheduling quirks or state machine pipelining.

## Next Steps: Validate Hypothesis

### Option 1: Run Sims (Fastest)
```bash
# Run core alone to verify it reaches Done correctly
vivado -mode batch -source project/run_core_sim.tcl 2>&1 | tee sim.log

# Check for report statements showing runs_done reaching 16
grep "percolation_core run complete" sim.log
```

### Option 2: Add Debug Outputs (Safest)
Add report statements to trace:
1. When batch_timing_active_s toggles
2. When core enters/exits WAIT_DONE state  
3. When core_done_s asserts
4. Cycle counts at each transition

### Option 3: Review Timing Logic (Manual)
The fix likely involves:
- Ensuring batch_timing_active_s starts at the correct point
- Ensuring the counter captures the full WAIT_DONE residence time
- Possibly adding a pipeline stage to avoid state transition artifacts
