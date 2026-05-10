Simulation helper to reproduce FPGA frontier behavior.

Files:
- `percolation_model.py`: FPGA-like row-wise model with `fpga_mode` to emulate popcount register delay.
- `simulate.py`: CLI to sweep probability range and print spanning and occupancy fractions.

Usage:

Run quick sweep (fpga-mode on to emulate bug):

```bash
python3 -m python.simulation.simulate --fpga-mode --runs 200 --points 11
```

Run ideal model (no popcount bug):

```bash
python3 -m python.simulation.simulate --runs 200 --points 11
```
