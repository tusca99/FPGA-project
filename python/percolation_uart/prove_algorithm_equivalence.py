"""Prove that the FPGA row-wise frontier algorithm is equivalent to 4-neighbor BFS.

This script generates the same random grids using Python's random.Random,
then runs both:
1. Standard BFS (4-neighbor connectivity)
2. FPGA row-wise frontier with horizontal closure

If the algorithms are equivalent, the spanning and occupied counts must match
exactly for every single run.

Usage:
    python -m percolation_uart.prove_algorithm_equivalence \
        --grid-width 64 --grid-steps 64 --runs 1000 --seed 0x12345678
"""

from __future__ import annotations

import argparse
import random
from collections import deque


def generate_grid(grid_width: int, grid_steps: int, probability: float, rng: random.Random) -> list[list[bool]]:
    """Generate a random occupancy grid."""
    return [[rng.random() < probability for _ in range(grid_width)] for _ in range(grid_steps)]


def bfs_spanning(grid: list[list[bool]]) -> tuple[bool, int]:
    """Standard 4-neighbor BFS from top row to bottom row."""
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

    return spanning, occupied


def fpga_reach_row(open_row: list[bool], seed_row: list[bool]) -> list[bool]:
    """FPGA horizontal closure (iterative ±1 neighbor expansion).

    Correct algorithm: repeatedly expand reachability by ±1 cell until
    no more cells can be reached. This matches the corrected VHDL.

    Formula: new_reach[i] = reach[i] | (open[i] & (reach[i-1] | reach[i+1]))
    """
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


def fpga_spanning(grid: list[list[bool]]) -> tuple[bool, int]:
    """FPGA row-wise frontier algorithm."""
    grid_steps = len(grid)
    grid_width = len(grid[0])
    occupied = sum(1 for row in grid for cell in row if cell)

    previous_reach = [False] * grid_width

    for row_idx, open_row in enumerate(grid):
        if row_idx == 0:
            seed_row = open_row
        else:
            seed_row = [o and r for o, r in zip(open_row, previous_reach)]

        row_reach = fpga_reach_row(open_row, seed_row)
        previous_reach = row_reach

    spanning = any(previous_reach)
    return spanning, occupied


def prove_equivalence(grid_width: int, grid_steps: int, probability: float, seed: int, runs: int) -> None:
    """Run both algorithms on identical grids and report any mismatches."""
    rng = random.Random(seed)
    mismatches = 0
    total_spanning_bfs = 0
    total_spanning_fpga = 0

    print(f"Proving equivalence: N={grid_width}x{grid_steps}, p={probability}, seed=0x{seed:08X}, runs={runs}")
    print("-" * 70)

    for run_idx in range(runs):
        grid = generate_grid(grid_width, grid_steps, probability, rng)

        bfs_s, bfs_o = bfs_spanning(grid)
        fpga_s, fpga_o = fpga_spanning(grid)

        total_spanning_bfs += int(bfs_s)
        total_spanning_fpga += int(fpga_s)

        if bfs_s != fpga_s or bfs_o != fpga_o:
            mismatches += 1
            print(f"  MISMATCH at run {run_idx}:")
            print(f"    BFS:  spanning={bfs_s}, occupied={bfs_o}")
            print(f"    FPGA: spanning={fpga_s}, occupied={fpga_o}")
            if mismatches >= 10:
                print("  (suppressing further mismatches)")
                break

    print("-" * 70)
    print(f"Results after {runs} runs:")
    print(f"  BFS spanning rate:  {total_spanning_bfs / runs:.4f}")
    print(f"  FPGA spanning rate: {total_spanning_fpga / runs:.4f}")
    print(f"  Mismatches: {mismatches}")

    if mismatches == 0:
        print("\n✅ SUCCESS: Algorithms are equivalent for all tested grids!")
    else:
        print(f"\n❌ FAILURE: {mismatches} mismatches found. Algorithms differ.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Prove FPGA algorithm = BFS")
    parser.add_argument("--grid-width", type=int, default=64)
    parser.add_argument("--grid-steps", type=int, default=64)
    parser.add_argument("--probability", type=float, default=0.5927)
    parser.add_argument("--seed", type=lambda s: int(s, 0), default=0x12345678)
    parser.add_argument("--runs", type=int, default=1000)
    args = parser.parse_args(argv)

    prove_equivalence(
        grid_width=args.grid_width,
        grid_steps=args.grid_steps,
        probability=args.probability,
        seed=args.seed,
        runs=args.runs,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
