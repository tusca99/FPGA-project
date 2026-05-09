"""Hardware sweep: run probability sweep against FPGA via UART.

Usage:
    python hw_sweep.py --port /dev/ttyUSB1 --runs 50 --points 9
"""

from __future__ import annotations

import argparse
import time

from percolation_uart.client import PercolationClient
from percolation_uart.protocol import PercolationRequest


def hw_sweep(probabilities, runs, steps, seed, port, baudrate, timeout):
    """Run sweep on FPGA hardware."""
    client = PercolationClient(port=port, baudrate=baudrate, timeout=timeout)
    results = []

    try:
        for p in probabilities:
            spanning = 0
            occupied = 0
            for i in range(runs):
                # Flush buffers before each request (like try.py)
                client.transport.reset_input_buffer()
                client.transport.reset_output_buffer()
                time.sleep(0.05)

                req = PercolationRequest.from_probability(
                    probability=p,
                    cfg_seed=(seed + i) & 0xFFFFFFFF,
                    steps_per_run=steps,
                    cfg_runs=1,
                )
                resp = client.run(req)
                spanning += resp.spanning_count
                occupied += resp.total_occupied

                # Delay between requests (like try.py)
                time.sleep(0.1)

            rate = spanning / runs
            avg_occ = occupied / (runs * steps * 32)
            results.append((p, rate, avg_occ))
            print(f"p={p:.4f}: spanning={spanning}/{runs} ({rate:.4f}), avg_occ={avg_occ:.4f}")
    finally:
        client.close()

    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="/dev/ttyUSB1")
    parser.add_argument("--baudrate", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--runs", type=int, default=50)
    parser.add_argument("--steps", type=int, default=64)
    parser.add_argument("--seed", type=lambda x: int(x, 0), default=0x12345678)
    parser.add_argument("--pmin", type=float, default=0.1)
    parser.add_argument("--pmax", type=float, default=0.9)
    parser.add_argument("--points", type=int, default=90)
    args = parser.parse_args()

    probs = [args.pmin + i * (args.pmax - args.pmin) / (args.points - 1) for i in range(args.points)]

    print(f"FPGA sweep: port={args.port}, runs={args.runs}, grid=32x{args.steps}")
    print(f"Probabilities: {[f'{p:.4f}' for p in probs]}\n")

    results = hw_sweep(probs, args.runs, args.steps, args.seed, args.port, args.baudrate, args.timeout)

    print("\n=== Results ===")
    print("p, spanning_frac, avg_occ_frac")
    for p, sf, af in results:
        print(f"{p:.4f}, {sf:.4f}, {af:.4f}")


if __name__ == "__main__":
    raise SystemExit(main())
