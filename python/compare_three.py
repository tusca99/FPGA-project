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
    hw_metrics = []  # list of dicts with detailed metrics per p
    try:
        for p in probabilities:
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
            avg_reachable = resp.spanning_occupied / runs  # average reachable sites per run
            reachable_fraction = resp.spanning_occupied / resp.total_occupied if resp.total_occupied > 0 else 0.0
            spanning_mass = resp.spanning_occupied / resp.spanning_count if resp.spanning_count > 0 else 0.0
            hw_rates.append(rate)
            hw_metrics.append({
                'p': p,
                'spanning_rate': rate,
                'avg_occ': avg_occ,
                'avg_reachable': avg_reachable,
                'reachable_fraction': reachable_fraction,
                'spanning_mass': spanning_mass,
            })
            print(f"  HW p={p:.4f}: span={resp.spanning_count}/{runs} ({rate:.4f}), "
                  f"occ={avg_occ:.4f}, reach={avg_reachable:.1f}, "
                  f"reach_frac={reachable_fraction:.4f}, mass={spanning_mass:.1f}")
            time.sleep(0.2)
    finally:
        client.close()
    return hw_rates, hw_metrics


def plot_three_way(probabilities, bfs_rates, sw_fpga_rates, hw_rates, hw_metrics, output, runs, width, steps):
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))

    # Plot 1: Spanning probability
    ax1 = axes[0, 0]
    ax1.plot(probabilities, bfs_rates, 'o-', label='BFS (undirected)', linewidth=2, markersize=6)
    ax1.plot(probabilities, sw_fpga_rates, 's-', label='SW FPGA (directed)', linewidth=2, markersize=6)
    if hw_rates is not None:
        ax1.plot(probabilities, hw_rates, '^-', label='HW FPGA', linewidth=2, markersize=6)
    ax1.axvline(x=0.5927, color='r', linestyle='--', alpha=0.5, label='Critical p=0.5927')
    ax1.set_xlabel('Occupation Probability p')
    ax1.set_ylabel('Spanning Probability')
    ax1.set_title(f'Spanning Probability (N={width}x{steps}, {runs} runs)')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    ax1.set_ylim(-0.05, 1.05)

    # Plot 2: Algorithm differences
    ax2 = axes[0, 1]
    if hw_rates is not None:
        diff_sw_hw = [abs(s - h) for s, h in zip(sw_fpga_rates, hw_rates)]
        ax2.plot(probabilities, diff_sw_hw, 'o-', color='red', linewidth=2, markersize=6, label='|SW FPGA - HW FPGA|')
    diff_bfs_sw = [abs(b - s) for b, s in zip(bfs_rates, sw_fpga_rates)]
    ax2.plot(probabilities, diff_bfs_sw, 's-', color='blue', linewidth=2, markersize=6, label='|BFS - SW FPGA|')
    ax2.set_xlabel('Occupation Probability p')
    ax2.set_ylabel('Absolute Difference')
    ax2.set_title('Algorithm Differences')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    ax2.set_ylim(-0.05, 1.05)

    # Plot 3: Reachable fraction (physics metric)
    ax3 = axes[1, 0]
    if hw_metrics:
        reach_fracs = [m['reachable_fraction'] for m in hw_metrics]
        ax3.plot(probabilities, reach_fracs, 'D-', color='green', linewidth=2, markersize=6, label='Reachable / Occupied')
        ax3.set_xlabel('Occupation Probability p')
        ax3.set_ylabel('Reachable Fraction')
        ax3.set_title('Percolation Front Density')
        ax3.legend()
        ax3.grid(True, alpha=0.3)
        ax3.set_ylim(-0.05, 1.05)

    # Plot 4: Spanning cluster mass
    ax4 = axes[1, 1]
    if hw_metrics:
        masses = [m['spanning_mass'] for m in hw_metrics]
        ax4.plot(probabilities, masses, 'v-', color='purple', linewidth=2, markersize=6, label='Mass per spanning run')
        ax4.set_xlabel('Occupation Probability p')
        ax4.set_ylabel('Average Reachable Sites')
        ax4.set_title('Spanning Cluster Mass')
        ax4.legend()
        ax4.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(output, dpi=150)
    print(f"\nPlot saved to {output}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', default='/dev/ttyUSB1')
    parser.add_argument('--baudrate', type=int, default=115200)
    parser.add_argument('--timeout', type=float, default=2.0)
    parser.add_argument('--runs', type=int, default=100)
    parser.add_argument('--width', type=int, default=64)
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
    hw_metrics = None
    if not args.software_only:
        print(f"Running hardware sweep on {args.port}...")
        try:
            hw_rates, hw_metrics = hw_sweep(probabilities, args.runs, args.width, args.steps, args.seed, args.port, args.baudrate, args.timeout)
            print()
        except Exception as e:
            print(f"Hardware error: {e}")
            print()

    plot_three_way(probabilities, bfs_rates, sw_fpga_rates, hw_rates, hw_metrics, args.output, args.runs, args.width, args.steps)

    # Summary
    print("\n=== Summary ===")

    def _interp_threshold(probs, rates):
        """Linearly interpolate the p where spanning rate crosses 0.5."""
        for i in range(len(rates) - 1):
            if (rates[i] < 0.5 and rates[i+1] >= 0.5) or (rates[i] >= 0.5 and rates[i+1] < 0.5):
                p0, p1 = probs[i], probs[i+1]
                r0, r1 = rates[i], rates[i+1]
                return p0 + (0.5 - r0) / (r1 - r0) * (p1 - p0)
        return None

    bfs_thr = _interp_threshold(probabilities, bfs_rates)
    sw_thr = _interp_threshold(probabilities, sw_fpga_rates)
    print(f"BFS critical threshold (spanning≈0.5): ~{bfs_thr:.4f}" if bfs_thr else "BFS threshold: out of range")
    print(f"SW FPGA directed critical threshold:   ~{sw_thr:.4f}" if sw_thr else "SW FPGA threshold: out of range")
    if hw_rates is not None:
        hw_thr = _interp_threshold(probabilities, hw_rates)
        print(f"HW FPGA critical threshold:            ~{hw_thr:.4f}" if hw_thr else "HW FPGA threshold: out of range")
        if hw_thr and hw_thr < 0.5:
            print("  WARNING: HW critical threshold << 0.5 indicates broken bitstream (log2 shift-OR bug)")


if __name__ == '__main__':
    raise SystemExit(main())
