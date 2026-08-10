# Percolation Core — Conceptual Schema

## Overview

The core performs multiple independent trials of site percolation on a 2D grid strip:

1. **Width**: fixed at compile-time by `N_ROWS_G` (default 64)
2. **Height**: runtime parameter `CfgStepsPerRun` (e.g., 64 for square grid)
3. **Occupancy**: each site open with probability `p` = `CfgP` (UQ32 fixed-point)
4. **Goal**: determine if an open path exists from top row to bottom row

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    percolation_core.vhd                       │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │   RNG Bank  │───▶│   Core FSM  │───▶│   Frontier      │ │
│  │(N_ROWS_G    │    │ (orchestrate)│    │ (reachability)  │ │
│  │ Trivium)    │    │             │    │                 │ │
│  └─────────────┘    └─────────────┘    └─────────────────┘ │
│         │                  │                      │           │
│         │ site_open[0..63] │ row_bits            │ ChunkOpen │
│         │ (every cycle)    │ (when frontier      │ (valid)   │
│         │                  │  ready)             │           │
│         ▼                  ▼                      ▼           │
│     Random bits         Occupancy row         Reachability    │
│     vs threshold        sent to frontier      computed via    │
│                         (4 cycles/row)       prefix scan       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  Statistics     │
                    │  StepCount      │
                    │  SpanningCount  │
                    │  TotalOccupied  │
                    │  SpanningOccupied│
                    └─────────────────┘
```

## High-Level Interface

| Signal | Direction | Description |
|--------|-----------|-------------|
| `Rst` | In | Active-low reset |
| `CfgInit` | In | Load config, reset state |
| `RunEn` | In | Start batch execution |
| `CfgP` | In | Occupation probability (UQ32) |
| `CfgStepsPerRun` | In | Grid height (rows per run) |
| `CfgSeed` | In | RNG seed |
| `CfgRuns` | In | Maximum runs in batch |
| `StepCount` | Out | Completed runs |
| `SpanningCount` | Out | Runs with spanning cluster |
| `TotalOccupied` | Out | Sum of occupied sites across all runs |
| `SpanningOccupied` | Out | Sum of reachable sites in spanning runs |
| `Done` | Out | Batch complete |

## Connectivity Backend: Row-Wise Frontier

The frontier processes the grid row-by-row without storing the full grid:

1. **Receive occupancy**: `open = ChunkOpen` (from RNG bank)
2. **Vertical seeding**:
   - Row 0: `seed = open` (all open sites are seeds)
   - Row N: `seed = open AND previous_reach` (only sites above reachable ones)
3. **Horizontal closure**: compute all sites reachable from any seed via contiguous open cells
4. **Save**: `previous_reach = reach` for next row
5. **Spanning check**: last row has any reachable site → spanning

### Horizontal Closure Methods

| Approach | Correctness | Timing (100MHz, N=64) | Throughput | Latency |
| :--- | :--- | :--- | :--- | :--- |
| Naive ±1 loop | ✅ | ❌ (too deep) | 1 row/clk | 1 clk |
| Combinatorial mask (log2 stages) | ✅ | ⚠️ (marginal) | 1 row/clk | 1 clk |
| **Associative prefix scan** | ✅ | ✅ | **1 row/3 clks** | **3 clks** |
| Pipelined prefix (3 cycles) | ✅ | ✅ | 1 row/3 clks | 3 clks |

**Current choice**: Pipelined associative prefix scan (bidirectional Kogge-Stone style).
Mathematically equivalent to iterative ±1 propagation, but the RTL uses three registered stages per row.

> **End-to-end cost**: the frontier pipeline is 3 cycles/row, but the core's registered
> row-send handshake adds 1 cycle/row, so the measured end-to-end throughput is
> **1 row/4 clks** (hardware fit slope ~3.99 cyc/step).

## Operational Flow

```
on reset:
    clear all counters and state

on CfgInit:
    load p, seed, runs_target, steps_per_run
    reset statistics

while runs_done < runs_target:
    1. Wait for RNG ready
    2. Assert frontier_start
    3. Stream CfgStepsPerRun rows:
       - Fetch N_ROWS_G bits from RNG
       - Send to frontier (ChunkValid + ChunkOpen)
       - Frontier computes reachability in 1 cycle
    4. When frontier_done:
       - Increment StepCount
       - If spanning: increment SpanningCount
       - Accumulate TotalOccupied and SpanningOccupied
```

## Top Application Wrapper

`percolation_uart_top.vhd` integrates the core with UART:
- Receives 16-byte configuration via UART
- Loads parameters and starts core
- Captures 16-byte response when Done
- Forwards response via UART
- Contains **no algorithmic logic**

## Binary Frame Layout

- **Request (16 bytes)**: `[CfgP (4B)] [CfgSeed (4B)] [CfgStepsPerRun (4B)] [CfgRuns (4B)]`
- **Response (16 bytes)**: `[StepCount (4B)] [SpanningCount (4B)] [TotalOccupied (4B)] [SpanningOccupied (4B)]`

## Validation Results

- Threshold ~0.6047 for directed percolation on 64×64 (expected ~0.605)
- Occupancy bias < 0.001 vs probability p
- Prefix scan validated against BFS reference (1000 random grids)
- Mass (avg reachable sites in spanning runs) ~1800 at criticality

## Doc Links

- [BFS Frontier](bfs_frontier.md) — Prefix scan algorithm details
- [UART Protocol](UART_PROTOCOL_V2.md) — Binary frame specification
- [RNG Architecture](../rng/RNG.md) — Trivium + AES-CTR seeding
- [Core README](README.md) — Module-level documentation
