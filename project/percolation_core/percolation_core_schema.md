# Percolation Core - Conceptual Schema

This document explains the operation of the percolation core in `percolation_core.vhd` and provides a common overview for the connectivity backends, both designed for row-wise processing.

## General Idea

The core performs multiple trials:

1. Constructs a strip of cells with a fixed width `N_ROWS_G`.
2. Determines which cells are occupied using a separate RNG bank of width `N_ROWS_G` (currently `N_ROWS_G = 64` in debug builds).
3. Checks if a cluster spans the strip from top to bottom.
4. Updates statistics.
5. Repeats for the requested number of runs.

Essentially, it answers: "With a given occupation probability `p`, how often does a random grid percolate?"

## High-Level Interface

- `Rst`: Resets everything.
- `CfgInit`: Loads parameters and resets internal state.
- `RunEn`: Starts the core.
- `StepAddValid` / `StepAddCount`: Adds runs to the queue.
- `CfgP`: Sets occupation probability.
- `CfgStepsPerRun`: Sets how many rows to process per run (32-bit unsigned).
- `CfgSeed`: Seeds the RNG bank.
- `CfgRuns`: Sets the maximum number of runs.
- `N_ROWS_G`: Row width fixed at compile-time.

**Statistics Outputs**:
- `StepCount`: Number of completed runs.
- `PendingSteps`: Runs remaining in queue.
- `SpanningCount`: Number of runs that percolated.
- `TotalOccupied`: Sum of occupied cells across all runs.

## Connectivity Backend: The Row-Wise Frontier

The core uses a "Frontier" approach to determine reachability without needing a full grid in memory.

### The Challenge: Horizontal Closure
To correctly identify if a cluster spans the grid, we must resolve all horizontal connections within a row before moving to the next. A cluster can "snake" across a row; simply checking $\pm 1$ neighbor once is insufficient.

#### 1. The Naive Loop (Sequential)
Iterate $N$ times: `reach(i) = open(i) AND (reach(i-1) OR reach(i+1) OR top(i))`.
- **Problem**: Creates a combinatorial chain of length $N$. For $N=64$, this is too deep for 100MHz $\to$ **Timing Failure**.

#### 2. The Bitmask Approach (Parallel Prefix)
Instead of 1-cell steps, we use shifts of $2^k$ ($1, 2, 4, 8, 16, 32$).
- **Logic**: `reach = reach OR ((reach <<< d d OR reach >> d) AND open)`.
- **Efficiency**: Resolves all connections in $\log_2(N)$ stages (6 stages for $N=64$).
- **Problem**: Even $\log_2(N)$ stages in one clock cycle, combined with RNG logic, can exceed the 10ns period $\to$ **Timing Failure**.

#### 3. The Pipelined Solution (Current Implementation)
We keep the $\log_2(N)$ logic but break the chain with registers.
- **Throughput**: Still 1 row per clock.
- **Latency**: $\log_2(N) + 1$ clocks per row.
- **Timing**: Each stage is a tiny combinatorial path $\to$ **Timing Success**.

## Top Application Wrapper

The wrapper integrates the core with UART and handles:
- Receiving configuration, seeds, and start/stop commands.
- Transferring parameters to the core.
- Reading and forwarding statistics.

It does not contain algorithmic logic. The grid is rectangular: `N_ROWS_G` (compile-time) $\times$ `CfgStepsPerRun` (runtime).

### Binary Frame Layout
- **Request (16 bytes)**: `[CfgP (4B)] [CfgSeed (4B)] [CfgStepsPerRun (4B)] [CfgRuns (4B)]`
- **Response (16 bytes)**: `[StepCount (4B)] [PendingSteps (4B)] [SpanningCount (4B)] [TotalOccupied (4B)]`

## Operational Flow (Pseudocode)

```text
on reset:
    clear states and counters

on CfgInit:
    load p, seed, max runs, and steps per run
    reset statistics

if RunEn = 1 or pending steps > 0:
    while run_count << runs runs_target:
        for row from 0 to CfgStepsPerRun - 1:
            1. Fetch N_ROWS_G bits from RNG bank
            2. Pipeline through log2(N) mask stages to resolve horizontal reachability
            3. Update frontier mask for next row
        
        if final_row_mask has any bit set:
            increment SpanningCount
        
        increment StepCount
        update TotalOccupied
```

## Summary of Trade-offs

| Approach | Correctness | Timing (100MHz) | Throughput | Latency |
| :--- | :--- | :--- | :--- | :--- |
| $\pm 1$ Single Pass | ❌ (Misses snakes) | ✅ | 1 row/clk | 1 clk |
| Naive Loop | ✅ | ❌ (Too deep) | 1 row/clk | 1 clk |
| Bitmask (1-cycle) | ✅ | ❌ (Borderline) | 1 row/clk | 1 clk |
| **Pipelined Bitmask** | ✅ | ✅ | **1 row/clk** | **$\log_2(N)$ clks** |