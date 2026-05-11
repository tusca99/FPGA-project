# Python Tools

Host-side tools for the percolation FPGA project.

## Package Layout

| Module | Purpose |
|--------|---------|
| `percolation_uart.protocol` | Pack/unpack UART messages (16-byte frames) |
| `percolation_uart.transport` | Serial link wrapper |
| `percolation_uart.client` | High-level API (`PercolationClient`) |
| `percolation_uart.reference` | Pure-Python Monte Carlo reference (BFS) |
| `percolation_uart.benchmark` | Timing and sweep experiments |
| `percolation_uart.fpga_algorithm` | Software model of FPGA algorithm |

## Install

```bash
cd python
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install uv
uv pip install -r requirements.txt
```

Optional analysis extras:
```bash
uv pip install -r requirements-analysis.txt
```

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

Compare BFS reference, software FPGA model, and hardware FPGA:

```bash
python python/compare_three.py --runs 1000 --points 20 --output three_way.png --pmin 0.50 --pmax 0.70
```

Outputs:
- Critical threshold estimates for all three methods
- Occupancy bias check
- Reachable fraction monotonicity check
- Mass (avg reachable sites in spanning runs) at criticality

### Hardware Sweep

```bash
python python/hw_sweep.py --port /dev/ttyUSB1 --runs 100 --points 10
```

## Response Format

The FPGA returns 16 bytes:
- `StepCount` (4B): completed runs
- `SpanningCount` (4B): spanning runs
- `TotalOccupied` (4B): total occupied sites
- `SpanningOccupied` (4B): reachable sites in spanning runs

For per-run statistics, keep `cfg_runs = 1` and repeat requests.

## Doc Links

- [Root README](../README.md) — Project overview
- [Core README](../project/percolation_core/README.md) — FPGA core
- [UART Protocol](../project/percolation_core/UART_PROTOCOL_V2.md) — Binary frame layout
