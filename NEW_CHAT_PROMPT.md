# Quick Prompt for New Chat - Percolation Hardware Debug

You are helping debug a Vivado/FPGA project (Arty A7-100T) that implements site percolation on a 64×64 grid with UART binary control.

## Problem Summary
**Hardware returns SpanningCount=0 and TotalOccupied=0, but StepCount is correct.**

The core completes all runs (StepCount=cfg_runs), but spanning cluster detection never fires:
- cfg_runs=100 → Response: StepCount=100 ✓, SpanningCount=0 ✗, TotalOccupied=0 ✗

## What We Know
1. **Message encoding/decoding works** (StepCount proves this)
2. **Core runs to completion** (frontier_done_s fires the right number of times)
3. **`frontier_spanning_s` never becomes '1'** on hardware (but should ~16 times in 16 runs)
4. **Testbench had critical bugs** (Fixed 26-Apr: CfgStepsPerRun was 1 not 64, CfgRuns was 3856 not 16)

## Critical Code Locations
- `project/percolation_core/percolation_core.vhd` line 247: spanning_cnt increment (never happens)
- `project/percolation_core/percolation_bfs_frontier.vhd` line 218: spanning output set to '1' (never fires)
- `project/rng/zz_rng_hybrid_64.vhd`: RNG bank producing site occupancy (likely suspect)

## Hypotheses (Priority Order)
1. **RNG produces all 0s** (no occupied sites) → impossible to detect spanning
2. **Row index bug** → pending_row_index never reaches grid_steps-1 (spanning check condition)
3. **Reach logic** → row_reach_v always 0 despite non-zero input

## Recent Changes
- Fixed `percolation_core_tb.vhd`: CfgStepsPerRun=0x0040 (64), CfgRuns=0x00000010 (16)
- Added `debug_spanning_detected` signal to `percolation_uart_top.vhd`
- LED now shows magenta (101) if spanning detected on any run

## Next Steps
1. **Rebuild bitstream** with debug changes
2. **Program FPGA** and observe LED:
   - Magenta → spanning detected, look elsewhere
   - Off → spanning never detected, debug RNG/frontier
3. **Run corrected testbench simulation** (N_ROWS_G=64) to verify core logic
4. **Add RNG debug output** to expose site occupancy bit patterns
5. **Trace frontier state machine** if needed

## Reference Files
- `DEBUG_STATE.md` - Complete analysis and commands
- `percolation_core_tb.vhd` - Corrected test with proper parameters
- `copilot-instructions.md` - Project conventions and current blocking issue

## Current Code State
- Bitstream last built: unknown (needs rebuild with debug changes)
- Python test script: `python/try.py` (working, sends requests to FPGA)
- Vivado project: `project/.vivado/FPGA-project/FPGA-project.xpr`

**Start with**: Rebuild bitstream → program FPGA → check LED color → run testbench to establish baseline
