from __future__ import annotations

import random
from typing import Tuple

UQ32_SCALE = 1 << 32


def probability_to_uq32(p: float) -> int:
    if not 0.0 <= p < 1.0:
        raise ValueError("p must be in [0,1)")
    return min(int(round(p * UQ32_SCALE)), 0xFFFFFFFF)


def popcount(x: int) -> int:
    return x.bit_count()


def mask_width(width: int) -> int:
    return (1 << width) - 1


def reach_row(open_row_mask: int, seed_row_mask: int, width: int) -> int:
    """Compute horizontal closure (VHDL `reach_row` equivalent).

    Uses shifts of powers of two (1,2,4,...) and AND with open mask.
    """
    mask = mask_width(width)
    open_u = open_row_mask & mask
    stage_reach = open_u & seed_row_mask

    step = 1
    while step < width:
        # same condition as VHDL: apply shift step if step < width
        if step < width:
            left = (stage_reach << step) & mask
            right = (stage_reach >> step) & mask
            stage_reach = stage_reach | ((left | right) & open_u)
        step *= 2

    return stage_reach & mask


class FPGAFrontierSimulator:
    """Simulate FPGA frontier row-wise processing.

    Modes:
    - `fpga_mode=True` replicates the popcount register behavior that causes
      the final-row undercount observed in the RTL (popcount added one cycle late).
    - `fpga_mode=False` is the ideal correct accounting.
    """

    def __init__(self, width: int = 64):
        self.width = width
        self.mask = mask_width(width)

    def _gen_row_mask(self, rng: random.Random, probability: float) -> int:
        # Align RNG usage with reference: use rng.random() per cell
        m = 0
        for i in range(self.width):
            if rng.random() < probability:
                m |= 1 << i
        return m

    def run_single(self, probability: float, steps_per_run: int, seed: int | None, fpga_mode: bool = True, rng: random.Random | None = None) -> Tuple[bool, int]:
        """Run single percolation trial.

        Returns (spanning, occupied_count)
        """
        if rng is None:
            rng = random.Random(seed)

        previous_reach = 0
        spanning = False
        run_occupied = 0
        pending_popcount = 0  # emulates popcount_reg registered one cycle

        for row in range(steps_per_run):
            row_mask = self._gen_row_mask(rng, probability)

            # emulate popcount pipeline: add pending from previous cycle
            if fpga_mode:
                run_occupied += pending_popcount
            else:
                run_occupied += popcount(row_mask)

            # compute seed and reach
            if row == 0:
                seed_mask = row_mask
            else:
                seed_mask = row_mask & previous_reach

            row_reach = reach_row(row_mask, seed_mask, self.width)
            previous_reach = row_reach

            # set pending_popcount to be added next cycle (fpga_mode)
            pending_popcount = popcount(row_mask)

            # check spanning at last row
            if row == steps_per_run - 1 and row_reach != 0:
                spanning = True

        # end for
        if fpga_mode:
            # FPGA bug: final pending_popcount never added to run_occupied before sum
            # In actual RTL occupied_sum <= occupied_sum + run_occupied executed
            # while pending_popcount still pending. So final row not counted.
            occupied_count = run_occupied
        else:
            occupied_count = run_occupied

        return spanning, occupied_count

    def run_batch(self, probability: float, steps_per_run: int, cfg_runs: int, seed: int, fpga_mode: bool = True) -> Tuple[int, int]:
        """Run `cfg_runs` trials and return (spanning_count, total_occupied)."""
        spanning = 0
        total_occ = 0
        rng = random.Random(seed)
        for i in range(cfg_runs):
            s, occ = self.run_single(probability, steps_per_run, seed=None, fpga_mode=fpga_mode, rng=rng)
            spanning += int(s)
            total_occ += occ
        return spanning, total_occ


def compare_with_reference(probability: float, steps_per_run: int, cfg_runs: int, seed: int, width: int = 64, fpga_mode: bool = True, max_print: int = 10):
    """Run per-run comparison between FPGA-like model and canonical BFS reference.

    Prints up to `max_print` differing runs.
    """
    from python.percolation_uart.reference import simulate_run

    sim = FPGAFrontierSimulator(width=width)
    rng = random.Random(seed)
    diffs = 0
    for i in range(cfg_runs):
        # Use same RNG instance for both simulators to align draws
        # Save RNG state to replay for reference
        state = rng.getstate()
        s_fpga, occ_fpga = sim.run_single(probability, steps_per_run, seed=None, fpga_mode=fpga_mode, rng=rng)

        # restore rng state for canonical reference
        rng.setstate(state)
        # canonical simulate_run expects a Random instance; use it directly
        ref = simulate_run(width, steps_per_run, probability, rng)

        if (s_fpga != ref.spanning) or (occ_fpga != ref.occupied_sites):
            diffs += 1
            if diffs <= max_print:
                print(f"Run {i}: FPGA(spanning={s_fpga}, occ={occ_fpga}) vs REF(spanning={ref.spanning}, occ={ref.occupied_sites})")

    print(f"Compared {cfg_runs} runs, differences={diffs}")
