# Python Tools

This folder contains the host-side tools for the percolation FPGA project.
It is the Python entry point for request/response handling, reference simulation, and benchmark sweeps.

## Where to start

- [README radice](../README.md) for the overall repository entry point.
- [Percolation core](../project/percolation_core/README.md) for the data-plane MVP and the BFS roadmap.
- [UART binary scaffold](../project/uart_message_bin/README.md) for the fixed-length control-plane wrappers.
- [UART protocol v2](../project/percolation_core/UART_PROTOCOL_V2.md) for the exact frame layout.

## Package layout

- `percolation_uart.protocol` packs and unpacks UART messages.
- `percolation_uart.transport` wraps the serial link to the FPGA.
- `percolation_uart.client` exposes a small high-level API.
- `percolation_uart.reference` provides a pure-Python Monte Carlo reference.
- `percolation_uart.benchmark` runs timing and sweep experiments.

## Install

From this directory, using a local virtual environment:

```bash
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

## Example

```python
from percolation_uart.client import PercolationClient

with PercolationClient(port="/dev/ttyUSB0") as client:
    response = client.run_from_probability(0.6, seed=0x12345678, grid_size=8, cfg_runs=1)
    print(response)
```

## Notes

- The FPGA response is 16 bytes: `StepCount`, `SpanningCount`, `TotalOccupied`, `BfsStepCount`.
- `StepCount` is the number of completed runs in the batch, while `BfsStepCount` is cumulative across the batch.
- For per-run statistics, keep `cfg_runs = 1` and repeat requests.
- The `requirements.txt` file keeps the editable install minimal; `requirements-analysis.txt` adds the plotting and numerical stack.
- `bootstrap.sh` creates the venv, installs `uv` inside it, and installs the base requirements.
