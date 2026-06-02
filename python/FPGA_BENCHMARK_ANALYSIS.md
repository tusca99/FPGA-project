# FPGA Benchmark Analysis Guide

A catalog of FPGA-engineering analyses for the percolation accelerator UART
benchmark data. These complement the physics-oriented plots in `analysis.py`
by focusing on **pipeline performance, UART overhead decomposition, and
system-level efficiency**.

---

## Table of Contents

1. [Terminology](#1-terminology)
2. [Theoretical Pipeline Model](#2-theoretical-pipeline-model)
3. [Amdahl Speedup & Break-Even Batch Size](#3-amdahl-speedup--break-even-batch-size)
4. [Asymptotic Cycles-Per-Run Fit](#4-asymptotic-cycles-per-run-fit)
5. [Frontier Cost Breakdown](#5-frontier-cost-breakdown)
6. [Pipeline Utilization Efficiency](#6-pipeline-utilization-efficiency)
7. [Grid-Height Invariance](#7-grid-height-invariance)
8. [Determinism & Repeatability](#8-determinism--repeatability)
9. [Throughput Contour Map](#9-throughput-contour-map)
10. [FPGA vs Software Speedup](#10-fpga-vs-software-speedup)
11. [Implementation Notes](#11-implementation-notes)

---

## 1. Terminology

| Symbol | Meaning |
|--------|---------|
| `N` | Grid width (compile-time `N_ROWS_G`, e.g. 64, 128, 180) |
| `S` | Grid height (`CfgStepsPerRun`, runtime configurable) |
| `R` | Number of runs per UART request (`CfgRuns`) |
| `T_total` | Wall-clock time from `client.run()` to response |
| `T_uart` | Theoretical UART wire time = 32 bytes × 10 bits / 115200 baud ≈ 2.78 ms |
| `T_core_est` | `T_total − T_uart` (what `benchmark.py` calls *core latency*) |
| `C_total` | `T_total × 100 MHz` (cycles) |
| `C_core_est` | `T_core_est × 100 MHz` (estimated FPGA + host cycles) |
| `C_ideal` | Theoretical minimum FPGA cycles for S steps, see §2 |

**Important**: `C_core_est` still includes host-side overhead (Python USB-serial
dispatch, OS scheduler jitter) — it is **not** purely FPGA cycles. See §4 for
how to separate the components.

---

## 2. Theoretical Pipeline Model

The percolation core has three pipeline stages:

### RNG warmup (one-time, not per-run)
```
AES seeding:    N_rows × 12 cycles    (128 × 12 = 1536 for N=128)
Trivium warmup: 37 cycles
Total:          1573 cycles ≈ 15.73 µs at 100 MHz
```
This is paid once per `CfgInit`, which occurs once per UART request.
Amortized over R runs: `1573 / R` cycles/run.

### Frontier processing (per row)
The BFS frontier uses a 3-stage pipelined prefix scan:

```
Cycle 1: RUN_READY   — latch row bits
Cycle 2: RUN_COMPUTE — compute reachability
Cycle 3: RUN_SAVE    — save result, compute popcount
```

With fully pipelined operation (a new row accepted every 3 cycles):
```
C_frontier = S × 3  cycles
```

### Per-run overhead
After all S rows are processed, the core state machine does:

```
Cycles for: popcount finalization, spanning check, accumulator update
```

From the asymptotic fit (see §4), this is about **110–120 cycles** per run.

### Ideal total per run (no amortization, no host)
```
C_ideal_per_run = 1573/S + S×3/R + overhead_per_run
                 ≈ 1573/R + 3×S + 115     for large S,R
```

### Where the gap comes from

The measured `C_core_est` is **much larger** than `C_ideal` at small R because:

| Component | Cycles (R=1, S=64) | Cycles (R=16384, S=64) |
|-----------|-------------------:|-----------------------:|
| UART wire (subtracted) | 278k | 278k |
| Host overhead (Python + USB + OS) | ~226k | ~0 (amortized) |
| RNG warmup | 1573 | 0.1 |
| Frontier (S×3) | 192 | 192 |
| Per-run state machine | ~115 | ~115 |
| **C_core_est** | **~234k** | **~310** |

The host overhead dominates at small R. At large R (≳ 4096) it amortizes away
and `C_core_est` approaches the FPGA-only cost.

---

## 3. Amdahl Speedup & Break-Even Batch Size

### Concept

The total latency decomposes into a **fixed** part (UART wire + host dispatch)
and a **scalable** part (FPGA computation):

```
T_total(R) = T_fixed + R × T_per_run
```

Speedup relative to single-run:

```
Speedup(R) = T_total(1) / T_total(R)
```

### What to plot

**Figure 3a**: `R` (x-axis, log₂ scale) vs `latency_s` (y-axis, log scale)
for several grid heights S. Each curve should show:

- Flat region (R ≲ 16): latency dominated by fixed overhead
- Linear scaling (R ≳ 256): latency ≈ R × T_per_run

**Figure 3b**: `R` vs `Speedup(R)`. The classic Amdahl curve where speedup
saturates at `1 / (1 − scalable_fraction)`.

### What to extract

- **Break-even batch size**: The smallest R where the FPGA computation time
  exceeds the fixed overhead. Read from the intersection of T_fixed and
  R × T_per_run in the decomposition fit.

- **Amdahl limit**: Maximum achievable speedup given the fixed serial fraction.

### Data source

`benchmark-2.sqlite3`: sessions with `effective_hw_width=128`, all
`runs` values at the same p (≈0.60), for each `steps` value.

<details>
<summary>Example data (N=128, p≈0.60, S=64)</summary>

| runs | latency_s | runs/s | speedup |
|-----:|----------:|-------:|--------:|
| 1 | 0.005115 | 195 | 1.0× |
| 4 | 0.005164 | 775 | 4.0× |
| 16 | 0.005735 | 2790 | 14.3× |
| 64 | 0.005582 | 11466 | 58.7× |
| 256 | 0.005654 | 45279 | 231.7× |
| 1024 | 0.021609 | 47389 | 242.5× |
| 4096 | 0.021758 | 188255 | 963.0× |
| 16384 | 0.053606 | 305639 | 1564.0× |

</details>

---

## 4. Asymptotic Cycles-Per-Run Fit

### Concept

Model `C_core_est(R)` as:

```
C_core_est(R) = C_fixed / R + C_marginal
```

Where:
- `C_fixed` = RNG warmup + host dispatch overhead (cycles, independent of R)
- `C_marginal` = true per-run FPGA cost (frontier + state machine)

A weighted linear fit of `C_core_est × R` vs `R` gives:

```
C_core_est × R = C_fixed + C_marginal × R
```

### What to plot

**Figure 4**: `R` vs `C_core_est` with the fitted curve overlaid.
Include the asymptote `C_marginal` as a horizontal dashed line.

### What to extract

| Quantity | Meaning |
|----------|---------|
| `C_marginal` | True FPGA cycles/run (frontier + SM overhead) |
| `C_fixed` | Host + RNG warmup overhead (one-time per request) |
| `ratio = C_marginal / (S × 3 + 115)` | Efficiency relative to naive pipeline model |
| `host_only = C_fixed − 1573` | Host-side overhead in cycles |

### Data source

Same as §3 — use the full runs sweep at a single `p` and `steps`.

---

## 5. Frontier Cost Breakdown

### Concept

The marginal cycles per run depend on grid height S:

```
C_marginal(S) = C_per_run_overhead + S × C_per_step
```

Fitting across S separates:
- **Per-run overhead**: state machine transitions, finalization (constant)
- **Per-step cost**: frontier pipeline cost per row

From the VHDL, the ideal frontier pipeline gives `C_per_step = 3 cycles`.
The fit tells you how close reality is.

### What to plot

**Figure 5**: `S` (x-axis) vs `C_marginal` (y-axis) with linear fit.

### What to extract

| Quantity | Meaning |
|----------|---------|
| Slope | `C_per_step` — should be close to 3 |
| Intercept | `C_per_run_overhead` — state machine fixed cost |
| Deviation from 3 | Pipeline bubbles or stalls |

### Data source

Use sessions with large R (e.g. 16384) across all S values at fixed
`p` ≈ 0.60. This minimizes host overhead contamination.

<details>
<summary>Example data (N=128, runs=16384, p≈0.60)</summary>

| steps | core_cyc/run | total_core_cycles | frontier_ideal (S×3) | overhead |
|------:|-------------:|------------------:|--------------------:|---------:|
| 64 | 310 | 5,079,040 | 192 | 118 |
| 128 | 600 | 9,830,400 | 384 | 216 |
| 256 | 1089 | 17,842,176 | 768 | 321 |
| 512 | 2067 | 33,865,728 | 1536 | 531 |
| 768 | 3145 | 51,527,680 | 2304 | 841 |
| 1024 | 4118 | 67,469,312 | 3072 | 1046 |

</details>

---

## 6. Pipeline Utilization Efficiency

### Concept

Once host overhead is negligible (large R), compare measured cycles/run to the
theoretical minimum:

```
Efficiency = (S × 3 + ~115) / C_marginal(S)
```

Where `~115` is the per-run state machine overhead (from §5 intercept).

### What to plot

**Figure 6a**: `S` vs `Efficiency` for large R (16384).

**Figure 6b**: `S` vs the **excess** `C_marginal(S) − (S × 3 + 115)`.
This shows absolute pipeline waste in cycles.

### What to extract

- **Peak efficiency**: best-case utilization of the pipeline (should be
  ≥ 85% at large S)
- **Efficiency trend**: does the pipeline sustain efficiency or degrade
  at large S? (potential memory/register bottleneck)

---

## 7. Grid-Height Invariance

### Concept

A well-pipelined design should sustain constant **cells per second**
regardless of grid height, because:

```
cells/s = N × S × R / T_total
```

If the pipeline runs at line-rate, `T_total` scales linearly with `S × R`,
so cells/s is constant.

### What to plot

**Figure 7**: `S` (x-axis) vs `cells/s` (y-axis) for several values of `R`.
Each series should be roughly flat if the pipeline is efficient.

### What to extract

- **Pipeline throughput stability**: variance of cells/s across S
- **Degradation point**: S where throughput drops → identify pipeline bubble

### Interpretation of existing data

From N=128, runs=16384:

| steps | cells/s | Normalized to S=64 |
|------:|--------:|-------------------:|
| 64 | 2.50e9 | 1.00× |
| 128 | 2.66e9 | 1.06× |
| 256 | 2.96e9 | 1.18× |
| 512 | 3.14e9 | 1.26× |
| 768 | 3.11e9 | 1.24× |
| 1024 | 3.17e9 | 1.27× |

Throughput actually **increases** slightly with S — the fixed RNG warmup
amortizes better over taller grids. The pipeline shows no degradation up
to S=1024.

---

## 8. Determinism & Repeatability

### Concept

Each (p, runs, steps) configuration has 20 repeat measurements. The
coefficient of variation (CV = σ/μ) of `latency_s` across repeats measures
system noise.

- **Very low CV** (< 1%): FPGA is deterministic, noise is from UART bit
  timing quantization
- **High CV** (> 5%): host scheduling, USB jitter, or OS interference

### What to plot

**Figure 8**: `p` (x-axis) vs `CV(latency_s)` (y-axis) as a scatter/bar.
Color by `runs` value.

### What to extract

- **Typical CV**: baseline noise level of the measurement setup
- **Outliers**: configurations with anomalously high jitter (→ investigate
  host load at that time)
- **Trend with R**: CV should decrease with larger R (law of large numbers)
  if noise is random

### Data source

Any session with `repeats > 1`. The finest is `ba1fe7e8` (200 p-points ×
50 repeats × 131072 runs, N=180).

---

## 9. Throughput Contour Map

### Concept

A 2D heatmap of `cells/s` with `p` on x-axis, `steps` on y-axis, and
color = log₁₀(cells/s). This shows the FPGA's operating envelope.

### What to plot

**Figure 9**: 2D contour/fill plot. Use the full runs-sweep data for a
fixed large batch size (e.g. runs=16384).

### What to extract

- **Sweet spot**: (p, S) region with maximum throughput
- **Occupancy effect**: does higher p reduce throughput? (more frontier
  work in the scan)
- **Grid-height effect**: does the pipeline need a minimum S to reach
  peak throughput?

---

## 10. FPGA vs Software Speedup

### Concept

Overlay the hardware throughput against a software reference.

```
Speedup = cells_per_s_HW / cells_per_s_SW
```

### What to plot

**Figure 10a**: `p` vs `cells/s` with two curves: HW and SW.

**Figure 10b**: `p` vs `log₂(Speedup_HW_vs_SW)`.

### What to extract

- **Speedup at threshold**: SW is fast near p=0.5 (sparse grids), HW wins
  at p ≈ p_c (dense grids)
- **Crossing point**: p where HW overtakes SW
- **Maximum speedup**: best-case advantage

### Data source

`benchmark.sqlite3` sessions `16456613` and `1ba9a5c9` (mixed SW+HW mode).

---

## 11. Implementation Notes

### Data loading

All data is in `python/output/benchmark-2.sqlite3` (FPGA data) and
`python/output/benchmark.sqlite3` (FPGA + software data). Use the
helpers in `percolation_uart.analysis`:

```python
from percolation_uart import analysis
from pathlib import Path

db = Path("python/output/benchmark-2.sqlite3")
conn = analysis._connect(db)
raw = analysis.load_raw_rows(conn, session_id="<session-uuid>")
```

### Filtering for the runs-sweep

All sweep sessions use the same p-range [0.53, 0.68] with 20 points.
To extract data at a fixed p ≈ 0.60:

```python
# Find the row with p closest to 0.60 for each session
import math
rows_at_p = sorted(raw, key=lambda r: abs(float(r["p"]) - 0.60))
closest = rows_at_p[0]
```

### Latency decomposition helper

```python
UART_WIRE_S = 32 * 10 / 115200  # ≈ 0.002778 s
RNG_WARMUP_CYCLES = 1573

def decompose_latency(row):
    """Decompose a HW raw row into its components."""
    runs = float(row["runs"])
    steps = float(row["steps"])
    total_s = float(row["latency_s"])
    uart_s = UART_WIRE_S
    host_s = max(0.0, total_s - uart_s)
    
    # FPGA-side
    rng_warmup_s = RNG_WARMUP_CYCLES / 100e6
    frontier_ideal_s = steps * 3 / 100e6
    sm_overhead_s = 115 / 100e6
    
    total_cycles = total_s * 100e6
    per_run_cycles = total_cycles / runs
    
    return {
        "total_s": total_s,
        "uart_s": uart_s,
        "host_s": host_s,
        "per_run_cycles": per_run_cycles,
        "rng_warmup_per_run_s": rng_warmup_s / runs,
        "frontier_per_run_s": frontier_ideal_s,
    }
```

### Plotting conventions

- Use `matplotlib` with `Agg` backend for file output (as in `analysis.py`).
- Save to `python/output/analysis/` with descriptive filenames.
- Use log scales where the data spans orders of magnitude (runs, latency).
- Label axes with physical units (cycles, seconds, cells/s).

### When to prefer benchmark-2 over benchmark

| Data | DB | Sessions |
|------|----|----------|
| FPGA-only runs sweep (N=128, N=180) | `benchmark-2` | Full factorial: runs × steps |
| FPGA-only fine sweep (N=180, 200 pts) | `benchmark-2` | `ba1fe7e8` (best for physics) |
| SW reference data | `benchmark` | Mixed SW+HW sessions |
| HW data at N=128 with high repeats | `benchmark` | `63343d77` (10×300k runs) |
| HW data at N=128 fine sweep | `benchmark` | `c06f384a` (100 points × 10 repeats) |