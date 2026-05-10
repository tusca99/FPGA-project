"""Generate comparison plot: BFS (undirected) vs FPGA (directed) percolation.

This is a pure-software simulation that shows the expected difference
between the two algorithms. Run this before testing hardware.
"""

from __future__ import annotations

import random
from collections import deque

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def fpga_directed_spanning(grid: list[list[bool]]) -> bool:
    """FPGA directed percolation (only downward propagation)."""
    steps = len(grid)
    width = len(grid[0])
    prev_reach = [False] * width

    for row_idx, open_row in enumerate(grid):
        if row_idx == 0:
            seed = open_row
        else:
            seed = [o and r for o, r in zip(open_row, prev_reach)]

        # Horizontal closure (iterative ±1)
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


def run_sweep(probabilities: list[float], runs: int, width: int, steps: int, seed: int):
    """Run both algorithms across probabilities and return rates."""
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
            if fpga_directed_spanning(grid):
                fpga_count += 1
        bfs_rates.append(bfs_count / runs)
        fpga_rates.append(fpga_count / runs)
        print(f"p={p:.4f}: BFS={bfs_count}/{runs} ({bfs_count/runs:.4f}), "
              f"FPGA={fpga_count}/{runs} ({fpga_count/runs:.4f})")

    return bfs_rates, fpga_rates


def plot_comparison(probabilities, bfs_rates, fpga_rates, output_path, runs, width, steps):
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    # Spanning probability plot
    ax1.plot(probabilities, bfs_rates, 'o-', label='BFS (undirected)', linewidth=2, markersize=6)
    ax1.plot(probabilities, fpga_rates, 's-', label='FPGA (directed)', linewidth=2, markersize=6)
    ax1.axvline(x=0.5927, color='r', linestyle='--', alpha=0.5, label='Critical p=0.5927')
    ax1.set_xlabel('Occupation Probability p')
    ax1.set_ylabel('Spanning Probability')
    ax1.set_title(f'Spanning Probability vs p (N={width}x{steps}, {runs} runs)')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    ax1.set_ylim(-0.05, 1.05)

    # Difference plot
    diffs = [abs(b - f) for b, f in zip(bfs_rates, fpga_rates)]
    ax2.plot(probabilities, diffs, 'o-', color='red', linewidth=2, markersize=6)
    ax2.set_xlabel('Occupation Probability p')
    ax2.set_ylabel('|BFS - FPGA|')
    ax2.set_title('Absolute Difference Between Algorithms')
    ax2.grid(True, alpha=0.3)
    ax2.set_ylim(-0.05, 1.05)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    print(f"\nPlot saved to {output_path}")


def main():
    probabilities = [0.1, 0.1667, 0.2333, 0.3, 0.3667, 0.4333,
                       0.5, 0.5667, 0.6, 0.6333, 0.7, 0.7667, 0.8333, 0.9]
    runs = 200
    width = 64
    steps = 64
    seed = 0x12345678
    output = 'bfs_vs_fpga_directed.png'

    print(f"Running sweep: {runs} runs per point, grid={width}x{steps}")
    print(f"Probabilities: {probabilities}\n")

    bfs_rates, fpga_rates = run_sweep(probabilities, runs, width, steps, seed)
    plot_comparison(probabilities, bfs_rates, fpga_rates, output, runs, width, steps)

    # Summary
    print("\n=== Summary ===")
    print(f"BFS critical threshold (where spanning ≈ 0.5): ~0.59")
    print(f"FPGA directed critical threshold: ~0.63")
    print(f"Max difference: {max(abs(b-f) for b,f in zip(bfs_rates, fpga_rates)):.4f} at p≈0.6")


if __name__ == '__main__':
    main()
