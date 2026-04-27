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

## 4. RX Frame Width / Observability Confusion

### Observed Issue
In implementation debug, some probes looked like 8-bit values only:
- `rx_msg_s` appeared as `000000000000000000000000000000ff`
- `core_cfg_runs_s` appeared as `ff`
- `captured_step_count` and `core_step_count_s` still looked 32-bit

### What the RTL Actually Says
The source does **not** define these as 8-bit signals:
- `rx_msg_s` is `std_logic_vector(REQ_BYTES*8-1 downto 0)` with `REQ_BYTES = 16`, so it is **128 bits**
- `tx_msg_s` is also **128 bits**
- `core_cfg_runs_s` is `std_logic_vector(31 downto 0)`, so it is **32 bits**
- `core_cfg_steps_s` is `std_logic_vector(15 downto 0)`, so it is **16 bits**

### Likely Explanation
This is likely not a literal 8-bit RTL definition bug. More likely one of these:
1. The ILA or implementation probe is attached to a truncated fragment or optimized net
2. The RX path is only capturing the last byte before the frame is considered valid
3. The top-level message assembly is not holding the full 16-byte payload in practice

### Why It Matters
If only the low byte is visible in debug, the top may still unpack `CfgRuns` as the low byte only in practice. That would explain the observed `0x000000ff`-style behavior and the zeroed response path.

### Immediate Checks
1. Probe the full bus slices explicitly: `rx_msg_s(127 downto 96)`, `rx_msg_s(95 downto 64)`, `rx_msg_s(63 downto 32)`, `rx_msg_s(31 downto 0)`
2. Probe `core_cfg_runs_s(31 downto 0)` and `core_cfg_steps_s(15 downto 0)` explicitly
3. Confirm request bytes on wire are `e6666666 | 12345678 | 00000064 | 000000ff` for current Python test
4. If ILA still shows only one byte changing, inspect `uart_msg_rx.vhd` capture timing and trigger point, not core datapath

### Current Status
⚠️ **Not yet proven as an RTL width bug**. Source-level widths are correct; remaining question is whether debug probe or RX/message assembly path is only exposing one byte in practice.

---

## Action Items

- [ ] Enable frontier completion logging in percolation_core state machine
- [ ] Trace batch_timing_active_s over full sim run
- [ ] Verify core_done_s timing against 16-run completion
- [ ] Remove `p_spanning` signal (cleanup)
- [ ] Re-run sim with fixes and validate batch_cycles ≈ 46108
