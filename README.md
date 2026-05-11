# FPGA Percolation Project

Site percolation on Artix-7 A7-100T (xc7a100tcsg324-1), 100 MHz single-clock.
Validates directed percolation threshold (~0.605 for 64×64) via UART-controlled sweeps.

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│   RNG Bank  │────▶│   Core      │────▶│   Frontier      │
│ (64 Trivium)│     │ (controller)│     │ (reachability)  │
└─────────────┘     └─────────────┘     └─────────────────┘
       │                   │                     │
       │ site_open[0..63]  │ row_bits            │ ChunkOpen
       │ (every cycle)     │ (when frontier      │ (when ChunkValid)
       │                   │  ready)               │
       ▼                   ▼                     ▼
   Random bits         Occupancy row         Reachability mask
   compared to        sent to frontier      computed via prefix
   threshold CfgP                            scan (1 cycle/row)
```

## Key Modules

| File | Role |
|------|------|
| `project/percolation_core/percolation_core.vhd` | Orchestrates RNG + frontier, accumulates statistics |
| `project/percolation_core/percolation_bfs_frontier.vhd` | Row-wise reachability via bidirectional associative prefix scan |
| `project/rng/zz_rng_hybrid_64.vhd` | 64× Trivium RNG bank, AES-CTR seeded |
| `project/percolation_core/percolation_uart_top.vhd` | UART wrapper: 16-byte request/response |

## Protocol

- **Request (16 bytes)**: `[CfgP (4B)] [CfgSeed (4B)] [CfgStepsPerRun (4B)] [CfgRuns (4B)]`
- **Response (16 bytes)**: `[StepCount (4B)] [SpanningCount (4B)] [TotalOccupied (4B)] [SpanningOccupied (4B)]`

See `project/percolation_core/UART_PROTOCOL_V2.md` for full details.

## Build & Simulation

```bash
# Rebuild Vivado project
cd /path/to/FPGA-project
vivado -mode batch -source project/recreate_vivado_project.tcl

# Optional targets
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs percolation
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs loopback
```

Project created in `project/.vivado/FPGA-project/FPGA-project.xpr`.

## Validation

```bash
# Three-way comparison: BFS reference vs SW FPGA model vs HW FPGA
python python/compare_three.py --runs 1000 --points 20 --output three_way.png
```

## Documentation

- `project/percolation_core/README.md` — Core details and connectivity backend
- `project/percolation_core/percolation_core_schema.md` — Conceptual schema
- `project/percolation_core/bfs_frontier.md` — Frontier algorithm (prefix scan)
- `project/percolation_core/UART_PROTOCOL_V2.md` — Binary UART protocol
- `project/rng/RNG.md` — RNG architecture (Trivium + AES-CTR)
- `project/uart_message_bin/README.md` — UART binary wrappers
- `python/README.md` — Host-side Python tools

## Status

- ✅ RNG verified: occupancy matches p (bias < 0.001)
- ✅ Frontier algorithm: prefix scan validated against BFS (1000 random tests)
- ✅ Threshold: ~0.6047 for directed percolation on 64×64 (expected ~0.605)
- ✅ Timing: combinatorial prefix scan meets 100 MHz at N=64
- ✅ UART end-to-end: 16-byte request/response working
- ⚠️  For N≥128, pipelined version needed (see `bfs_frontier.md`)
