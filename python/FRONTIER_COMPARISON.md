# Frontier vs BFS Comparison — Short Report

Summary
-------
- Goal: compare FPGA-style row-wise `frontier` reachability against canonical BFS on same random grids.
- Action: implemented `python/simulation` model, aligned RNG draws with reference, ran per-run comparisons.
- Result: many mismatches found where frontier reports `spanning = True` while BFS reports `spanning = False` (occupied counts matched).

Concrete failing example
------------------------
- Grid: 16 rows × 16 columns (printed top→bottom):

```
.1.1.1.1........
..1.11.....11...
.1.1.11.11.111.1
1....1...1.11...
.....111.1.11.1.
11...1..111....1
1.1.....1111....
.1111.......1.1.
1..1.1...1..1..1
11.1.11.........
1.1...11111..1..
....11.111......
1.1.1111......11
...11.1.....1.1.
.111..1..1.11...
.11..1...111.11.
```

- For this run: BFS spanning = False, Frontier spanning = True. Occupied site counts were equal.

What this implies
-----------------
- RNG and threshold conversion are correct (occupied counts match). The difference is purely connectivity logic.
- `reach_row` (horizontal closure) in the frontier model overestimates connectivity on some patterns — allows reach to propagate in ways BFS does not.

Immediate checks / next steps
----------------------------
- Re-run VHDL `reach_row` on the exact failing grid as a VHDL testbench (feed row masks one by one) and inspect the `row_reach` outputs to confirm RTL behaviour matches Python `reach_row` implementation.
- Compare bit-order and shift directions: confirm left/right shifts in VHDL map to same bit indices used in Python (LSB=col0 assumption).
- Verify `seed` computation: confirm seed = `ChunkOpen and previous_reach` semantics match the intended propagation (we used `row_mask & prev_reach`).
- Instrument FPGA/top to stream per-row `ChunkOpen`, `seed_row`, and `row_reach` for failing seeds (or add debug prints in VHDL testbench).
- Check whether `reach_row` should apply closure iteratively using registered pipeline (VHDL uses log2 shifts); test order of OR/AND operations for off-by-one effects.
- Validate that `reach_row` does not allow reachability through cells that BFS would not connect (e.g., ensure closure only within contiguous open segments connected to vertical seed bits).

Longer-term
-----------
- Add automated per-run comparison harness that logs first N mismatches and emits both BFS-visited masks and frontier masks for each row.
- Add small VHDL stimulus module to replay failing grids in simulation and log internals for direct comparison.
- If VHDL confirmed wrong, propose patch: rewrite `reach_row` so it exactly implements parallel prefix closure equivalent to iterative ±1 neighbor expansion.

Files used / created
--------------------
- `python/simulation/percolation_model.py` — FPGA-like model + comparator helper
- `python/simulation/simulate.py` — sweep CLI
- `python/simulation/FRONTIER_COMPARISON.md` — this file

Contact / notes
----------------
- I can generate the VHDL testbench stimulus for the concrete failing grid and run a simulation (if you want). Reply what you prefer next: VHDL testbench, deeper Python diagnosis, or a candidate fix to `reach_row`.
