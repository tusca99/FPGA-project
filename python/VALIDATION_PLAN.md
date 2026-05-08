# FPGA Percolation Validation Plan

## 1. Objectives

1. **Confirm the `occupied_sum` bug is fixed** (or prove it never occurs).
2. **Prove the FPGA algorithm matches the BFS reference** for identical seeds.
3. **Validate end-to-end hardware** via UART and compare with Python simulators.

---

## 2. Known Issues & Fixes

### 2.1 `occupied_sum` Bug (FIXED in `percolation_core.vhd`)

**Problem:** In state 1, when `popcount_valid_reg='1'` and `frontier_done_s='1'` coincide in the same cycle, the `run_occupied_v` variable was updated *after* `occupied_sum` used it:

```vhdl
-- OLD (buggy) order:
if popcount_valid_reg = '1' then
    run_occupied_v := run_occupied_v + resize(popcount_reg, 32);  -- update A
end if;
if frontier_done_s = '1' then
    occupied_sum <= occupied_sum + run_occupied_v;               -- uses OLD value!
end if;
```

**Fix:** Reordered so the popcount accumulation happens *before* the done check:

```vhdl
-- NEW (fixed) order:
if popcount_valid_reg = '1' then
    run_occupied_v := run_occupied_v + resize(popcount_reg, 32);  -- update A
end if;

if frontier_done_s = '1' then
    occupied_sum <= occupied_sum + run_occupied_v;               -- uses NEW value
end if;
```

**Verification:**
- [ ] Run `percolation_core_tb.vhd` with `N_ROWS_G=4`, `CfgStepsPerRun=4`, `CfgRuns=1`.
- [ ] Check that `TotalOccupied` equals the sum of all row popcounts.
- [ ] Force the coincidence case by using a grid where the last row's popcount is non-zero.

### 2.2 Connectivity Algorithm Equivalence

**Claim:** The FPGA's row-wise frontier with horizontal closure is *mathematically equivalent* to standard 4-neighbor BFS.

**Proof sketch:**
- The FPGA processes rows top-to-bottom.
- For each row, it computes horizontal reachability via `reach_row()` (log2(N) shift-OR stages).
- This resolves all horizontal connections within the row in one cycle.
- Vertical propagation happens naturally: a cell in row `r` is reachable iff it is open AND (it is in the horizontal closure of the seed set, where the seed set is the intersection of the current row with the previous row's reachability).
- This is exactly the same as BFS restricted to the subgraph induced by the grid.

**Risk:** If the FPGA's RNG produces different grids than the Python `Random` for the same seed, the results will diverge even if the algorithm is correct.

---

## 3. Validation Tests

### 3.1 Unit Test: `occupied_sum` Coincidence

**Setup:**
- Use a small grid (e.g., `N_ROWS_G=4`, `CfgStepsPerRun=4`).
- Manually construct a grid where the last row has exactly 1 occupied site.
- Run for 1 run.

**Expected:**
- `TotalOccupied` = sum of popcounts of all 4 rows.
- If the bug existed, `TotalOccupied` would be missing the last row's popcount.

**Command:**
```bash
# In Vivado or ModelSim, run the testbench with the small grid
```

### 3.2 Algorithm Equivalence Test (Python)

**Setup:**
- Run `python -m percolation_uart.fpga_algorithm --compare`.
- This runs both the BFS reference and the FPGA algorithm on the same seeds.

**Expected:**
- For small grids (N=4, 8, 16), the spanning counts and occupied counts should match exactly.
- For N=64, they should match statistically (same seed → same grid → same result).

**Command:**
```bash
cd /home/alessio/ssd_data/Alessio/uni_magistrale/Programmable_Hardware_Devices/FPGA-project/python
source .venv/bin/activate
python -m percolation_uart.fpga_algorithm \
    --grid-width 64 --grid-steps 64 \
    --probability 0.5927 --seed 0x12345678 --runs 100 --compare
```

### 3.3 Hardware End-to-End Test

**Setup:**
- Program the FPGA with the latest bitstream (`alessio-combinatorial-clean`).
- Connect via UART (`/dev/ttyUSB1` or similar).
- Run `python/try.py` or the benchmark script.

**Expected:**
- `StepCount` should equal `CfgRuns`.
- `SpanningCount` should be > 0 for p near critical threshold (0.5927).
- `TotalOccupied` should be ~ p * N^2 * CfgRuns.

**Command:**
```bash
cd /home/alessio/ssd_data/Alessio/uni_magistrale/Programmable_Hardware_Devices/FPGA-project/python
source .venv/bin/activate
python try.py
```

**Comparison:**
- Run the same parameters through the FPGA algorithm simulator:
```bash
python -m percolation_uart.fpga_algorithm \
    --grid-width 64 --grid-steps 64 \
    --probability 0.5927 --seed 0x12345678 --runs 16
```
- Compare `SpanningCount` and `TotalOccupied` from hardware vs simulator.

### 3.4 Benchmark Sweep

**Setup:**
- Run a sweep across probabilities and grid sizes.
- Collect both FPGA and reference data.

**Command:**
```bash
# Reference
python -m percolation_uart.benchmark --backend reference --cfg-runs 100 --samples 10 --output ref.csv

# FPGA (connect board first)
python -m percolation_uart.benchmark --backend fpga --port /dev/ttyUSB1 --cfg-runs 100 --samples 10 --output fpga.csv
```

**Analysis:**
- Plot `SpanningCount / CfgRuns` vs `probability` for both backends.
- They should overlap within statistical noise.

---

## 4. Debugging Checklist

If hardware and simulator disagree:

1. **Check RNG alignment:**
   - Does the FPGA's `rng_hybrid_64` produce the same grid as the Python `_generate_fpga_grid`?
   - Compare row-by-row for the first few runs.

2. **Check frontier logic:**
   - Does `_reach_row()` in Python match `reach_row()` in VHDL?
   - Test with a hand-crafted grid where horizontal closure matters.

3. **Check UART protocol:**
   - Verify request/response byte order (big-endian `>IIII`).
   - Verify `CfgStepsPerRun` is not truncated (lower 16 bits in top).

4. **Check timing:**
   - Is the FPGA completing all runs before responding?
   - Does `Done` assert correctly?

---

## 5. Files Involved

| File | Role |
|------|------|
| `project/percolation_core/percolation_core.vhd` | Core with stats counters |
| `project/percolation_core/percolation_bfs_frontier.vhd` | Row-wise frontier |
| `project/rng/zz_rng_hybrid_64.vhd` | RNG bank |
| `python/percolation_uart/reference.py` | BFS reference simulator |
| `python/percolation_uart/fpga_algorithm.py` | FPGA algorithm simulator |
| `python/percolation_uart/protocol.py` | UART protocol |
| `python/percolation_uart/client.py` | UART client |
| `python/percolation_uart/benchmark.py` | Sweep utilities |
| `python/try.py` | Manual hardware test |

---

## 6. Success Criteria

- [ ] `occupied_sum` bug is verified fixed in simulation.
- [ ] FPGA algorithm simulator matches BFS reference for N=64, p=0.5927, seed=0x12345678.
- [ ] Hardware output matches FPGA algorithm simulator for at least 10 runs.
- [ ] Benchmark sweep shows overlapping curves for FPGA and reference.
