# Hardware Debug State: SpanningCount=0 Issue

## Project Context
- **FPGA**: Arty A7-100T, xc7a100tcsg324-1, 100 MHz single-clock
- **Task**: Site percolation on 64×64 grid with UART binary control
- **Protocol v3.0**: 16-byte request (CfgP, CfgSeed, CfgStepsPerRun, CfgRuns), 16-byte response (StepCount, SpanningCount, TotalOccupied, Status)
- **Baud**: 9600 on hardware

## Current Behavior

### ✅ Working
- **StepCount increments correctly**: cfg_runs=100 → StepCount=100
- **UART communication**: Binary protocol sends/receives 16 bytes successfully
- **Message encoding/decoding**: Verified working (StepCount=cfg_runs proves this)
- **Core runs to completion**: frontier_done fires (runs_done increments)

### ❌ Broken
- **SpanningCount always 0**: Should be ~16 for P=0.6, 64×64 grid, 16 runs
- **TotalOccupied always 0**: Should be ~600-1000 occupied sites across 16 runs
- **Testbench had bugs**: 
  - CfgStepsPerRun was 0x0001 (1 step) instead of 0x0040 (64 steps)
  - CfgRuns was 0x00000F10 (3856 decimal) instead of 0x00000010 (16 decimal)
  - **FIXED**: Updated testbench to correct values

## Root Cause Analysis

### Key Finding
Line 247 in `percolation_core.vhd`:
```vhdl
if frontier_spanning_s = '1' then
    spanning_cnt <= spanning_cnt + 1;
end if;
```

**`frontier_spanning_s` is NEVER '1' on hardware** (despite frontier_done_s firing 100 times).

This means either:
1. **RNG produces all zeros** (no occupied sites) → frontier cannot find spanning clusters
2. **Frontier row index bug** → pending_row_index never reaches grid_steps-1 condition (line 216-224 percolation_bfs_frontier.vhd)
3. **Frontier reach logic** → row_reach_v computed as all 0s despite non-zero input

### Evidence
- StepCount=cfg_runs proves: message encoding correct, core running correct iterations, frontier_done firing
- SpanningCount=0 AND TotalOccupied=0 proves: no sites marked as occupied OR no spanning detected
- **Most likely**: RNG not producing varied site occupancy on hardware (all 0s or all 1s)

## Code State

### Modified Files
1. **percolation_core_tb.vhd** (Fixed):
   - CfgStepsPerRun: 0x0001 → 0x0040 (now 64)
   - CfgRuns: 0x00000F10 → 0x00000010 (now 16)

2. **percolation_uart_top.vhd** (Enhanced with debug):
   - Added `debug_spanning_detected` signal to track if spanning ever detected
   - LED output now shows magenta (101) if spanning was detected at least once
   - Added report statement in WAIT_DONE state

### Key Modules (NOT modified, working as-is in simulation)
- `percolation_core.vhd`: Orchestrates runs, accumulates spanning/occupied
- `percolation_bfs_frontier.vhd`: Row-wise BFS detecting spanning clusters
- `zz_rng_hybrid_64.vhd`: RNG bank producing site occupancy (128×64 bits per clock = 64 sites × 2 stages)
- `uart_msg_rx.vhd` / `uart_msg_tx.vhd`: Binary message I/O (working)

## What We Know About the Hardware
- Synthesis/implementation completes successfully
- Bitstream programs without errors
- UART communication works (can send/receive 16-byte messages)
- Core runs (StepCount increments)
- **Something in RNG or frontier is broken on 64-row grid**

## Next Steps

### Immediate Debug
1. **Check LED output**: Program new bitstream with debug_spanning_detected LED (magenta)
   - If LED shows magenta → spanning IS detected, problem is elsewhere
   - If LED stays off → spanning NEVER detected on hardware

2. **Isolate RNG**: Add debug output to expose `rng_site_open_s` signal
   - Monitor if RNG produces varied bit patterns or stuck at 0/1

3. **Run corrected testbench** with N_ROWS_G=64:
   - Testbench assertions will confirm if core works in simulation with proper 64-row config
   - If testbench passes: problem specific to hardware/RNG/implementation
   - If testbench fails: problem in core logic itself

### Hypothesis Testing (Priority Order)
1. **RNG stuck at 0**: Check if site occupancy always 0 → no connectivity possible
2. **Frontier row counting**: Verify pending_row_index reaches grid_steps-1
3. **Grid size mismatch**: Confirm N_ROWS_G=64 everywhere (not 256 from old code)
4. **CfgStepsPerRun truncation**: Verify 16-bit value handled correctly through chain

## Hardware Test Status
```
cfg_runs=1   → StepCount=1 ✓, Spanning=0 ✗, Occupied=0 ✗
cfg_runs=10  → StepCount=10 ✓, Spanning=0 ✗, Occupied=0 ✗  
cfg_runs=100 → StepCount=100 ✓, Spanning=0 ✗, Occupied=0 ✗
cfg_runs=255 → StepCount=100 ✓ (capped), Spanning=0 ✗, Occupied=0 ✗
```

## Files to Check in New Debug Session
1. `project/percolation_core/percolation_core_tb.vhd` - Has correct test parameters now
2. `project/percolation_core/percolation_uart_top.vhd` - Has debug_spanning_detected LED
3. `project/percolation_core/percolation_core.vhd` - Lines 240-250 where spanning_cnt incremented
4. `project/percolation_core/percolation_bfs_frontier.vhd` - Lines 216-224 spanning detection logic
5. `project/rng/zz_rng_hybrid_64.vhd` - RNG output to verify it produces varied sites

## Commands to Continue
```bash
# Program FPGA with debug bitstream (after rebuild)
# vivado_lab -url TCP:127.0.0.1:3121 -open_hw
# program_hw_devices -file <bitstream.bit>

# Test with Python
cd python && python try.py

# Check LED color (should be magenta 101 if spanning detected)
# Visual inspection of LED on board
```

## Known Good State (Simulation)
- percolation_core_tb with corrected parameters (64 steps, 16 runs)
- Expected simulation output: non-zero SpanningCount and TotalOccupied
- If testbench passes → problem is hardware-specific (RNG/frontier implementation)

---

**Status**: Blocking issue - spanning never detected on hardware despite core completing all runs. Testbench corrected, awaiting new rebuild and LED debug info to isolate RNG vs frontier vs core logic.
