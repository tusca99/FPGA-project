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

- **RNG**: 64 independent Trivium stream ciphers, AES-CTR seeded, producing 64 random bits/cycle
- **Frontier**: Bidirectional associative prefix scan for exact horizontal closure in 1 cycle/row
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
        PendingSteps   : out std_logic_vector(31 downto 0);
        SpanningCount  : out std_logic_vector(31 downto 0);
        TotalOccupied  : out std_logic_vector(31 downto 0);
        SpanningOccupied : out std_logic_vector(31 downto 0);
        RngBusy        : out std_logic;
        RngAllValid    : out std_logic;
        Done           : out std_logic
    );
end entity;
```

### Timing per Run (N=64, GridSteps=64)

| Phase | Cycles | Description |
|-------|--------|-------------|
| Start overhead | 1 | Core asserts `frontier_start_s` |
| Row streaming | 64 × 3 | Pipelined prefix frontier = 3 cycles/row |
| Done detection | 1 | Frontier asserts `Done` |
| Accumulation | 1 | Core adds `run_occupied` to `occupied_sum` |
| **Total** | **~195** | Per run at 64 rows |

## Validation

- Threshold ~0.6047 for directed percolation on 64×64 (expected ~0.605)
- Occupancy bias < 0.001 vs probability p
- Prefix scan validated against BFS reference (1000 random grids)
- Frontier latency is pipelined: 3 cycles per row, so 64 rows cost about 193-195 cycles depending on start/done bookkeeping

## Doc Links

- [BFS Frontier Algorithm](bfs_frontier.md) — Prefix scan reachability details
- [Core Schema](percolation_core_schema.md) — Conceptual architecture
- [UART Protocol](UART_PROTOCOL_V2.md) — Binary frame layout
- [RNG Architecture](../rng/RNG.md) — Trivium + AES-CTR seeding
- [UART Binary Scaffold](../uart_message_bin/README.md) — Wrapper details
- [Python Tools](../../python/README.md) — Host-side validation
