"""Debug script to trace percolation mismatch between BFS and FPGA algorithm.

This script finds the first mismatch and prints the full grid, BFS visited
mask, and FPGA reachability mask for each row to identify where they diverge.
"""

from __future__ import annotations

import random
from collections import deque


def generate_grid(grid_width: int, grid_steps: int, probability: float, rng: random.Random) -> list[list[bool]]:
    return [[rng.random() < probability for _ in range(grid_width)] for _ in range(grid_steps)]


def bfs_spanning(grid: list[list[bool]]) -> tuple[bool, int, list[list[bool]]]:
    """Standard 4-neighbor BFS from top row to bottom row. Returns (spanning, occupied, visited)."""
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

    return spanning, occupied, visited


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


def fpga_spanning(grid: list[list[bool]]) -> tuple[bool, int, list[list[bool]]]:
    """FPGA row-wise frontier algorithm. Returns (spanning, occupied, reach_masks)."""
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
    return spanning, occupied, reach_masks


def print_grid(grid: list[list[bool]], visited: list[list[bool]] | None = None, reach: list[list[bool]] | None = None):
    """Print grid with markers: . = empty, # = occupied, * = visited/reachable."""
    for row_idx, row in enumerate(grid):
        line = ""
        for col_idx, cell in enumerate(row):
            if visited and visited[row_idx][col_idx]:
                line += "*"
            elif reach and reach[row_idx][col_idx]:
                line += "+"
            elif cell:
                line += "#"
            else:
                line += "."
        print(f"  {line}")


def debug_first_mismatch(grid_width: int, grid_steps: int, probability: float, seed: int, max_runs: int = 1000):
    """Find first mismatch and print detailed trace."""
    rng = random.Random(seed)

    for run_idx in range(max_runs):
        grid = generate_grid(grid_width, grid_steps, probability, rng)

        bfs_s, bfs_o, bfs_v = bfs_spanning(grid)
        fpga_s, fpga_o, fpga_r = fpga_spanning(grid)

        if bfs_s != fpga_s:
            print(f"=== MISMATCH at run {run_idx} ===")
            print(f"  BFS:  spanning={bfs_s}, occupied={bfs_o}")
            print(f"  FPGA: spanning={fpga_s}, occupied={fpga_o}")
            print()
            print("Grid (BFS visited = *, FPGA reach = +, occupied = #, empty = .):")
            for row_idx in range(grid_steps):
                line = ""
                for col_idx in range(grid_width):
                    if bfs_v[row_idx][col_idx] and fpga_r[row_idx][col_idx]:
                        line += "*"  # Both agree
                    elif bfs_v[row_idx][col_idx]:
                        line += "B"  # Only BFS
                    elif fpga_r[row_idx][col_idx]:
                        line += "F"  # Only FPGA
                    elif grid[row_idx][col_idx]:
                        line += "#"  # Occupied but not reached
                    else:
                        line += "."
                print(f"  Row {row_idx:2d}: {line}")

            # Find first row where they diverge
            for row_idx in range(grid_steps):
                bfs_row = bfs_v[row_idx]
                fpga_row = fpga_r[row_idx]
                if bfs_row != fpga_row:
                    print(f"\nFirst divergence at row {row_idx}:")
                    print(f"  BFS:  {''.join('*' if x else '.' for x in bfs_row)}")
                    print(f"  FPGA: {''.join('*' if x else '.' for x in fpga_row)}")
                    print(f"  Open: {''.join('#' if x else '.' for x in grid[row_idx])}")
                    if row_idx > 0:
                        print(f"  Prev: {''.join('*' if x else '.' for x in fpga_r[row_idx-1])}")
                    break

            return

    print(f"No mismatches found in {max_runs} runs")


if __name__ == "__main__":
    debug_first_mismatch(64, 64, 0.5927, 0x12345678)
