"""Pure-Python reference simulator for the percolation benchmark."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from random import Random

from .protocol import PercolationRequest, PercolationResponse, uq32_to_probability


@dataclass(frozen=True)
class RunResult:
    """Per-run statistics used by the reference simulator."""

    spanning: bool
    occupied_sites: int
    bfs_step_count: int


def _validate_grid_size(grid_size: int) -> None:
    if grid_size < 1:
        raise ValueError("grid_size must be positive")


def simulate_run(grid_size: int, probability: float, rng: Random) -> RunResult:
    """Simulate a single site-percolation run on a square grid."""

    _validate_grid_size(grid_size)
    if not 0.0 <= probability < 1.0:
        raise ValueError("probability must be in the range [0, 1)")

    grid = [[rng.random() < probability for _ in range(grid_size)] for _ in range(grid_size)]
    occupied_sites = sum(1 for row in grid for cell in row if cell)

    visited = [[False] * grid_size for _ in range(grid_size)]
    queue = deque()

    for col in range(grid_size):
        if grid[0][col]:
            visited[0][col] = True
            queue.append((0, col))

    spanning = False
    bfs_step_count = 0

    while queue:
        row, col = queue.popleft()
        bfs_step_count += 1

        if row == grid_size - 1:
            spanning = True

        for delta_row, delta_col in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            next_row = row + delta_row
            next_col = col + delta_col
            if not (0 <= next_row < grid_size and 0 <= next_col < grid_size):
                continue
            if visited[next_row][next_col] or not grid[next_row][next_col]:
                continue

            visited[next_row][next_col] = True
            queue.append((next_row, next_col))

    return RunResult(
        spanning=spanning,
        occupied_sites=occupied_sites,
        bfs_step_count=bfs_step_count,
    )


def simulate_request(request: PercolationRequest, rng: Random | None = None) -> PercolationResponse:
    """Simulate the FPGA batch response for the given request."""

    if rng is None:
        rng = Random(request.cfg_seed)

    probability = uq32_to_probability(request.cfg_p_uq32)
    spanning_count = 0
    total_occupied = 0
    total_bfs_steps = 0

    for _ in range(request.cfg_runs):
        run = simulate_run(request.grid_size, probability, rng)
        spanning_count += int(run.spanning)
        total_occupied += run.occupied_sites
        total_bfs_steps += run.bfs_step_count

    return PercolationResponse(
        step_count=request.cfg_runs,
        spanning_count=spanning_count,
        total_occupied=total_occupied,
        bfs_step_count=total_bfs_steps,
    )
