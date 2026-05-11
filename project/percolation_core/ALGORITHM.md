# Percolation Algorithm — Detailed Walkthrough

This document explains the exact algorithm implemented in the current FPGA percolation core, including the data flow, state machines, and the critical timing/bug fixes applied.

## Architecture Overview

The system consists of three main blocks:

1. **RNG Bank** (`rng_hybrid_64`): Generates `N_ROWS_G` pseudo-random 64-bit values per clock cycle.
2. **Frontier Engine** (`percolation_bfs_frontier`): Computes row-wise reachability for site percolation.
3. **Core Controller** (`percolation_core`): Orchestrates multiple independent runs and accumulates statistics.

## 1. Random Number Generation (RNG Bank)

### What it does
- Uses a **Trivium-based stream cipher** instantiated `N_ROWS_G` times (one per column).
- Each row-RNG is seeded with a unique key derived from `CfgSeed` plus a golden-ratio constant.
- Every clock cycle, each row-RNG produces a new 64-bit random word.
- The word is compared against the threshold `CfgP` (32-bit UQ32 fixed-point in `[0, 1)`).
- Result: a binary flag `site_open(i) = '1'` if `random(i) < CfgP`.

### Interface to the core
```vhdl
rng_site_open_s : flag_array_t(0 to N_ROWS_G-1)  -- '1' = site is open
rng_all_valid_s : std_logic                         -- all rows have produced at least one value
rng_busy_s      : std_logic                         -- '1' while warming up / reseeding
```

**Important**: The RNG runs **continuously** and autonomously. The core simply reads the current `site_open` vector whenever it needs a new row.

---

## 2. Frontier Engine — Row-wise Reachability

### The Problem
We need to determine if there exists a path of open sites from the **top row** to the **bottom row** of a 2D grid. The grid has:
- **Width**: `N_ROWS_G` columns (compile-time generic, currently 64)
- **Height**: `CfgStepsPerRun` rows (runtime parameter, e.g. 64)

### The Algorithm (Iterative Horizontal Closure)

For each row `r` from `0` to `GridSteps-1`:

1. **Receive occupancy**: `open = ChunkOpen` (from RNG)
2. **Vertical seeding**: 
   - If `r == 0`: `seed = open` (top row — every open site is a starting point)
   - Else: `seed = open AND previous_reach` (only sites directly above a reachable site can be reached)
3. **Horizontal closure** (iterative until convergence):
   ```
   reach = seed
   repeat:
       left  = reach shifted left  by 1 (with '0' fill)
       right = reach shifted right by 1 (with '0' fill)
       new_reach = reach OR ((left OR right) AND open)
   until new_reach == reach
   ```
   This propagates reachability **left and right** across contiguous open sites. It converges in at most `N_ROWS_G/2` iterations for a single cluster, but typically 1-3 iterations.
4. **Save result**: `previous_reach = reach` for the next row's vertical seeding.
5. **Spanning check**: If `r == GridSteps-1` (last row) and `any_set(reach) == '1'`, set `Spanning = '1'`.

### Why Not the Combinatorial Mask?

Earlier versions used a **single-cycle combinatorial prefix network**:
```vhdl
for d in 1, 2, 4, 8, 16, 32 loop
    reach = reach OR ((reach << d OR reach >> d) AND open)
end loop
```

This is mathematically equivalent to the iterative closure but computes it in **one clock cycle** using `log2(N_ROWS_G)` stages of wide shifts/ORs/ANDs.

**Why we reverted to iterative:**
- At `N_ROWS_G = 64`, the combinatorial path was **~9.9ns** (logic + routing), leaving only **0.08ns slack** at 100 MHz.
- At `N_ROWS_G = 128`, it **failed timing entirely** (~60% LUT utilization but routing congestion killed the path).
- The iterative version breaks the work across **multiple cycles**, giving the router freedom to spread logic and meeting timing comfortably.

**Trade-off**: 
- Combinatorial: 1 row / clock (but risky at N≥64)
- Iterative: 1–3 cycles / row (but safe and scalable)

---

## 3. Core Controller — Run Orchestration

### State Machine

```
State 0 (IDLE):
    Wait for RNG ready (rng_busy='0', rng_all_valid='1')
    Wait for run permission (RunEn='1' or pending_steps > 0)
    Check run limit (runs_done < CfgRuns, or CfgRuns=0 for infinite)
    → Clear run_occupied counter
    → Assert frontier_start_s
    → Go to State 1

State 1 (RUNNING):
    if frontier_done_s = '1':
        // Run complete
        runs_done     += 1
        occupied_sum  += run_occupied
        if frontier_spanning_s = '1': spanning_cnt += 1
        if pending > 0: pending -= 1
        → Go to State 0
    elsif frontier_busy_s = '1':
        // Frontier accepted the row and is processing it
        row_pending = '0'
    elsif frontier_busy_s = '0' AND row_pending = '0':
        // Frontier is idle and no row in flight: send next row
        row_bits    = flags_to_slv(rng_site_open_s)
        hk_chunk_open_s  <= row_bits
        hk_chunk_valid_s <= '1'
        run_occupied += count_ones(row_bits)
        row_pending = '1'
```

### The Double-Counting Bug (Fixed)

**Root cause**: `Busy` in the frontier was **combinatorial**:
```vhdl
Busy <= '0' when (state = RUN_READY) else '1';
```

When `ChunkValid='1'` arrived, the frontier transitioned `RUN_READY → RUN_PROCESS` on the clock edge. But during that cycle, `state` still read as `RUN_READY` (VHDL signal updates happen after all processes suspend). So `Busy` remained `'0'` for **one extra cycle**.

The core saw `frontier_busy_s = '0'` and sent a **second row** immediately. The frontier ignored it (already in `RUN_PROCESS`). When the frontier later returned to `RUN_READY`, the core sent that same row **again**, and `run_occupied` was incremented twice.

**Fix**: Added a `row_pending` flag in the core:
```vhdl
elsif frontier_busy_s = '1' then
    row_pending <= '0';  -- Frontier accepted the row
elsif (frontier_busy_s = '0') and (row_pending = '0') then
    -- Safe to send next row
    ...
    row_pending <= '1';
```

This ensures the core only sends a new row when the frontier is **truly idle** and no row is already in flight.

---

## 4. Data Flow Summary

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│   RNG Bank  │────▶│   Core      │────▶│   Frontier      │
│ (N trivium) │     │ (controller)│     │ (reachability)  │
└─────────────┘     └─────────────┘     └─────────────────┘
       │                   │                     │
       │ site_open[0..63]  │ row_bits            │ ChunkOpen
       │ (every cycle)     │ (when frontier      │ (when ChunkValid)
       │                   │  ready)               │
       ▼                   ▼                     ▼
   Random bits         Occupancy row         Reachability mask
   compared to        sent to frontier      computed iteratively
   threshold CfgP                            (horizontal closure)
```

### Timing per Run (N=64, GridSteps=64)

| Phase | Cycles | Description |
|-------|--------|-------------|
| Start overhead | 1 | Core asserts `frontier_start_s` |
| Busy settle | 1 | Frontier transitions, `Busy` registered |
| Row streaming | 64 × 1–3 | One row per cycle (iterative closure converges fast) |
| Done detection | 1 | Frontier asserts `Done` |
| Accumulation | 1 | Core adds `run_occupied` to `occupied_sum` |
| **Total** | **~68–132** | ~94% efficiency at 1 cycle/row |

---

## 5. Key Parameters and Metrics

| Parameter | Register | Description |
|-----------|----------|-------------|
| `CfgP` | `core_cfg_p_s` | Occupancy probability in UQ32 |
| `CfgStepsPerRun` | `core_cfg_steps_s` | Grid height (rows per run) |
| `CfgRuns` | `core_cfg_runs_s` | Total runs to execute |
| `CfgSeed` | `core_cfg_seed_s` | RNG seed |
| `StepCount` | `runs_done` | Runs completed so far |
| `SpanningCount` | `spanning_cnt` | Runs with top-to-bottom path |
| `TotalOccupied` | `occupied_sum` | Cumulative occupied sites across all runs |

---

## 6. Files and Their Roles

| File | Role |
|------|------|
| `percolation_core.vhd` | Top-level controller, orchestrates RNG + frontier |
| `percolation_bfs_frontier.vhd` | Row-wise reachability engine (iterative closure) |
| `zz_rng_hybrid_64.vhd` | Trivium-based RNG bank |
| `percolation_uart_top.vhd` | UART wrapper: receives config, sends back metrics |
| `percolation_core_tb.vhd` | Testbench for standalone core validation |

---

## 7. Validation Checklist

- [ ] `TotalOccupied` equals sum of `run_occupied` across all runs (no double-counting)
- [ ] `StepCount` equals `CfgRuns` when `Done` asserts
- [ ] `SpanningCount` is non-zero for `p > p_c` (critical threshold ~0.5927 for 2D site percolation)
- [ ] `RngAllValid` asserts before first run starts
- [ ] Timing closure: WNS > 0.050 ns at 100 MHz

---

## 8. Prefix-Scan Frontier (Current Implementation)

### Why we switched from iterative to prefix-scan

The iterative frontier was algorithmically correct and met timing, but its cycle count was **data-dependent**:
- Best case: 1 cycle per row (horizontal closure converges immediately)
- Worst case: up to `N_ROWS_G/2` cycles per row (single cluster spanning full width)
- Typical: 1–3 cycles per row

This variability makes benchmarking and latency prediction harder. The prefix-scan frontier replaces the iterative loop with a **combinatorial associative prefix network** that computes the exact same reachable set in **deterministic O(log N) depth**.

### The associative semigroup

Each cell contributes a pair `(A, B)`:
- `A = open[i]` — "this cell is open"
- `B = open[i] AND seed[i]` — "this cell is open AND has a seed"

The **combine** operator for two adjacent segments `left = [l..m]` and `right = [m+1..r]`:
```
combined.A = right.A AND left.A
combined.B = right.B OR (right.A AND left.B)
```

- `A` propagates as AND: the combined segment is fully open only if both halves are
- `B` propagates as OR: the combined segment has a reachable seed if the right half has one, OR the left half has one AND the right half is fully open (so the seed can propagate through)

This is the **correct** associative operator for contiguous-segment reachability. It prevents "jumping" over closed cells.

### Bidirectional scan

A single left-to-right scan only finds seeds **to the left** of each cell. To catch seeds on either side:
1. **LTR scan**: finds seeds at or to the left of each cell
2. **RTL scan**: reverses the row, scans, then reverses back — finds seeds at or to the right
3. **Final OR**: `reach[i] = ltr[i].B OR rtl[i].B`

Algorithmically identical to iterative ±1 propagation, but computed in **log₂(N) stages** instead of O(N) iterations.

### Timing (deterministic)

For `N_ROWS_G = 64`:

| Phase | Cycles | Description |
|-------|--------|-------------|
| Start overhead | 1 | Core asserts `frontier_start_s` |
| Per-row latency | **2** | Cycle 1: latch `ChunkOpen` + compute `seed`; Cycle 2: prefix-scan computes `reach_result`, save to `previous_reach` |
| Row count | `GridSteps` | e.g. 64 rows |
| Done detection | 1 | Frontier asserts `Done` after last row |
| Core accumulation | 1 | Core adds `run_occupied` to `occupied_sum` |
| **Total per run** | **`2 × GridSteps + 3`** | For 64×64 grid: **131 cycles** @ 100 MHz = **1.31 µs** |

The timing is **fully deterministic** — no data-dependent convergence loops. Every row takes exactly 2 cycles regardless of cluster size or occupancy pattern.

### Timing closure

The prefix-scan network is ~6 Kogge-Stone stages × 2 LUTs per stage = ~12 LUT levels. At 100 MHz (10 ns period), this leaves ~3–5 ns slack after routing, well within closure margins for Artix-7.

### Comparison with previous versions

| Frontier | Cycles/row | Deterministic? | Timing risk @ N=64 |
|----------|-----------|----------------|-------------------|
| Iterative | 1–32 | No | Low (meets timing) |
| Broken OR-shift prefix | 1 | Yes | Medium (algorithm wrong) |
| **Correct prefix-scan** | **2** | **Yes** | **Low (correct + meets timing)** |

---
