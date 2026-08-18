# FPGA Percolation Project

An FPGA accelerator for **directed percolation** on an Artix-7 A7-100T
(`xc7a100tcsg324-1`), single 100 MHz clock. A custom RTL core validates the
directed-percolation phase transition (~0.605 for 64×64) through host-controlled
UART sweeps.

## Architecture

```
RNG Bank (64× Trivium) → Core Controller → Frontier Engine → UART
```

Three independent blocks: random-number generation (RNG bank), reachability
computation (frontier, bidirectional associative prefix scan), and
control/communication (core + UART). The core consumes rows from the pipeline
on demand, with no wasted clock cycles.

## Key Modules

| File | Role |
|------|------|
| `project/percolation_core/percolation_core.vhd` | Top-level controller: orchestrates RNG + frontier, accumulates statistics |
| `project/percolation_core/percolation_bfs_frontier.vhd` | Row-wise reachability engine (bidirectional associative prefix scan) |
| `project/percolation_core/percolation_uart_top.vhd` | UART wrapper: 16-byte request/response |
| `project/rng/rng_hybrid_64.vhd` | 64× Trivium RNG bank, AES-CTR seeded |

## Protocol (v3.0)

- **Request (16 bytes)**: `[CfgP (UQ32)] [CfgSeed] [CfgStepsPerRun] [CfgRuns]`
- **Response (16 bytes)**: `[StepCount] [SpanningCount] [TotalOccupied] [SpanningOccupied]`
- **Baud rate**: 115200 (raw termios link, zero dependencies)

Full details in `project/percolation_core/UART_PROTOCOL.md`.

## Build & Simulation

```bash
vivado -mode batch -source project/recreate_vivado_project.tcl            # rebuild
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs percolation
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs loopback
```

Project created in `project/.vivado/FPGA-project/FPGA-project.xpr`.

## Validation & Analysis

```bash
# Three-way comparison: BFS reference vs SW FPGA model vs HW FPGA
python python/compare_three.py --runs 1000 --points 20 --output python/output/three_way_comparison.png

# Quick hardware test
python python/try.py

# Benchmark analysis (starter plots + FPGA engineering)
percolation-analyze --db python/output/benchmark.sqlite3 --latest --plot-dir python/output/analysis
percolation-analyze --fpga-plot python/output/analysis
```

Full host workflow and plot catalog in `python/README.md`.

## Results

| Result | Value |
|--------|-------|
| RNG occupancy bias | < 0.001 |
| Frontier vs BFS | 1000 random tests, perfect match |
| DP threshold (64×64) | ~0.6047 ± 0.0002 (literature ~0.605) |
| End-to-end frontier cost | 4 cycles/row (3 prefix scan + 1 handshake) |
| Pipeline efficiency | 85–95% of ideal |
| Universality | Finite-size scaling, DP exponent ν = 1.096 |

## Documentation

- `project/percolation_core/` — Core, schema, frontier algorithm, UART protocol
- `project/rng/RNG.md` — RNG architecture (Trivium + AES-CTR)
- `project/uart_message_bin/README.md` — Binary UART wrappers
- `python/README.md` — Host-side Python tools
- `python/FPGA_BENCHMARK_ANALYSIS.md` — Theoretical models for benchmark analysis
- `python/PRESENTATION_OUTLINE.md` — Presentation outline

