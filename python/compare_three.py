"""Three-way comparison: BFS (undirected) vs Software FPGA (directed) vs Hardware FPGA.

Usage:
    # With FPGA connected:
    python compare_three.py --port /dev/ttyUSB1 --runs 100 --points 9

    # Software-only (no hardware):
    python compare_three.py --software-only --runs 200 --points 13
"""

from __future__ import annotations

import argparse
import random
import time
from collections import deque

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from percolation_uart.client import PercolationClient
from percolation_uart.protocol import PercolationRequest


def bfs_spanning(grid: list[list[bool]]) -> bool:
    """Standard 4-neighbor BFS (undirected percolation)."""
    steps = len(grid)
    width = len(grid[0])
    visited = [[False] * width for _ in range(steps)]
    queue = deque()
    for c in range(width):
        if grid[0][c]:
            visited[0][c] = True
            queue.append((0, c))
    while queue:
        r, c = queue.popleft()
        if r == steps - 1:
            return True
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nr, nc = r + dr, c + dc
            if 0 <= nr < steps and 0 <= nc < width and not visited[nr][nc] and grid[nr][nc]:
                visited[nr][nc] = True
                queue.append((nr, nc))
    return False


def sw_fpga_directed_spanning(grid: list[list[bool]]) -> bool:
    """Software FPGA directed percolation (corrected iterative ±1)."""
    steps = len(grid)
    width = len(grid[0])
    prev_reach = [False] * width
    for row_idx, open_row in enumerate(grid):
        if row_idx == 0:
            seed = open_row
        else:
            seed = [o and r for o, r in zip(open_row, prev_reach)]
        reach = [o and s for o, s in zip(open_row, seed)]
        while True:
            new_reach = reach[:]
            for i in range(width):
                if reach[i]:
                    new_reach[i] = True
                else:
                    left = reach[i - 1] if i > 0 else False
                    right = reach[i + 1] if i < width - 1 else False
                    if open_row[i] and (left or right):
                        new_reach[i] = True
            if new_reach == reach:
                break
            reach = new_reach
        prev_reach = reach
    return any(prev_reach)


def sw_sweep(probabilities: list[float], runs: int, width: int, steps: int, seed: int):
    """Run both software algorithms."""
    bfs_rates = []
    fpga_rates = []
    for p in probabilities:
        rng = random.Random(seed)
        bfs_count = 0
        fpga_count = 0
        for _ in range(runs):
            grid = [[rng.random() < p for _ in range(width)] for _ in range(steps)]
            if bfs_spanning(grid):
                bfs_count += 1
            if sw_fpga_directed_spanning(grid):
                fpga_count += 1
        bfs_rates.append(bfs_count / runs)
        fpga_rates.append(fpga_count / runs)
        print(f"  SW p={p:.4f}: BFS={bfs_count}/{runs}, FPGA={fpga_count}/{runs}")
    return bfs_rates, fpga_rates


def hw_sweep(probabilities: list[float], runs: int, width: int, steps: int, seed: int, port: str, baudrate: int, timeout: float):
    """Run hardware sweep using cfg_runs per request for speed."""
    client = PercolationClient(port=port, baudrate=baudrate, timeout=timeout)
    hw_rates = []
    try:
        for p in probabilities:
            # Use cfg_runs=runs in ONE request instead of runs individual requests
            req = PercolationRequest.from_probability(
                probability=p,
                cfg_seed=seed,
                steps_per_run=steps,
                cfg_runs=runs,
            )
            client.transport.reset_input_buffer()
            client.transport.reset_output_buffer()
            time.sleep(0.05)
            resp = client.run(req)
            rate = resp.spanning_count / runs
            avg_occ = resp.total_occupied / (runs * steps * width)
            hw_rates.append(rate)
            print(f"  HW p={p:.4f}: spanning={resp.spanning_count}/{runs} ({rate:.4f}), avg_occ={avg_occ:.4f}")
            time.sleep(0.2)
    finally:
        client.close()
    return hw_rates


def plot_three_way(probabilities, bfs_rates, sw_fpga_rates, hw_rates, output, runs, width, steps):
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    # Spanning probability plot
    ax1.plot(probabilities, bfs_rates, 'o-', label='BFS (undirected)', linewidth=2, markersize=6)
    ax1.plot(probabilities, sw_fpga_rates, 's-', label='SW FPGA (directed)', linewidth=2, markersize=6)
    if hw_rates is not None:
        ax1.plot(probabilities, hw_rates, '^-', label='HW FPGA (current bitstream)', linewidth=2, markersize=6)
    ax1.axvline(x=0.5927, color='r', linestyle='--', alpha=0.5, label='Critical p=0.5927')
    ax1.set_xlabel('Occupation Probability p (log scale)')
    #ax1.set_xscale('log')
    ax1.set_ylabel('Spanning Probability')
    ax1.set_title(f'Spanning Probability vs p (N={width}x{steps}, {runs} runs)')
    ax1.legend()
    ax1.grid(True, alpha=0.3, which='both')
    ax1.set_ylim(-0.05, 1.05)

    # Difference plot
    if hw_rates is not None:
        diff_sw_hw = [abs(s - h) for s, h in zip(sw_fpga_rates, hw_rates)]
        ax2.plot(probabilities, diff_sw_hw, 'o-', color='red', linewidth=2, markersize=6, label='|SW FPGA - HW FPGA|')
    diff_bfs_sw = [abs(b - s) for b, s in zip(bfs_rates, sw_fpga_rates)]
    ax2.plot(probabilities, diff_bfs_sw, 's-', color='blue', linewidth=2, markersize=6, label='|BFS - SW FPGA|')
    ax2.set_xlabel('Occupation Probability p (log scale)')
    #ax2.set_xscale('log')
    ax2.set_ylabel('Absolute Difference')
    ax2.set_title('Algorithm Differences')
    ax2.legend()
    ax2.grid(True, alpha=0.3, which='both')
    ax2.set_ylim(-0.05, 1.05)

    plt.tight_layout()
    plt.savefig(output, dpi=150)
    print(f"\nPlot saved to {output}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', default='/dev/ttyUSB1')
    parser.add_argument('--baudrate', type=int, default=115200)
    parser.add_argument('--timeout', type=float, default=2.0)
    parser.add_argument('--runs', type=int, default=100)
    parser.add_argument('--width', type=int, default=32)
    parser.add_argument('--steps', type=int, default=64)
    parser.add_argument('--seed', type=lambda x: int(x, 0), default=0x12345678)
    parser.add_argument('--pmin', type=float, default=0.1)
    parser.add_argument('--pmax', type=float, default=0.9)
    parser.add_argument('--points', type=int, default=9)
    parser.add_argument('--output', type=str, default='three_way_comparison.png')
    parser.add_argument('--software-only', action='store_true')
    args = parser.parse_args()

    probabilities = [args.pmin + i * (args.pmax - args.pmin) / (args.points - 1) for i in range(args.points)]

    print(f"Three-way comparison: runs={args.runs}, grid={args.steps}x{args.width}")
    print(f"Probabilities: {[f'{p:.4f}' for p in probabilities]}\n")

    # Software sweeps
    print("Running software sweeps...")
    bfs_rates, sw_fpga_rates = sw_sweep(probabilities, args.runs, args.width, args.steps, args.seed)
    print()

    # Hardware sweep
    hw_rates = None
    if not args.software_only:
        print(f"Running hardware sweep on {args.port}...")
        try:
            hw_rates = hw_sweep(probabilities, args.runs, args.width, args.steps, args.seed, args.port, args.baudrate, args.timeout)
            print()
        except Exception as e:
            print(f"Hardware error: {e}")
            print()

    plot_three_way(probabilities, bfs_rates, sw_fpga_rates, hw_rates, args.output, args.runs, args.width, args.steps)

    # Summary
    print("\n=== Summary ===")
    print(f"BFS critical threshold (spanning≈0.5): ~0.59")
    print(f"SW FPGA directed critical threshold:   ~0.63")
    if hw_rates is not None:
        hw_half = next((p for p, r in zip(probabilities, hw_rates) if r >= 0.5), None)
        print(f"HW FPGA critical threshold:            ~{hw_half}")
        if hw_half and hw_half < 0.5:
            print("  WARNING: HW critical threshold << 0.5 indicates broken bitstream (log2 shift-OR bug)")


if __name__ == '__main__':
    raise SystemExit(main())
