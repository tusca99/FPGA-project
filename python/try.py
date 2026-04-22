from percolation_uart.client import PercolationClient


with PercolationClient(port="/dev/ttyUSB1", baudrate=115200, timeout=5.0) as client:
    response = client.run_from_probability(
        0.6,
        seed=0x12345678,
        steps_per_run=1,
        cfg_runs=1,
    )
    print(response)