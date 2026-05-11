"""Percolation algorithms: BFS reference and FPGA-directed row-wise frontier.

All algorithms operate on a grid of bools: grid[row][col].
"""

from __future__ import annotations

import random
from collections import deque
from typing import Tuple


def generate_grid(grid_width: int, grid_steps: int, probability: float, rng: random.Random) -> list[list[bool]]:
    """Generate a random occupancy grid."""
    return [[rng.random() < probability for _ in range(grid_width)] for _ in range(grid_steps)]


def bfs_spanning(grid: list[list[bool]]) -> tuple[bool, int]:
    """Standard 4-neighbor BFS (undirected percolation).

    Returns (spanning, occupied_sites).
    """
    steps = len(grid)
    width = len(grid[0])
    occupied = sum(1 for row in grid for cell in row if cell)

    visited = [[False] * width for _ in range(steps)]
    queue = deque()

    for c in range(width):
        if grid[0][c]:
            visited[0][c] = True
            queue.append((0, c))

    spanning = False
    while queue:
        r, c = queue.popleft()
        if r == steps - 1:
            spanning = True

        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nr, nc = r + dr, c + dc
            if 0 <= nr < steps and 0 <= nc < width and not visited[nr][nc] and grid[nr][nc]:
                visited[nr][nc] = True
                queue.append((nr, nc))

    return spanning, occupied


def fpga_reach_row(open_row: list[bool], seed_row: list[bool]) -> list[bool]:
    """Horizontal closure: iterative ±1 neighbor expansion.

    Matches the corrected VHDL prefix-scan semantics.
    Formula: new_reach[i] = reach[i] | (open[i] & (reach[i-1] | reach[i+1]))
    """
    n = len(open_row)
    reach = [o and s for o, s in zip(open_row, seed_row)]

    while True:
        new_reach = reach[:]
        for i in range(n):
            if not reach[i] and open_row[i]:
                left = reach[i - 1] if i > 0 else False
                right = reach[i + 1] if i < n - 1 else False
                if left or right:
                    new_reach[i] = True
        if new_reach == reach:
            break
        reach = new_reach

    return reach


def fpga_directed_spanning(grid: list[list[bool]]) -> tuple[bool, int]:
    """FPGA row-wise frontier (directed percolation, only downward).

    Returns (spanning, occupied_sites).
    """
    steps = len(grid)
    width = len(grid[0])
    occupied = sum(1 for row in grid for cell in row if cell)

    prev_reach = [False] * width
    for row_idx, open_row in enumerate(grid):
        if row_idx == 0:
            seed = open_row
        else:
            seed = [o and r for o, r in zip(open_row, prev_reach)]

        reach = fpga_reach_row(open_row, seed)
        prev_reach = reach

    return any(prev_reach), occupied


def run_sweep_software(
    probabilities: list[float],
    runs: int,
    width: int,
    steps: int,
    seed: int,
) -> tuple[list[float], list[float], list[float]]:
    """Run BFS and FPGA-directed sweeps. Returns (bfs_rates, fpga_rates, occupancy_rates)."""
    bfs_rates = []
    fpga_rates = []
    occ_rates = []

    for p in probabilities:
        rng = random.Random(seed)
        bfs_count = 0
        fpga_count = 0
        total_occ = 0

        for _ in range(runs):
            grid = generate_grid(width, steps, p, rng)
            bfs_s, occ = bfs_spanning(grid)
            fpga_s, _ = fpga_directed_spanning(grid)
            bfs_count += int(bfs_s)
            fpga_count += int(fpga_s)
            total_occ += occ

        bfs_rates.append(bfs_count / runs)
        fpga_rates.append(fpga_count / runs)
        occ_rates.append(total_occ / (runs * steps * width))
        print(f"  SW p={p:.4f}: BFS={bfs_count}/{runs}, FPGA={fpga_count}/{runs}, occ={occ_rates[-1]:.4f}")

    return bfs_rates, fpga_rates, occ_rates
