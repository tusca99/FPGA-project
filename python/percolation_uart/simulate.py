from __future__ import annotations

import argparse
import math
from percolation_model import FPGAFrontierSimulator


def sweep(prob_values, runs=1000, width=64, steps=64, seed=0x12345678, fpga_mode=True):
    sim = FPGAFrontierSimulator(width=width)
    out = []
    for p in prob_values:
        spanning, total_occ = sim.run_batch(p, steps, runs, seed, fpga_mode=fpga_mode)
        span_frac = spanning / runs
        avg_occ_frac = total_occ / (runs * steps * width)
        out.append((p, span_frac, avg_occ_frac))
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pmin", type=float, default=0.1)
    parser.add_argument("--pmax", type=float, default=0.9)
    parser.add_argument("--steps", type=int, default=64)
    parser.add_argument("--width", type=int, default=64)
    parser.add_argument("--runs", type=int, default=500)
    parser.add_argument("--points", type=int, default=9)
    parser.add_argument("--seed", type=lambda x: int(x, 0), default=0x12345678)
    parser.add_argument("--fpga-mode", action="store_true", help="Emulate FPGA popcount register bug")
    args = parser.parse_args()

    probs = [args.pmin + i * (args.pmax - args.pmin) / (args.points - 1) for i in range(args.points)]
    results = sweep(probs, runs=args.runs, width=args.width, steps=args.steps, seed=args.seed, fpga_mode=args.fpga_mode)

    print("p, spanning_frac, avg_occ_frac")
    for p, sf, af in results:
        print(f"{p:.4f}, {sf:.4f}, {af:.4f}")


if __name__ == '__main__':
    main()
