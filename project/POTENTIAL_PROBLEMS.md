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

---

## 3. Frontier Single-Cycle Limit / Tiled Scaling

### Question
Can the whole frontier update stay in one clock cycle, the same way the current row-step idea is drawn?

### Short Answer
Only if the combinational depth still fits inside the clock period. At 128 columns this may be practical, but the limit is timing closure, not the algorithm itself.

### What the Tiled Idea Means
The tiled version does **not** mean one giant combinational pass over the whole row. It means:
- split the row into smaller fixed-width tiles
- process tiles in sequence
- carry only the boundary reachability between tiles
- keep the dataflow streaming and one-pass over the row data

### Important Distinction
- **Single-cycle row update:** possible only when the whole row logic meets timing
- **Tiled frontier:** still one logical pass, but usually staged or pipelined across tiles

### Practical Read
- 128 columns: one-cycle may still close
- 512 columns: likely borderline
- 1024 columns: a tiled or pipelined frontier is the safer architecture

### Current Status
ℹ️ **Architectural scaling note** — keep the current generic frontier for now, but treat tiling as the follow-up path when width grows beyond what timing can hold.

---
✓ StepCount = 0x10 (16 runs completed correctly)  
✓ SpanningCount = 0x10 (all runs spanned)  
✓ TotalOccupied = 0x9992 (placeholder reasonable for site percolation)  
✓ Status = 0x00000000 (success)  
✓ RNG init cycles > 0 (counts while RNG busy during init)  
✓ Core run cycles > 0 (counts during core execution)

## 4. RX Frame Width / Observability Confusion

### Observed Issue
- `captured_step_count` and `core_step_count_s` still looked 32-bit

- `tx_msg_s` is also **128 bits**
- `core_cfg_runs_s` is `std_logic_vector(31 downto 0)`, so it is **32 bits**
- `core_cfg_steps_s` is `unsigned(31 downto 0)`, so it is **32 bits**

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

## 5. BRAM Timing Hint

### Observed Issue
Vivado reports a timing hint on a Block RAM in the RNG/key-schedule path. It is a warning about timing margin, not a functional failure.

### What It Likely Means
- the BRAM output path may be a little too long for the current clock target
- the fix is usually a register boundary or a small pipeline cleanup near the RAM output
- the issue is more about Fmax margin than correctness

### Why It Is Not the First Priority
- the design already synthesizes successfully
- the current functional focus is still the percolation core and its control/reporting flow
- timing closure work is better done after the logic is stable

### Current Status
ℹ️ **Documented for later** — do not treat it as the active blocker unless timing begins to fail.

## 6. Routed Timing Failure

### Observed Issue
Implementation completed, but `route_design` ended with a timing violation:
- `WNS = -0.324 ns`
- `TNS = -8.160 ns`

### What It Means
- the design is functionally routed and bitstream generation still succeeds
- the target clock is not fully met after routing
- the critical path is now a real implementation problem, not just a synthesis hint

### What The Report Points At
The worst paths include:
- `percolation_uart_top_slim/core_inst/frontier_inst/FSM_onehot_state_reg[*]`
- `percolation_uart_top_slim/core_inst/run_occupied_reg[22]`

### Likely Interpretation
The timing pressure is not isolated to one tiny net. It is spread across frontier control, occupancy accumulation, and the RNG/control path that also appears in the phys-opt report.

### Current Status
❗ **Active implementation issue** — the routed design works, but timing closure still needs a follow-up pass.

## 7. Debug Core / XDC Mismatch

### Observed Issue
`pins.xdc` still references probe nets such as `core_cfg_p_s[*]`, `core_spanning_s[*]`, `core_cfg_seed_s[*]`, and `core_cfg_steps_s[*]`, but implementation reports that no matching nets were found and that debug core `u_ila_0` was not found.

### What It Means
- the constraint file still contains debug wiring for a debug core that is not present in the current netlist
- the synthesis/implementation flow keeps warning about the missing nets
- this does not stop the build, but it means the debug constraints are stale

### Why It Matters
- the warnings hide real timing messages in a wall of noise
- the ILA-based observability path is not aligned with the current top
- probe names in `pins.xdc` likely need to be updated or removed if debug is no longer used

### Current Status
⚠️ **Stale debug constraints** — safe for the bitstream, but they should be cleaned up to keep implementation output readable.

## 8. Legacy UART Ports Left Unused

### Observed Issue
Synthesis reported:
- `Port baud_tick in module uart_rx is either unconnected or has no load`
- `Port half_tick in module uart_rx is either unconnected or has no load`

### What It Means
- the active design no longer consumes these ports
- they are most likely legacy interface remnants from an older UART variant
- synthesis ignores them, but they create noise and can confuse later debugging

### Why It Matters
- it suggests the top-level UART chain still carries legacy shape from the modular tree
- unused ports make it harder to tell whether a signal is genuinely broken or just obsolete
- if these ports are no longer required, the clean fix is to remove them from the active interface or tie the design to the self-timed RX path only

### Current Status
ℹ️ **Non-blocking cleanup item** — not a functional bug, but worth removing once the active UART interface is fully settled.

---

## Action Items

- [ ] Enable frontier completion logging in percolation_core state machine
- [ ] Trace batch_timing_active_s over full sim run
- [ ] Verify core_done_s timing against 16-run completion
- [ ] Clean up stale debug/ILA constraints in pins.xdc
- [ ] Decide whether the legacy UART tick ports should be removed from the active tree
- [ ] Re-run sim with fixes and validate batch_cycles ≈ 46108
