"""Hardware validation sweep: compare FPGA hardware against BFS reference.

This script:
1. Connects to the FPGA via UART and runs a probability sweep
2. Runs the same sweep with the BFS reference simulator
3. Plots both spanning probability curves for comparison

Usage:
    # With FPGA connected:
    python fpga_hardware_validate.py --port /dev/ttyUSB1 --runs 100

    # Software-only (BFS only, no hardware):
    python fpga_hardware_validate.py --software-only --runs 1000
"""

from __future__ import annotations

import argparse
import random
import time
from collections import deque
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from percolation_uart.client import PercolationClient
from percolation_uart.protocol import PercolationRequest, probability_to_uq32


def bfs_spanning(grid: list[list[bool]]) -> bool:
    """Standard 4-neighbor BFS from top row to bottom row."""
    grid_steps = len(grid)
    grid_width = len(grid[0])
    visited = [[False] * grid_width for _ in range(grid_steps)]
    queue = deque()

    for col in range(grid_width):
        if grid[0][col]:
            visited[0][col] = True
            queue.append((0, col))

    while queue:
        row, col = queue.popleft()
        if row == grid_steps - 1:
            return True
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nr, nc = row + dr, col + dc
            if 0 <= nr < grid_steps and 0 <= nc < grid_width and not visited[nr][nc] and grid[nr][nc]:
                visited[nr][nc] = True
                queue.append((nr, nc))
    return False


def bfs_sweep(probabilities: list[float], runs: int, width: int, steps: int, seed: int) -> list[float]:
    """Run BFS sweep and return spanning fractions."""
    rates = []
    for p in probabilities:
        rng = random.Random(seed)
        spanning_count = 0
        for _ in range(runs):
            grid = [[rng.random() < p for _ in range(width)] for _ in range(steps)]
            if bfs_spanning(grid):
                spanning_count += 1
        rates.append(spanning_count / runs)
        print(f"  BFS p={p:.4f}: {spanning_count}/{runs} = {spanning_count/runs:.4f}")
    return rates


def fpga_sweep(
    probabilities: list[float],
    runs: int,
    steps: int,
    seed: int,
    port: str,
    baudrate: int,
    timeout: float,
) -> list[float]:
    """Run FPGA hardware sweep and return spanning fractions."""
    rates = []
    client = PercolationClient(port=port, baudrate=baudrate, timeout=timeout)
    try:
        for p in probabilities:
            spanning_count = 0
            total_occupied = 0
            for run_idx in range(runs):
                req = PercolationRequest.from_probability(
                    probability=p,
                    cfg_seed=(seed + run_idx) & 0xFFFFFFFF,
                    steps_per_run=steps,
                    cfg_runs=1,  # One run per request for accurate per-run stats
                )
                resp = client.run(req)
                spanning_count += resp.spanning_count
                total_occupied += resp.total_occupied
                # Small delay to avoid overwhelming the FPGA
                if run_idx % 10 == 9:
                    time.sleep(0.05)
            rates.append(spanning_count / runs)
            avg_occ = total_occupied / (runs * steps * 64)
            print(f"  FPGA p={p:.4f}: {spanning_count}/{runs} = {spanning_count/runs:.4f}, avg_occ={avg_occ:.4f}")
    finally:
        client.close()
    return rates


def plot_comparison(
    probabilities: list[float],
    bfs_rates: list[float],
    fpga_rates: list[float] | None,
    output_path: str,
    runs: int,
    width: int,
    steps: int,
):
    """Generate comparison plot."""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    # Spanning probability plot
    ax1.plot(probabilities, bfs_rates, 'o-', label='BFS (undirected)', linewidth=2, markersize=6)
    if fpga_rates is not None:
        ax1.plot(probabilities, fpga_rates, 's-', label='FPGA (directed)', linewidth=2, markersize=6)
    ax1.axvline(x=0.5927, color='r', linestyle='--', alpha=0.5, label='Critical p=0.5927')
    ax1.set_xlabel('Occupation Probability p')
    ax1.set_ylabel('Spanning Probability')
    title = f'Spanning Probability vs p (N={width}x{steps}, {runs} runs)'
    if fpga_rates is None:
        title += ' [BFS ONLY — no FPGA]'
    ax1.set_title(title)
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    ax1.set_ylim(-0.05, 1.05)

    # Mismatch plot (only if FPGA data available)
    if fpga_rates is not None:
        mismatch_rates = [abs(b - f) for b, f in zip(bfs_rates, fpga_rates)]
        ax2.plot(probabilities, mismatch_rates, 'o-', color='red', linewidth=2, markersize=6)
        ax2.set_xlabel('Occupation Probability p')
        ax2.set_ylabel('Absolute Difference |BFS - FPGA|')
        ax2.set_title('BFS vs FPGA Absolute Difference')
        ax2.grid(True, alpha=0.3)
        ax2.set_ylim(-0.05, 1.05)
    else:
        ax2.text(0.5, 0.5, 'No FPGA data\n(software-only mode)', ha='center', va='center', fontsize=14)
        ax2.set_xlim(0, 1)
        ax2.set_ylim(0, 1)
        ax2.axis('off')

    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    print(f"\nPlot saved to {output_path}")


def main():
    parser = argparse.ArgumentParser(description='FPGA hardware vs BFS validation sweep')
    parser.add_argument('--port', default='/dev/ttyUSB1', help='Serial port for FPGA')
    parser.add_argument('--baudrate', type=int, default=115200)
    parser.add_argument('--timeout', type=float, default=2.0)
    parser.add_argument('--runs', type=int, default=100, help='Runs per probability point')
    parser.add_argument('--width', type=int, default=64, help='Grid width (compile-time constant)')
    parser.add_argument('--steps', type=int, default=64, help='Grid steps per run')
    parser.add_argument('--seed', type=lambda x: int(x, 0), default=0x12345678)
    parser.add_argument('--pmin', type=float, default=0.1)
    parser.add_argument('--pmax', type=float, default=0.9)
    parser.add_argument('--points', type=int, default=9)
    parser.add_argument('--output', type=str, default='fpga_vs_bfs_comparison.png')
    parser.add_argument('--software-only', action='store_true', help='Skip FPGA, run BFS only')
    parser.add_argument('--skip-bfs', action='store_true', help='Skip BFS, run FPGA only')
    args = parser.parse_args()

    probabilities = [args.pmin + i * (args.pmax - args.pmin) / (args.points - 1) for i in range(args.points)]

    print(f"Probability sweep: {probabilities}")
    print(f"Runs per point: {args.runs}")
    print(f"Grid: {args.width}x{args.steps}")
    print()

    # Run BFS sweep
    bfs_rates = None
    if not args.skip_bfs:
        print("Running BFS sweep...")
        bfs_rates = bfs_sweep(probabilities, args.runs, args.width, args.steps, args.seed)
        print()

    # Run FPGA sweep
    fpga_rates = None
    if not args.software_only:
        print(f"Connecting to FPGA on {args.port} @ {args.baudrate} baud...")
        try:
            fpga_rates = fpga_sweep(
                probabilities, args.runs, args.steps, args.seed,
                args.port, args.baudrate, args.timeout,
            )
            print()
        except Exception as e:
            print(f"ERROR: Could not connect to FPGA: {e}")
            print("Falling back to software-only mode.")
            print()

    # Plot
    if bfs_rates is None and fpga_rates is None:
        print("Nothing to plot!")
        return 1

    plot_comparison(probabilities, bfs_rates or [], fpga_rates, args.output, args.runs, args.width, args.steps)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
