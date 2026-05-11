"""Percolation algorithms: BFS reference and FPGA-directed row-wise frontier.

All algorithms operate on a grid of bools: grid[row][col].
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import os
import random
from collections import deque

try:
    import numpy as np
    from numba import njit
except ImportError:  # pragma: no cover - optional acceleration path
    np = None
    njit = None


_NUMBA_AVAILABLE = np is not None and njit is not None


if _NUMBA_AVAILABLE:

    @njit(cache=True)
    def _next_uniform_u01(state):
        state = state * np.uint64(6364136223846793005) + np.uint64(1)
        return state, (state >> np.uint64(11)) * (1.0 / 9007199254740992.0)


    @njit(cache=True)
    def _simulate_sweep_numba(probability, runs, width, steps, seed):
        total_cells = width * steps
        bfs_count = 0
        fpga_count = 0
        total_occ = 0

        grid = np.empty(total_cells, dtype=np.uint8)
        visited = np.empty(total_cells, dtype=np.uint8)
        queue_rows = np.empty(total_cells, dtype=np.int32)
        queue_cols = np.empty(total_cells, dtype=np.int32)
        prev_reach = np.empty(width, dtype=np.uint8)
        reach = np.empty(width, dtype=np.uint8)
        next_reach = np.empty(width, dtype=np.uint8)

        state = np.uint64(seed) ^ np.uint64(0x9E3779B97F4A7C15)

        for _ in range(runs):
            occupied = 0
            for index in range(total_cells):
                state, sample = _next_uniform_u01(state)
                cell_open = np.uint8(sample < probability)
                grid[index] = cell_open
                visited[index] = 0
                occupied += cell_open
            total_occ += occupied

            # BFS spanning check.
            head = 0
            tail = 0
            spanning = 0
            for col in range(width):
                if grid[col] != 0:
                    visited[col] = 1
                    queue_rows[tail] = 0
                    queue_cols[tail] = col
                    tail += 1

            while head < tail:
                row = queue_rows[head]
                col = queue_cols[head]
                head += 1

                if row == steps - 1:
                    spanning = 1

                grid_index = row * width + col

                if row > 0:
                    neighbor = grid_index - width
                    if visited[neighbor] == 0 and grid[neighbor] != 0:
                        visited[neighbor] = 1
                        queue_rows[tail] = row - 1
                        queue_cols[tail] = col
                        tail += 1

                if row + 1 < steps:
                    neighbor = grid_index + width
                    if visited[neighbor] == 0 and grid[neighbor] != 0:
                        visited[neighbor] = 1
                        queue_rows[tail] = row + 1
                        queue_cols[tail] = col
                        tail += 1

                if col > 0:
                    neighbor = grid_index - 1
                    if visited[neighbor] == 0 and grid[neighbor] != 0:
                        visited[neighbor] = 1
                        queue_rows[tail] = row
                        queue_cols[tail] = col - 1
                        tail += 1

                if col + 1 < width:
                    neighbor = grid_index + 1
                    if visited[neighbor] == 0 and grid[neighbor] != 0:
                        visited[neighbor] = 1
                        queue_rows[tail] = row
                        queue_cols[tail] = col + 1
                        tail += 1

            bfs_count += spanning

            # FPGA-directed row-wise frontier.
            for col in range(width):
                prev_reach[col] = 0

            for row in range(steps):
                base_index = row * width
                for col in range(width):
                    if row == 0:
                        reach[col] = grid[base_index + col]
                    else:
                        reach[col] = grid[base_index + col] & prev_reach[col]

                changed = 1
                while changed != 0:
                    changed = 0
                    for col in range(width):
                        if reach[col] == 0 and grid[base_index + col] != 0:
                            left = reach[col - 1] if col > 0 else 0
                            right = reach[col + 1] if col + 1 < width else 0
                            if left != 0 or right != 0:
                                next_reach[col] = 1
                                changed = 1
                            else:
                                next_reach[col] = 0
                        else:
                            next_reach[col] = reach[col]

                    for col in range(width):
                        reach[col] = next_reach[col]

                for col in range(width):
                    prev_reach[col] = reach[col]

            fpga_spanning = 0
            for col in range(width):
                if prev_reach[col] != 0:
                    fpga_spanning = 1
                    break

            fpga_count += fpga_spanning

        return bfs_count, fpga_count, total_occ


def _simulate_sweep_python(probability: float, runs: int, width: int, steps: int, seed: int) -> tuple[int, int, int]:
    rng = random.Random(seed)
    bfs_count = 0
    fpga_count = 0
    total_occ = 0

    for _ in range(runs):
        grid = generate_grid(width, steps, probability, rng)
        bfs_s, occ = bfs_spanning(grid)
        fpga_s, _ = fpga_directed_spanning(grid)
        bfs_count += int(bfs_s)
        fpga_count += int(fpga_s)
        total_occ += occ

    return bfs_count, fpga_count, total_occ


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
    workers: int | None = None,
) -> tuple[list[float], list[float], list[float]]:
    """Run BFS and FPGA-directed sweeps. Returns (bfs_rates, fpga_rates, occupancy_rates)."""
    if not probabilities:
        return [], [], []

    bfs_rates: list[float] = [0.0] * len(probabilities)
    fpga_rates: list[float] = [0.0] * len(probabilities)
    occ_rates: list[float] = [0.0] * len(probabilities)

    max_workers = min(len(probabilities), os.cpu_count() or 1) if workers is None or workers <= 0 else min(workers, len(probabilities))

    if _NUMBA_AVAILABLE:
        # Compile once in the main thread so worker threads only execute the hot path.
        _simulate_sweep_numba(0.0, 0, 1, 1, 0)

        if max_workers > 1:
            print(f"  SW sweeps: numba + {max_workers} threads")
            with ThreadPoolExecutor(max_workers=max_workers) as executor:
                futures = [executor.submit(_simulate_sweep_numba, p, runs, width, steps, seed) for p in probabilities]
                for index, (p, future) in enumerate(zip(probabilities, futures)):
                    bfs_count, fpga_count, total_occ = future.result()
                    bfs_rates[index] = bfs_count / runs
                    fpga_rates[index] = fpga_count / runs
                    occ_rates[index] = total_occ / (runs * steps * width)
                    print(
                        f"  SW p={p:.4f}: BFS={bfs_count}/{runs}, "
                        f"FPGA={fpga_count}/{runs}, occ={occ_rates[index]:.4f}"
                    )
            return bfs_rates, fpga_rates, occ_rates

        print("  SW sweeps: numba")
        for index, p in enumerate(probabilities):
            bfs_count, fpga_count, total_occ = _simulate_sweep_numba(p, runs, width, steps, seed)
            bfs_rates[index] = bfs_count / runs
            fpga_rates[index] = fpga_count / runs
            occ_rates[index] = total_occ / (runs * steps * width)
            print(f"  SW p={p:.4f}: BFS={bfs_count}/{runs}, FPGA={fpga_count}/{runs}, occ={occ_rates[index]:.4f}")
        return bfs_rates, fpga_rates, occ_rates

    print("  SW sweeps: pure Python")
    for index, p in enumerate(probabilities):
        bfs_count, fpga_count, total_occ = _simulate_sweep_python(p, runs, width, steps, seed)
        bfs_rates[index] = bfs_count / runs
        fpga_rates[index] = fpga_count / runs
        occ_rates[index] = total_occ / (runs * steps * width)
        print(f"  SW p={p:.4f}: BFS={bfs_count}/{runs}, FPGA={fpga_count}/{runs}, occ={occ_rates[index]:.4f}")

    return bfs_rates, fpga_rates, occ_rates
