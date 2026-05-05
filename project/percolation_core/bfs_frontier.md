# BFS Frontier - RTL Contract

This document describes the row-wise frontier backend used by the core. It is not a full-grid BFS; the module processes the grid row-by-row, keeping only the current row being filled and the previously processed reachability mask.

In the current core, the runtime parameter `GridSteps` (`CfgStepsPerRun`) defines the height of the strip. The width is fixed at compile-time by the generic `N_ROWS_G`.

## Entity Target

The target block is a reachability engine designed for 2D percolation and directed variants.

```vhdl
entity percolation_bfs_frontier is
    generic (
        N_ROWS_G : positive := 64
    );
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
        Spanning      : out std_logic
    );
end entity;
```

## Objective

Verify if at least one continuous path exists from the top row to the bottom row without using Union-Find or maintaining full component labels.

The block operates row-wise:
- Stores only the current row and the previous reachability mask.
- Receives an occupancy row sampled from the RNG bank.
- Resolves horizontal reachability (closure) for the current row.
- Stops when the final row is processed and no pending data remains.

## Connectivity Strategies: Comparison

To determine if a cell in the current row is reachable, we must resolve all horizontal connections. A cluster can "snake" across the row, meaning a cell might be reachable via a path that moves far to the left or right before coming back.

### 1. Naive Sequential Loop
Iterate $N$ times: `reach(i) = open(i) AND (reach(i-1) OR reach(i+1) OR top(i))`.
- **Pros**: Simple logic.
- **Cons**: Creates a combinatorial chain of length $N$.
- **Artix-7 Limit**: For $N=64$, the path is too long for 100MHz. Timing fails.

### 2. Combinatorial Bitmask (Parallel Prefix)
Use $\log_2(N)$ stages of shifts: $d = 1, 2, 4, 8, \dots$
Rule: $reach \leftarrow reach \lor ((reach \ll d) \lor (reach \gg d)) \land open$.
- **Pros**: Reduces path depth from $O(N)$ to $O(\log N)$.
- **Cons**: Still a single combinatorial block.
- **Artix-7 Limit**: At $N=64$, $\log_2(64)=6$ stages. Combined with RNG and FSM logic, this often exceeds the 10ns clock period.

### 3. Pipelined Bitmask (Current Choice)
Same as the bitmask approach, but each $\log_2(N)$ stage is separated by a register.
- **Pros**: **Maximum Throughput (1 row/clk)**. Each stage is a tiny combinatorial path.
- **Cons**: Increases latency by $\log_2(N)$ cycles.
- **Artix-7 Limit**: Extremely robust. Can easily hit 100MHz+ regardless of $N$ (up to reasonable limits like 256/512).

### 4. Tiling (Block-wise)
Split the row into $M$ smaller tiles (e.g., 4 tiles of 16 bits).
- **Pros**: Very short local combinatorial paths.
- **Cons**: **Slower Throughput (1 row / $M$ clks)**. Requires complex boundary management to handle clusters crossing tile edges.
- **Artix-7 Limit**: Only useful if $N$ is so large (e.g., $N > 1024$) that the row cannot fit in a register or the RNG cannot produce it in one cycle.

| Method | Correctness | Timing (100MHz) | Throughput | Latency | Complexity |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Naive Loop | ✅ | ❌ | 1 row/clk | 1 clk | Low |
| Comb. Mask | ✅ | ❌ | 1 row/clk | 1 clk | Low |
| **Pipelined Mask**| ✅ | ✅ | **1 row/clk** | $\log_2 N$ clks | Medium |
| Tiling | ✅ | ✅ | 1 row / $M$ clks | $M$ clks | High |

## Operational Sequence

1. **Reset/CfgInit**: Initialize state and load `GridSteps`.
2. **Start**: Trigger the first row capture.
3. **Streaming**: 
   - Fetch row from RNG.
   - Feed into the $\log_2(N)$ pipeline.
   - The result of Row $N$ is used as the vertical seed for Row $N+1$.
4. **Completion**: When the last row exits the pipeline, check if any bit is set $\to$ `Spanning = 1`.

## Synthesis Goals

- **No Recursion**: All loops are unrolled into pipeline stages.
- **Bit-Parallel**: Use wide vectors to process the whole row at once.
- **Registered Boundaries**: Ensure no long combinatorial paths exist between the RNG, the mask stages, and the final counters.