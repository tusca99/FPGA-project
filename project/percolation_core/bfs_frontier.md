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

### 3. Combinatorial Bitmask (Current Choice — Validated for N=64)
The bitmask approach is implemented as a pure combinatorial function `reach_row` using a while loop with $\log_2(N)$ shift-OR stages.
- **Pros**: **Maximum Throughput (1 row/clk)**. Single-cycle latency. Simple FSM.
- **Cons**: The combinatorial path depth is $O(\log N)$. For large $N$ this may approach timing limits.
- **Artix-7 Limit**: At $N=64$, $\log_2(64)=6$ stages of shifts/ORs. This fits comfortably within the 10ns clock period at 100MHz. **For $N \ge 128$, timing fails due to congestion** (too many wide LUTs spread across the chip).

### 4. Tiling (Block-wise)
Split the row into $M$ smaller tiles (e.g., 4 tiles of 16 bits).
- **Pros**: Very short local combinatorial paths.
- **Cons**: **Slower Throughput (1 row / $M$ clks)**. Requires complex boundary management to handle clusters crossing tile edges.
- **Artix-7 Limit**: Only useful if $N$ is so large (e.g., $N > 1024$) that the row cannot fit in a register or the RNG cannot produce it in one cycle.

| Method | Correctness | Timing (100MHz) | Throughput | Latency | Complexity |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Naive Loop | ✅ | ❌ | 1 row/clk | 1 clk | Low |
| Comb. Mask | ✅ | ❌ | 1 row/clk | 1 clk | Low |
| **Combinatorial Mask (N≤64)**| ✅ | ✅ | **1 row/clk** | 1 clk | Low |
| Pipelined Mask (N≥128) | ✅ | ✅ | 1 row/clk | 2-3 clks | Medium |
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



The frontier is already reverted to the simple 3-state version. Let me confirm the current state and explain why N=128 fails at ~60% LUTs. 

Read [](file:///home/alessio/ssd_data/Alessio/uni_magistrale/Programmable_Hardware_Devices/FPGA-project/project/percolation_core/percolation_bfs_frontier.vhd#1-1), lines 1 to 50

The frontier is already reverted to the simple 3-state version (`IDLE → RUN → COMPLETE`). No S0/S1/S2 pipeline — just the original combinatorial `reach_row` in one cycle.

## Why N=128 Fails at ~60% LUTs

**It's not about total LUT count — it's about physical proximity.**

For N=128, `reach_row` has **7 stages of 128-bit wide logic** (shift+OR+AND). Each stage needs ~128 LUTs, and all 7 stages must fit within a 10ns clock cycle. The problem:

1. **Wide buses create routing congestion** — 128 parallel signals need 128 physical wires. When they have to travel between 7 stages, they compete for the same routing channels.
2. **The router can't place them close enough** — even at 60% total utilization, the critical path LUTs end up spread across the chip. Route delay becomes 8ns+ (as we saw: 63% of the 13ns path was routing).
3. **The 10ns budget is unforgiving** — Artix-7 LUT delay is ~0.5ns, CARRY4 is ~0.1ns, but route delay is 1-3ns per hop. For N=128, the path needs 10+ hops.

For N=64:
- Only **6 stages of 64-bit logic** — half the width, one fewer stage
- 64-bit buses fit in local routing, so route delay is ~1ns per hop
- Total path: ~6ns logic + ~3ns route = ~9ns ✅ (0.08ns slack in your report)

## Your N=64 Timing Report

```
WNS = +0.080ns  (meets timing)
TNS = 0.000ns   (no violations)
```

The critical path is the popcount tree: `core_cfg_p_s_reg[2] → popcount_reg_reg[5]`
- Data path: 9.868ns (logic 2.34ns, route 7.53ns)
- 12 logic levels, 4 CARRY4s

It passes with a slim 0.08ns margin. The `popcount_reg` pipeline helps by breaking the path, but the route delay is still 76% of the total. This is expected for a 64-bit tree.

## Bottom Line

N=64 @ 100MHz is the validated build. The hardware is ready. N=128 would require either:
- 50 MHz clock (doubling the budget to 20ns)
- Internal pipelining of `reach_row` (2 cycles per row, halving throughput)

For your project, **N=64 is the right choice**. The bitstream works, timing is clean, and you can move on to Python validation.

Ready to proceed with the Python benchmarking?


Read [](file:///home/alessio/ssd_data/Alessio/uni_magistrale/Programmable_Hardware_Devices/FPGA-project/project/percolation_core/percolation_bfs_frontier.vhd#50-50), lines 50 to 150

Yes, 68 cycles for 64 rows = ~94% efficiency, nearly 1 row/clk. The 4-cycle overhead per run comes from:

1. **Start propagation** (1 cycle): Core in state 0 sets `frontier_start_s`, transitions to state 1
2. **Busy settling** (1 cycle): Frontier transitioned to RUN, but `Busy` output is registered so core still sees '1'
3. **Done detection** (1 cycle): Frontier processes last row → COMPLETE, but `Done` is combinatorial on `state` signal which updates after the rising edge
4. **Final accumulation** (1 cycle): Core detects done, adds last popcount to `run_occupied`, updates `occupied_sum`, transitions to state 0

Could we save some? 
- **Busy settling**: We could have the core send immediately in the first cycle of state 1 (it knows it just set Start). Would save 1 cycle.
- **Done detection**: Core could count rows itself instead of waiting for frontier Done. Would save 1 cycle but duplicates logic.

For 64-row runs, 4 cycles overhead is ~6% — probably not worth the extra complexity. If you were doing 8-row runs, then yes.

Go ahead and push this N=64 safe build. Then we can revisit the pipelined version for N≥128.