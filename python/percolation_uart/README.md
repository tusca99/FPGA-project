# Percolation UART Python Package

Host-side tools for the FPGA percolation core.

## Modules

| Module | Purpose |
|--------|---------|
| `protocol` | Pack/unpack UART messages (16-byte frames) |
| `transport` | Serial link wrapper (Linux termios) |
| `client` | High-level API (`PercolationClient`) |
| `algorithms` | BFS reference + FPGA-directed algorithm |
| `reference` | Pure-Python Monte Carlo reference (BFS) |
| `analysis` | SQLite history inspection and lightweight plotting |

## Quick Start

```python
from percolation_uart.client import PercolationClient

with PercolationClient(port="/dev/ttyUSB0") as client:
    response = client.run_from_probability(0.6, seed=0x12345678, grid_size=64, cfg_runs=16)
    print(response)
    # PercolationResponse(step_count=16, spanning_count=8, total_occupied=39314, spanning_occupied=57344)
```

## Validation

### Three-Way Comparison

```bash
python compare_three.py --runs 1000 --points 20 --output three_way.png --pmin 0.50 --pmax 0.70
```

### Quick Hardware Test

```bash
python try.py
```

### SQLite Analysis

```bash
python -m percolation_uart.analysis --db python/output/benchmark.sqlite3 --latest --plot-dir python/output/analysis
```

## Response Format

The FPGA returns 16 bytes:
- `StepCount` (4B): completed runs
- `SpanningCount` (4B): spanning runs
- `TotalOccupied` (4B): total occupied sites
- `SpanningOccupied` (4B): reachable sites in spanning runs
