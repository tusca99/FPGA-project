# BFS Frontier — Row-Wise Reachability

## Overview

`percolation_bfs_frontier.vhd` computes row-wise reachability for site percolation.
It processes the grid strip top-to-bottom, keeping only the current row and the previous reachability mask.

**Key property**: exact horizontal closure via associative prefix scan, pipelined over **3 cycles per row**.

## Entity

```vhdl
entity percolation_bfs_frontier is
    generic (N_ROWS_G : positive := 64);
    port (
        Clk           : in std_logic;
        Rst           : in std_logic; -- active low
        CfgInit       : in std_logic;
        GridSteps     : in unsigned(31 downto 0);
        Start         : in std_logic;
        ChunkOpen     : in std_logic_vector(N_ROWS_G - 1 downto 0);
        ChunkValid    : in std_logic;
        Busy          : out std_logic;
        Done          : out std_logic;
        Spanning      : out std_logic;
        ReachPopcount : out unsigned(31 downto 0)
    );
end entity;
```

## Algorithm: Associative Prefix Scan

### The Problem

A cluster can "snake" across a row. Simply checking immediate neighbors once is insufficient.
We need to find all cells reachable from any seed via contiguous open cells.

### The Semigroup

Define a **pair** for each cell: `(A, B)` where:
- `A = open` — cell is open (can be traversed)
- `B = open AND seed` — cell is open AND is a seed (reachability starts here)

**Combine operation** (associative):
```
combine(left=(A_L, B_L), right=(A_R, B_R)):
    A = A_R AND A_L          -- segment is fully open if both halves are
    B = B_R OR (A_R AND B_L) -- reachable if right half has seed, or left half
                               -- seed connects through right half
```

### Bidirectional Scan

1. **Left-to-right prefix scan**: for each cell, does any seed to its **left** (or at it) reach it?
2. **Right-to-left prefix scan**: for each cell, does any seed to its **right** (or at it) reach it?
3. **OR the results**: cell is reachable if any seed in its contiguous open segment reaches it.

### VHDL Implementation

```vhdl
function horizontal_reach(seed, openv : std_logic_vector) return std_logic_vector is
    variable pairs : pair_array_t;
    variable ltr, rtl : pair_array_t;
begin
    -- Build element pairs
    for i in 0 to N_ROWS_G-1 loop
        pairs(i).a := openv(i);
        pairs(i).b := openv(i) and seed(i);
    end loop;

    -- Left-to-right prefix scan
    ltr := prefix_scan_ltr(pairs);

    -- Right-to-left prefix scan (reverse, scan, reverse back)
    rtl := reverse_pairs(prefix_scan_ltr(reverse_pairs(pairs)));

    -- Combine
    for i in 0 to N_ROWS_G-1 loop
        result(i) := ltr(i).b or rtl(N_ROWS_G-1-i).b;
    end loop;
    return result;
end function;
```

The `prefix_scan_ltr` uses Kogge-Stone style doubling (dist = 1, 2, 4, 8, ...).

## State Machine

```
IDLE ──Start──▶ RUN_READY ──ChunkValid──▶ RUN_COMPUTE ──last row──▶ COMPLETE ──▶ IDLE
                      ▲                                              │
                      └──────────────── not last row ────────────────┘
```

- **RUN_READY**: Wait for `ChunkValid`, latch `ChunkOpen`, compute `seed`
- **RUN_COMPUTE**: Compute `reach = horizontal_reach(seed, open)`, register `reach_result`
- **RUN_SAVE**: Save to `previous_reach`, compute popcount; on last row assert `Spanning`
- **COMPLETE**: Assert `Done` (if any reach bit set)

## Timing

| Phase | Cycles | Description |
|-------|--------|-------------|
| Per row (frontier only) | 3 | Pipelined prefix scan (registered stages) |
| Per row (end-to-end) | 4 | 3-cycle scan + 1-cycle registered-send handshake in the core |
| Total run | ~4 * GridSteps + 3 | Start overhead + rows + done |

> **Frontier vs end-to-end cost.** The frontier state machine itself is 3 cycles/row
> (`RUN_READY → RUN_COMPUTE → RUN_SAVE`). The core (`percolation_core.vhd`) drives the
> row handshake with **registered** `ChunkValid`/`ChunkOpen` while the frontier's `Busy`
> is combinatorial, so the frontier idles one extra cycle in `RUN_READY` waiting for the
> row. The measured end-to-end cost is therefore **4 cycles/row** (hardware fit slope
> ~3.99 cyc/step). The Python analysis uses `FRONTIER_CYCLES_PER_STEP = 4` to reflect this.

## Comparison of Methods

| Method | Correctness | Timing (100MHz, N=64) | Throughput | Latency | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Naive ±1 loop | ✅ | ❌ (O(N) depth) | 1 row/clk | 1 clk | Too deep for N=64 |
| Combinatorial mask (shift-OR) | ✅ | ⚠️ (marginal) | 1 row/clk | 1 clk | ~9.9ns at N=64 |
| **Pipelined associative prefix scan** | ✅ | ✅ (~7 LUT levels) | **1 row/3 clks** | **3 clks** | **Current** |

## Validation

- Prefix scan validated against iterative BFS on 1000 random grids (all matched)
- Threshold ~0.6047 for directed percolation on 64×64 (expected ~0.605)
- Occupancy bias < 0.001

## Synthesis Notes

- **N=64**: ~7 LUT levels, easily meets 100 MHz on Artix-7
- **N=128**: the 3-cycle pipelined prefix scan (current implementation) should be used
- **N≥256**: consider tiling or further pipelining

## Doc Links

- [Core README](README.md) — Module overview
- [Core Schema](percolation_core_schema.md) — Full architecture
- [RNG Architecture](../rng/RNG.md) — Random number generation
