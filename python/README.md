# Python Tools

This folder contains the host-side tools for the percolation FPGA project:

- `percolation_uart.protocol` for packing and unpacking UART messages.
- `percolation_uart.transport` for the serial connection to the FPGA.
- `percolation_uart.client` for a small high-level API.
- `percolation_uart.reference` for a pure-Python Monte Carlo reference.
- `percolation_uart.benchmark` for timing and sweep experiments.

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

If you prefer a single-step bootstrap:

```bash
bash bootstrap.sh
bash bootstrap.sh --analysis
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
- For per-run statistics, keep `cfg_runs = 1` and repeat requests.
- The `requirements.txt` file keeps the editable install minimal; `requirements-analysis.txt` adds the plotting and numerical stack.
- `bootstrap.sh` creates the venv, installs `uv` inside it, and installs the base requirements.
