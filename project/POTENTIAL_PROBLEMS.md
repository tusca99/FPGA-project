# Potential Problems - Percolation UART Top

## 1. Batch Cycle Timing Anomaly

### Observed Issue
Simulation response shows:
- **Batch cycles**: 0x00000ada (2778 cycles)
- **RNG init cycles**: 0x00000683 (1667 cycles)  
- **Core run cycles**: 0x0000ad99 (44441 cycles)

**Expected:** Batch cycles should total entire execution window from start to Done.
- Expected: RNG + Core ≈ 1667 + 44441 = **~46108 cycles**
- Actual: **2778 cycles** (way too small)

### Root Cause Suspects
1. `batch_timing_active_s` turns off too early (before core actually completes all 16 runs)
2. `core_done_s` asserts unexpectedly fast
3. Frontier module finishing prematurely or not running full 16 iterations
4. Logic error in WAIT_DONE state transition

### Investigation Steps
- Enable verbosity on `frontier_done_s` transitions via `report` statements
- Verify frontier completes exactly 16 times before Done asserts
- Check timing of `batch_timing_active_s` deassert vs `core_done_s` assert
- Confirm percolation_core doesn't pre-exit on first completion

### Current Status
⚠️ **Timing metric unreliable** — core logic works (StepCount=16, SpanningCount=16), but batch window capture broken.

---

## 2. Dead Signal: `p_spanning`

### Issue
Signal `p_spanning` is declared in percolation_core.vhd but:
- Never assigned
- Never read
- Dead code clutter

### Impact
- None on correctness (spanning count uses `frontier_spanning_s` directly)
- Minor: adds noise to synthesis and simulation

### Fix
Remove declaration and all references to `p_spanning`.

### Current Status
✓ **Non-blocking** — does not affect functionality, only cleanup.

---

## 3. Working Elements (Verified)

✓ StepCount = 0x10 (16 runs completed correctly)  
✓ SpanningCount = 0x10 (all runs spanned)  
✓ TotalOccupied = 0x9992 (placeholder reasonable for site percolation)  
✓ Status = 0x00000000 (success)  
✓ RNG init cycles > 0 (counts while RNG busy during init)  
✓ Core run cycles > 0 (counts during core execution)

---

## Action Items

- [ ] Enable frontier completion logging in percolation_core state machine
- [ ] Trace batch_timing_active_s over full sim run
- [ ] Verify core_done_s timing against 16-run completion
- [ ] Remove `p_spanning` signal (cleanup)
- [ ] Re-run sim with fixes and validate batch_cycles ≈ 46108
