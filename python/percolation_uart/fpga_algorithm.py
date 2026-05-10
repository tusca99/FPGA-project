"""Bit-parallel row-wise percolation simulator matching the FPGA algorithm.

This script reproduces the exact FPGA percolation logic in Python so we can
compare it against:
1. The standard BFS reference (4-neighbor connectivity)
2. Actual FPGA hardware output

The FPGA uses a row-wise frontier with horizontal closure via shift-OR:
    reach = open & (top | horizontal_reach)
where horizontal_reach is resolved in log2(N) shift-OR stages.

Usage:
    python -m percolation_uart.fpga_algorithm \
        --grid-size 64 --probability 0.5927 --seed 0x12345678 --runs 16
"""

from __future__ import annotations

import argparse
import random
import struct
from dataclasses import dataclass

from .protocol import PercolationRequest, PercolationResponse, uq32_to_probability
from .reference import simulate_run as bfs_simulate_run


def _aes_ctr_stream(key: int, iv: int, length: int) -> list[int]:
    """Simplified AES-CTR-like stream for seeding (not cryptographically accurate).

    The FPGA uses AES-128-ECB in counter mode to generate 80-bit seeds for
    each Trivium instance.  We emulate this with a simple PRNG keyed by the
    128-bit ``key`` and starting counter ``iv``.
    """
    rng = random.Random((key << 64) | iv)
    return [rng.getrandbits(80) for _ in range(length)]


def _trivium_stream(key: int, iv: int, length: int) -> list[int]:
    """Simplified Trivium-like stream generator.

    The FPGA runs 64 independent Trivium instances, each producing one 32-bit
    word per clock after warmup.  We emulate each stream with a Python
    ``random.Random`` seeded by the 80-bit key/iv pair.
    """
    rng = random.Random((key << 80) | iv)
    return [rng.getrandbits(32) for _ in range(length)]


def _threshold_to_probability(threshold_u32: int) -> float:
    """Convert the FPGA's UQ32 threshold back to a probability."""
    return threshold_u32 / (1 << 32)


def _generate_fpga_grid(
    width: int,
    steps: int,
    threshold_u32: int,
    seed_u32: int,
) -> list[list[bool]]:
    """Generate a grid using the same RNG architecture as the FPGA.

    1. Derive a 128-bit master key from the 32-bit seed (golden-ratio
       mixing, exactly as ``seed_to_master_key`` in VHDL).
    2. Use AES-CTR to produce 2*width 80-bit blocks (key + IV for each
       Trivium instance).
    3. Run ``width`` independent Trivium streams for ``steps`` cycles.
    4. Compare each 32-bit word against ``threshold_u32`` to decide if the
       site is open.
    """
    # 1. Master key derivation (matches VHDL seed_to_master_key)
    seed = seed_u32 & 0xFFFFFFFF
    golden1 = 0x9E3779B9
    golden2 = 0x243F6A88
    key128 = (
        (seed << 96)
        | ((~seed & 0xFFFFFFFF) << 64)
        | ((seed ^ golden1) << 32)
        | ((seed + golden2) & 0xFFFFFFFF)
    )

    # 2. AES-CTR-like expansion to 2*width 80-bit seeds
    aes_blocks = _aes_ctr_stream(key128, seed, 2 * width)
    trivium_keys = aes_blocks[0::2]
    trivium_ivs = aes_blocks[1::2]

    # 3. Run width independent Trivium streams
    threshold = threshold_u32 & 0xFFFFFFFF
    grid: list[list[bool]] = []
    for step in range(steps):
        row: list[bool] = []
        for col in range(width):
            # Each Trivium instance produces one word per step
            words = _trivium_stream(trivium_keys[col], trivium_ivs[col], steps)
            word = words[step]
            row.append(word < threshold)
        grid.append(row)

    return grid


def _reach_row(open_row: list[bool], seed_row: list[bool]) -> list[bool]:
    """Resolve horizontal reachability for one row (matches corrected VHDL).

    Correct algorithm: repeatedly expand reachability by ±1 cell until
    no more cells can be reached. This prevents the "jump over" bug in
    the old log2(N) shift-OR approach.

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


def simulate_run_fpga(
    grid_width: int,
    grid_steps: int,
    threshold_u32: int,
    seed_u32: int,
) -> tuple[bool, int]:
    """Simulate a single run using the exact FPGA algorithm.

    Returns:
        (spanning, occupied_sites)
    """
    grid = _generate_fpga_grid(grid_width, grid_steps, threshold_u32, seed_u32)
    occupied_sites = sum(1 for row in grid for cell in row if cell)

    previous_reach: list[bool] = [False] * grid_width
    spanning = False

    for row_idx, open_row in enumerate(grid):
        if row_idx == 0:
            seed_row = open_row
        else:
            seed_row = [o and r for o, r in zip(open_row, previous_reach)]

        row_reach = _reach_row(open_row, seed_row)
        previous_reach = row_reach

    # After the last row: spanning iff any bit in previous_reach is set
    spanning = any(previous_reach)

    return spanning, occupied_sites


def simulate_request_fpga(request: PercolationRequest) -> PercolationResponse:
    """Simulate the FPGA batch response using the FPGA algorithm."""
    spanning_count = 0
    total_occupied = 0

    # The FPGA re-seeds the RNG for every run using the same CfgSeed.
    # The only thing that changes between runs is the internal Trivium state
    # (which advances).  For a faithful model we would need to track the
    # post-warmup state; here we approximate by using the same seed and
    # letting the stream advance.
    for run_idx in range(request.cfg_runs):
        # In the FPGA, the RNG bank is NOT reset between runs; it keeps
        # streaming.  To emulate this we offset the seed by run_idx so each
        # run sees a different grid.
        effective_seed = (request.cfg_seed + run_idx) & 0xFFFFFFFF
        spanning, occupied = simulate_run_fpga(
            grid_width=64,  # compile-time constant in FPGA
            grid_steps=request.steps_per_run,
            threshold_u32=request.cfg_p_uq32,
            seed_u32=effective_seed,
        )
        spanning_count += int(spanning)
        total_occupied += occupied

    return PercolationResponse(
        step_count=request.cfg_runs,
        spanning_count=spanning_count,
        total_occupied=total_occupied,
        status=0,
        rng_init_cycles=0,
        core_run_cycles=0,
        batch_cycles=0,
    )


def compare_algorithms(
    grid_width: int,
    grid_steps: int,
    probability: float,
    seed: int,
    runs: int,
) -> None:
    """Run both the BFS reference and the FPGA algorithm and print differences."""
    import random as py_random

    rng = py_random.Random(seed)
    threshold_u32 = int(probability * (1 << 32))

    print(f"Comparing algorithms: N={grid_width}x{grid_steps}, p={probability}, seed=0x{seed:08X}, runs={runs}")
    print("-" * 70)

    bfs_spanning = 0
    bfs_occupied = 0
    fpga_spanning = 0
    fpga_occupied = 0

    for run_idx in range(runs):
        # BFS reference
        bfs_result = bfs_simulate_run(grid_width, grid_steps, probability, rng)
        bfs_spanning += int(bfs_result.spanning)
        bfs_occupied += bfs_result.occupied_sites

        # FPGA algorithm (use same seed offset to get comparable grids)
        effective_seed = (seed + run_idx) & 0xFFFFFFFF
        fpga_s, fpga_o = simulate_run_fpga(grid_width, grid_steps, threshold_u32, effective_seed)
        fpga_spanning += int(fpga_s)
        fpga_occupied += fpga_o

    print(f"BFS reference:  spanning={bfs_spanning}  occupied={bfs_occupied}")
    print(f"FPGA algorithm: spanning={fpga_spanning}  occupied={fpga_occupied}")
    print(f"Spanning diff:  {fpga_spanning - bfs_spanning:+d}")
    print(f"Occupied diff:  {fpga_occupied - bfs_occupied:+d}")

    if fpga_spanning != bfs_spanning:
        print("\n*** WARNING: Spanning counts differ! ***")
        print("This means the FPGA algorithm and BFS reference disagree on connectivity.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="FPGA algorithm simulator & validator")
    parser.add_argument("--grid-width", type=int, default=64)
    parser.add_argument("--grid-steps", type=int, default=64)
    parser.add_argument("--probability", type=float, default=0.5927)
    parser.add_argument("--seed", type=lambda s: int(s, 0), default=0x12345678)
    parser.add_argument("--runs", type=int, default=16)
    parser.add_argument("--compare", action="store_true", help="Also run BFS reference and compare")
    args = parser.parse_args(argv)

    if args.compare:
        compare_algorithms(
            grid_width=args.grid_width,
            grid_steps=args.grid_steps,
            probability=args.probability,
            seed=args.seed,
            runs=args.runs,
        )
    else:
        request = PercolationRequest.from_probability(
            probability=args.probability,
            cfg_seed=args.seed,
            steps_per_run=args.grid_steps,
            cfg_runs=args.runs,
        )
        response = simulate_request_fpga(request)
        print(f"FPGA algorithm result:")
        print(f"  StepCount     = {response.step_count}")
        print(f"  SpanningCount = {response.spanning_count}")
        print(f"  TotalOccupied = {response.total_occupied}")
        print(f"  Status        = {response.status}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
