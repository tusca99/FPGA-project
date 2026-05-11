# Copilot Instructions for FPGA Project

## Architecture

- `project/percolation_core/`: data-plane MVP — site percolation core
  - `percolation_core.vhd`: orchestrates RNG + frontier, accumulates statistics
  - `percolation_bfs_frontier.vhd`: row-wise reachability via bidirectional associative prefix scan
  - `percolation_uart_top.vhd`: thin UART wrapper (16-byte request/response)
- `project/rng/`: RNG bank — 64× Trivium + AES-CTR seeding
  - `zz_rng_hybrid_64.vhd`: parameterized by `N_ROWS_G` (default 64)
- `project/uart_message_bin/`: UART binary wrappers
  - `uart_msg_rx.vhd`, `uart_msg_tx.vhd`: fixed-length message I/O
  - `uart_msg_loopback_top.vhd`: loopback benchmark
- `python/`: host-side validation
  - `percolation_uart/algorithms.py`: BFS reference + FPGA-directed algorithm
  - `compare_three.py`: three-way validation (BFS / SW FPGA / HW FPGA)
  - `try.py`: quick hardware test

## Protocol (v3.0)

- **Request (16 bytes)**: `[CfgP (4B UQ32)] [CfgSeed (4B)] [CfgStepsPerRun (4B)] [CfgRuns (4B)]`
- **Response (16 bytes)**: `[StepCount (4B)] [SpanningCount (4B)] [TotalOccupied (4B)] [SpanningOccupied (4B)]`
- Grid width fixed at `N_ROWS_G` (compile-time, default 64), height from `CfgStepsPerRun`

## Current Status

- ✅ RNG verified: occupancy matches p (bias < 0.001)
- ✅ Frontier: associative prefix scan validated against BFS (1000 random tests)
- ✅ Threshold: ~0.6047 for directed percolation on 64×64 (expected ~0.605)
- ✅ Timing: prefix scan meets 100 MHz at N=64
- ✅ UART end-to-end: 16-byte request/response working
- ⚠️  For N≥128, pipelined version needed

## Conventions

- **Reset active low** (`Rst = '0'`)
- **Clock**: 100 MHz single-clock (Arty A7-100T)
- **Parameters**: generics for compile-time, ports for runtime
- **Synchronization**: double flip-flop for async inputs

## Build

```bash
vivado -mode batch -source project/recreate_vivado_project.tcl
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs percolation
```

## Validation

```bash
# Three-way comparison
python python/compare_three.py --runs 1000 --points 20 --output output/three_way.png

# Quick hardware test
python python/try.py
```

## Notes

- VHDL is final; focus on Python tooling and documentation
- `python/output/` is the default directory for plots
- Keep docs in sync with code; outdated docs cause confusion
