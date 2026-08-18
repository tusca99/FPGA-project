# Percolation Core

Data-plane for site percolation on FPGA. Single-clock 100 MHz.

## Current Implementation

### Modules

| File | Role |
|------|------|
| `percolation_core.vhd` | Top-level controller: orchestrates RNG + frontier, accumulates statistics |
| `percolation_bfs_frontier.vhd` | Row-wise reachability engine (bidirectional associative prefix scan) |
| `percolation_uart_top.vhd` | UART wrapper: 16-byte request/response, no algorithmic logic |
| `percolation_core_tb.vhd` | Standalone testbench for core validation |
| `percolation_uart_top_tb.vhd` | End-to-end UART testbench |

### Key Features

- **RNG**: $N_{\text{rows}}$ independent Trivium stream ciphers (one per column), AES-CTR seeded, producing $N_{\text{rows}}$ random bits/cycle
- **Frontier**: Bidirectional associative prefix scan for exact horizontal closure in 3 cycles/row (pipelined)
- **Statistics**: StepCount, SpanningCount, TotalOccupied, SpanningOccupied
- **Grid shape**: Width fixed at `N_ROWS_G` (compile-time, default 64), height from `CfgStepsPerRun` (runtime)

### Algorithm
1. Core waits for RNG ready (`rng_busy='0'`, `rng_all_valid='1'`)
2. For each run, streams `CfgStepsPerRun` rows to the frontier
3. Frontier computes reachability row-by-row:
   - Row 0: seed = open (all open sites are starting points)
   - Row N: seed = open AND previous_reach (vertical propagation)
   - Horizontal closure via prefix scan (see `bfs_frontier.md`)
4. After last row: if any reach bit set → spanning detected
5. Core accumulates: occupied sites per run, spanning-occupied sites per run

### Interface

```vhdl
entity percolation_core is
    generic (N_ROWS_G : positive := 64);
    port (
        Clk            : in std_logic;
        Rst            : in std_logic; -- active low
        RunEn          : in std_logic;
        StepAddValid   : in std_logic;
        StepAddCount   : in std_logic_vector(31 downto 0);
        CfgP           : in std_logic_vector(31 downto 0); -- UQ32 threshold
        CfgStepsPerRun : in unsigned(31 downto 0);
        CfgSeed        : in std_logic_vector(31 downto 0);
        CfgRuns        : in std_logic_vector(31 downto 0);
        CfgInit        : in std_logic;
        StepCount      : out std_logic_vector(31 downto 0);
        SpanningCount  : out std_logic_vector(31 downto 0);
        TotalOccupied  : out std_logic_vector(31 downto 0);
        SpanningOccupied : out std_logic_vector(31 downto 0);
        Done           : out std_logic
    );
end entity;
```

### Timing per Run (N=64, GridSteps=64)

The frontier's own pipeline is **3 cycles/row** (`RUN_READY → RUN_COMPUTE → RUN_SAVE`).
However, the core drives the row handshake with **registered** `ChunkValid`/`ChunkOpen`
while the frontier's `Busy` is combinatorial, so the frontier waits one extra cycle in
`RUN_READY` for the row to arrive. The **end-to-end** cost is therefore **4 cycles/row**.

| Phase | Cycles | Description |
|-------|--------|-------------|
| Start overhead | 1 | Core asserts `frontier_start_s` |
| Row streaming | 64 × 4 | 3-cycle prefix scan + 1-cycle registered-send handshake |
| Done detection | 1 | Frontier asserts `Done` |
| Accumulation | 1 | Core adds `run_occupied` to `occupied_sum` |
| **Total** | **~259** | Per run at 64 rows (4·64 + 3) |

> **Note on the 4 cyc/row**: this is a handshake artifact, not a frontier inefficiency.
> The measured hardware fit of `core_latency_per_run_cycles_est` vs `steps` gives a slope
> of ~3.99 cyc/step, matching the 4 cyc/row model. The frontier's prefix-scan pipeline
> itself is 3 cycles/row; the extra cycle is the registered row-send in `percolation_core.vhd`.

## Validation

- Threshold ~0.6047 for directed percolation on 64×64 (expected ~0.605)
- Occupancy bias < 0.001 vs probability p
- Prefix scan validated against BFS reference (1000 random grids)
- Frontier latency is pipelined: 3 cycles per row internally, 4 cycles/row end-to-end
  including the registered-send handshake, so 64 rows cost about 259 cycles

## Doc Links

- [BFS Frontier Algorithm](bfs_frontier.md) — Prefix scan reachability details
- [Core Schema](percolation_core_schema.md) — Conceptual architecture
- [UART Protocol](UART_PROTOCOL.md) — Binary frame layout
- [RNG Architecture](../rng/RNG.md) — Trivium + AES-CTR seeding
- [UART Binary Scaffold](../uart_message_bin/README.md) — Wrapper details
- [Python Tools](../../python/README.md) — Host-side validation
