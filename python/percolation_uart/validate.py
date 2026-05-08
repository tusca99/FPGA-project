"""Validate FPGA percolation algorithm against BFS reference.

This script:
1. Compares FPGA (directed) vs BFS (undirected) percolation
2. Identifies mismatches and categorizes them
3. Generates plots of spanning probability vs p

Usage:
    python -m percolation_uart.validate --runs 1000 --seed 0x12345678
"""

from __future__ import annotations

import argparse
import random
from collections import deque
from dataclasses import dataclass

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


@dataclass
class RunResult:
    spanning: bool
    occupied: int
    bfs_visited: list[list[bool]] | None = None
    fpga_reach: list[list[bool]] | None = None


def generate_grid(grid_width: int, grid_steps: int, probability: float, rng: random.Random) -> list[list[bool]]:
    return [[rng.random() < probability for _ in range(grid_width)] for _ in range(grid_steps)]


def bfs_spanning(grid: list[list[bool]]) -> RunResult:
    """Standard 4-neighbor BFS (undirected percolation)."""
    grid_steps = len(grid)
    grid_width = len(grid[0])
    occupied = sum(1 for row in grid for cell in row if cell)

    visited = [[False] * grid_width for _ in range(grid_steps)]
    queue = deque()

    for col in range(grid_width):
        if grid[0][col]:
            visited[0][col] = True
            queue.append((0, col))

    spanning = False
    while queue:
        row, col = queue.popleft()
        if row == grid_steps - 1:
            spanning = True

        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nr, nc = row + dr, col + dc
            if 0 <= nr < grid_steps and 0 <= nc < grid_width and not visited[nr][nc] and grid[nr][nc]:
                visited[nr][nc] = True
                queue.append((nr, nc))

    return RunResult(spanning=spanning, occupied=occupied, bfs_visited=visited)


def fpga_reach_row(open_row: list[bool], seed_row: list[bool]) -> list[bool]:
    """FPGA horizontal closure (iterative ±1 neighbor expansion)."""
    n = len(open_row)
    reach = [o and s for o, s in zip(open_row, seed_row)]

    while True:
        new_reach = reach[:]
        for i in range(n):
            if reach[i]:
                new_reach[i] = True
            else:
                left = reach[i - 1] if i - 1 >= 0 else False
                right = reach[i + 1] if i + 1 < n else False
                if open_row[i] and (left or right):
                    new_reach[i] = True
        if new_reach == reach:
            break
        reach = new_reach

    return reach


def fpga_spanning(grid: list[list[bool]]) -> RunResult:
    """FPGA row-wise frontier (directed percolation, only downward)."""
    grid_steps = len(grid)
    grid_width = len(grid[0])
    occupied = sum(1 for row in grid for cell in row if cell)

    previous_reach = [False] * grid_width
    reach_masks = []

    for row_idx, open_row in enumerate(grid):
        if row_idx == 0:
            seed_row = open_row
        else:
            seed_row = [o and r for o, r in zip(open_row, previous_reach)]

        row_reach = fpga_reach_row(open_row, seed_row)
        reach_masks.append(row_reach)
        previous_reach = row_reach

    spanning = any(previous_reach)
    return RunResult(spanning=spanning, occupied=occupied, fpga_reach=reach_masks)


def validate(grid_width: int, grid_steps: int, probability: float, seed: int, runs: int) -> dict:
    """Run validation and return statistics."""
    rng = random.Random(seed)
    
    bfs_spanning_count = 0
    fpga_spanning_count = 0
    mismatches = 0
    bfs_more = 0  # BFS says spanning, FPGA says not
    fpga_more = 0  # FPGA says spanning, BFS says not
    
    for run_idx in range(runs):
        grid = generate_grid(grid_width, grid_steps, probability, rng)
        
        bfs_result = bfs_spanning(grid)
        fpga_result = fpga_spanning(grid)
        
        bfs_spanning_count += int(bfs_result.spanning)
        fpga_spanning_count += int(fpga_result.spanning)
        
        if bfs_result.spanning != fpga_result.spanning:
            mismatches += 1
            if bfs_result.spanning and not fpga_result.spanning:
                bfs_more += 1
            else:
                fpga_more += 1
    
    return {
        'runs': runs,
        'probability': probability,
        'bfs_spanning_rate': bfs_spanning_count / runs,
        'fpga_spanning_rate': fpga_spanning_count / runs,
        'mismatches': mismatches,
        'bfs_more': bfs_more,
        'fpga_more': fpga_more,
    }


def sweep_and_plot(grid_width: int, grid_steps: int, seed: int, runs: int, output: str):
    """Run probability sweep and generate comparison plot."""
    probabilities = [0.1, 0.2, 0.3, 0.4, 0.5, 0.55, 0.58, 0.59, 0.5927, 0.6, 0.65, 0.7, 0.8, 0.9]
    
    bfs_rates = []
    fpga_rates = []
    mismatch_rates = []
    
    for p in probabilities:
        print(f"Testing p={p:.4f}...")
        result = validate(grid_width, grid_steps, p, seed, runs)
        bfs_rates.append(result['bfs_spanning_rate'])
        fpga_rates.append(result['fpga_spanning_rate'])
        mismatch_rates.append(result['mismatches'] / runs)
        print(f"  BFS={result['bfs_spanning_rate']:.4f}, FPGA={result['fpga_spanning_rate']:.4f}, "
              f"mismatches={result['mismatches']} (BFS>FPGA:{result['bfs_more']}, FPGA>BFS:{result['fpga_more']})")
    
    # Plot
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))
    
    ax1.plot(probabilities, bfs_rates, 'o-', label='BFS (undirected)', linewidth=2)
    ax1.plot(probabilities, fpga_rates, 's-', label='FPGA (directed)', linewidth=2)
    ax1.axvline(x=0.5927, color='r', linestyle='--', alpha=0.5, label='Critical p=0.5927')
    ax1.set_xlabel('Occupation Probability p')
    ax1.set_ylabel('Spanning Probability')
    ax1.set_title(f'Spanning Probability vs p (N={grid_width}x{grid_steps}, {runs} runs)')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    ax2.plot(probabilities, mismatch_rates, 'o-', color='red', linewidth=2)
    ax2.set_xlabel('Occupation Probability p')
    ax2.set_ylabel('Mismatch Rate')
    ax2.set_title('BFS vs FPGA Mismatch Rate')
    ax2.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output, dpi=150)
    print(f"\nPlot saved to {output}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate FPGA percolation algorithm")
    parser.add_argument("--grid-width", type=int, default=64)
    parser.add_argument("--grid-steps", type=int, default=64)
    parser.add_argument("--probability", type=float, default=0.5927)
    parser.add_argument("--seed", type=lambda s: int(s, 0), default=0x12345678)
    parser.add_argument("--runs", type=int, default=1000)
    parser.add_argument("--sweep", action="store_true", help="Run probability sweep and plot")
    parser.add_argument("--output", type=str, default="percolation_validation.png")
    args = parser.parse_args(argv)
    
    if args.sweep:
        sweep_and_plot(args.grid_width, args.grid_steps, args.seed, args.runs, args.output)
    else:
        result = validate(args.grid_width, args.grid_steps, args.probability, args.seed, args.runs)
        print(f"Validation Results (N={args.grid_width}x{args.grid_steps}, p={args.probability}, {args.runs} runs):")
        print(f"  BFS spanning rate:  {result['bfs_spanning_rate']:.4f}")
        print(f"  FPGA spanning rate: {result['fpga_spanning_rate']:.4f}")
        print(f"  Mismatches: {result['mismatches']} ({result['mismatches']/args.runs*100:.1f}%)")
        print(f"  BFS > FPGA: {result['bfs_more']} (undirected paths that directed misses)")
        print(f"  FPGA > BFS: {result['fpga_more']} (should be 0 after reach_row fix)")
    
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
