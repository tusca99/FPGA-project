from percolation_uart.client import PercolationClient

with PercolationClient(port="/dev/ttyUSB0") as client:
    response = client.run_from_probability(0.6, seed=0x12345678, grid_size=8, cfg_runs=1)
    print(response)