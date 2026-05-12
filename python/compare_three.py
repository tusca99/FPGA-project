"""Three-way comparison: BFS (undirected) vs Software FPGA (directed) vs Hardware FPGA.

Usage:
    # With FPGA connected:
    python compare_three.py --port /dev/ttyUSB1 --runs 1000 --points 20

    # Software-only (no hardware):
    python compare_three.py --software-only --runs 200 --points 13
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from percolation_uart.algorithms import run_sweep_software
from percolation_uart.client import PercolationClient
from percolation_uart.protocol import PercolationRequest


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_OUTPUT = SCRIPT_DIR / 'output' / 'three_way_comparison.png'


def hw_sweep(probabilities, runs, width, steps, seed, port, baudrate, timeout):
    """Run hardware sweep using cfg_runs per request for speed."""
    client = PercolationClient(port=port, baudrate=baudrate, timeout=timeout)
    hw_rates = []
    hw_metrics = []
    try:
        for p in probabilities:
            req = PercolationRequest.from_probability(
                probability=p,
                cfg_seed=seed,
                steps_per_run=steps,
                cfg_runs=runs,
            )
            client.transport.reset_input_buffer()
            client.transport.reset_output_buffer()
            time.sleep(0.05)
            resp = client.run(req)

            rate = resp.spanning_count / runs
            avg_occ = resp.total_occupied / (runs * steps * width)
            avg_reach = resp.spanning_occupied / runs
            reach_frac = resp.spanning_occupied / resp.total_occupied if resp.total_occupied > 0 else 0.0
            mass = resp.spanning_occupied / resp.spanning_count if resp.spanning_count > 0 else 0.0

            hw_rates.append(rate)
            hw_metrics.append({
                'p': p,
                'spanning_rate': rate,
                'avg_occ': avg_occ,
                'avg_reachable': avg_reach,
                'reachable_fraction': reach_frac,
                'spanning_mass': mass,
                'spanning_count': resp.spanning_count,
            })

            occ_error = abs(avg_occ - p)
            low_stats = 0 < resp.spanning_count < 10
            
            if occ_error > 0.02:
                print(f"    [WARNING] OCCUPANCY BIAS: expected ~{p:.4f}, got {avg_occ:.4f}")
            if low_stats:
                print(f"    [WARNING] LOW STATISTICS: only {resp.spanning_count} spanning runs")

            print(f"  HW p={p:.4f}: span={resp.spanning_count}/{runs} ({rate:.4f}), "
                  f"occ={avg_occ:.4f}, reach={avg_reach:.1f}, "
                  f"reach_frac={reach_frac:.4f}, mass={mass:.1f}")
            time.sleep(0.2)
    finally:
        client.close()
    
    # Compute low_stats flags for visualization
    low_stats_flags = [0 < m['spanning_count'] < 10 for m in hw_metrics]
    return hw_rates, hw_metrics, low_stats_flags


def plot_three_way(probabilities, bfs_rates, sw_fpga_rates, hw_rates, hw_metrics, low_stats_flags, output, runs, width, steps):
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))

    # Plot 1: Spanning probability
    ax1 = axes[0, 0]
    ax1.plot(probabilities, bfs_rates, 'o-', label='BFS (undirected)', linewidth=2, markersize=6)
    ax1.plot(probabilities, sw_fpga_rates, 's-', label='SW FPGA (directed)', linewidth=2, markersize=6)
    if hw_rates is not None:
        ax1.plot(probabilities, hw_rates, '^-', label='HW FPGA', linewidth=2, markersize=6)
    ax1.axvline(x=0.5927, color='r', linestyle='--', alpha=0.5, label='Critical p=0.5927')
    ax1.set_xlabel('Occupation Probability p')
    ax1.set_ylabel('Spanning Probability')
    ax1.set_title(f'Spanning Probability (N={width}x{steps}, {runs} runs)')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    ax1.set_ylim(-0.05, 1.05)

    # Plot 2: Algorithm differences
    ax2 = axes[0, 1]
    if hw_rates is not None:
        diff_sw_hw = [abs(s - h) for s, h in zip(sw_fpga_rates, hw_rates)]
        ax2.plot(probabilities, diff_sw_hw, 'o-', color='red', linewidth=2, markersize=6, label='|SW FPGA - HW FPGA|')
    diff_bfs_sw = [abs(b - s) for b, s in zip(bfs_rates, sw_fpga_rates)]
    ax2.plot(probabilities, diff_bfs_sw, 's-', color='blue', linewidth=2, markersize=6, label='|BFS - SW FPGA|')
    ax2.set_xlabel('Occupation Probability p')
    ax2.set_ylabel('Absolute Difference')
    ax2.set_title('Algorithm Differences')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    ax2.set_ylim(-0.05, 1.05)

    # Plot 3: Reachable fraction
    ax3 = axes[1, 0]
    if hw_metrics:
        reach_fracs = [m['reachable_fraction'] for m in hw_metrics]
        ax3.plot(probabilities, reach_fracs, 'D-', color='green', linewidth=2, markersize=6, label='Reachable / Occupied')
        ax3.set_xlabel('Occupation Probability p')
        ax3.set_ylabel('Reachable Fraction')
        ax3.set_title('Percolation Front Density')
        ax3.legend()
        ax3.grid(True, alpha=0.3)
        ax3.set_ylim(-0.05, 1.05)

    # Plot 4: Spanning cluster mass
    ax4 = axes[1, 1]
    if hw_metrics and low_stats_flags:
        # Separate normal and low-stats points
        normal_probs = [hw_metrics[i]['p'] for i in range(len(hw_metrics)) if not low_stats_flags[i]]
        normal_masses = [hw_metrics[i]['spanning_mass'] for i in range(len(hw_metrics)) if not low_stats_flags[i]]
        low_stat_probs = [hw_metrics[i]['p'] for i in range(len(hw_metrics)) if low_stats_flags[i]]
        low_stat_masses = [hw_metrics[i]['spanning_mass'] for i in range(len(hw_metrics)) if low_stats_flags[i]]
        
        # Plot normal stats as green circles (no line)
        if normal_probs:
            ax4.scatter(normal_probs, normal_masses, marker='o', color='green', s=80, linewidth=0, label='Mass per spanning run', zorder=4)
        
        # Plot low stats with red upper triangles (no line)
        if low_stat_probs:
            ax4.scatter(low_stat_probs, low_stat_masses, marker='^', color='red', s=100, linewidth=0, label='Mass (low statistics)', zorder=5)
        
        ax4.set_xlabel('Occupation Probability p')
        ax4.set_ylabel('Average Reachable Sites')
        ax4.set_title('Spanning Cluster Mass')
        ax4.legend()
        ax4.grid(True, alpha=0.3)

    plt.tight_layout()
    output.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(output, dpi=150)
    print(f"\nPlot saved to {output}")


def _interp_threshold(probs, rates):
    """Linearly interpolate the p where spanning rate crosses 0.5."""
    for i in range(len(rates) - 1):
        if (rates[i] < 0.5 and rates[i+1] >= 0.5) or (rates[i] >= 0.5 and rates[i+1] < 0.5):
            p0, p1 = probs[i], probs[i+1]
            r0, r1 = rates[i], rates[i+1]
            return p0 + (0.5 - r0) / (r1 - r0) * (p1 - p0)
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', default='/dev/ttyUSB1')
    parser.add_argument('--baudrate', type=int, default=115200)
    parser.add_argument('--timeout', type=float, default=2.0)
    parser.add_argument('--runs', type=int, default=100)
    parser.add_argument('--width', type=int, default=64)
    parser.add_argument('--steps', type=int, default=64)
    parser.add_argument('--seed', type=lambda x: int(x, 0), default=0x12345678)
    parser.add_argument('--pmin', type=float, default=0.1)
    parser.add_argument('--pmax', type=float, default=0.9)
    parser.add_argument('--points', type=int, default=9)
    parser.add_argument('--workers', type=int, default=0, help='Number of worker threads for software sweeps; 0 uses auto')
    parser.add_argument('--output', type=str, default=str(DEFAULT_OUTPUT))
    parser.add_argument('--software-only', action='store_true')
    args = parser.parse_args()

    output = Path(args.output)
    if not output.is_absolute():
        output = SCRIPT_DIR / output

    probabilities = [args.pmin + i * (args.pmax - args.pmin) / (args.points - 1) for i in range(args.points)]

    print(f"Three-way comparison: runs={args.runs}, grid={args.steps}x{args.width}")
    print(f"Probabilities: {[f'{p:.4f}' for p in probabilities]}\n")

    # Software sweeps
    print("Running software sweeps...")
    bfs_rates, sw_fpga_rates, _ = run_sweep_software(
        probabilities,
        args.runs,
        args.width,
        args.steps,
        args.seed,
        workers=args.workers,
    )
    print()

    # Hardware sweep
    hw_rates = None
    hw_metrics = None
    low_stats_flags = None
    if not args.software_only:
        print(f"Running hardware sweep on {args.port}...")
        try:
            hw_rates, hw_metrics, low_stats_flags = hw_sweep(probabilities, args.runs, args.width, args.steps, args.seed, args.port, args.baudrate, args.timeout)
            print()
        except Exception as e:
            print(f"Hardware error: {e}\n")

    plot_three_way(probabilities, bfs_rates, sw_fpga_rates, hw_rates, hw_metrics, low_stats_flags, output, args.runs, args.width, args.steps)

    # Summary
    print("\n=== Summary ===")
    bfs_thr = _interp_threshold(probabilities, bfs_rates)
    sw_thr = _interp_threshold(probabilities, sw_fpga_rates)
    print(f"BFS critical threshold (spanning≈0.5): ~{bfs_thr:.4f}" if bfs_thr else "BFS threshold: out of range")
    print(f"SW FPGA directed critical threshold:   ~{sw_thr:.4f}" if sw_thr else "SW FPGA threshold: out of range")
    if hw_rates is not None:
        hw_thr = _interp_threshold(probabilities, hw_rates)
        print(f"HW FPGA critical threshold:            ~{hw_thr:.4f}" if hw_thr else "HW FPGA threshold: out of range")
        if hw_thr and hw_thr < 0.5:
            print("  WARNING: HW critical threshold << 0.5 indicates broken bitstream")

    # Physical validation
    if hw_metrics:
        print("\n=== Physical Validation ===")
        max_occ_error = max(abs(m['avg_occ'] - m['p']) for m in hw_metrics)
        print(f"Max occupancy bias: {max_occ_error:.4f} (should be < 0.02)")
        print("  [PASS]" if max_occ_error <= 0.02 else "  [FAIL]")

        reach_fracs = [m['reachable_fraction'] for m in hw_metrics]
        non_mono = sum(1 for i in range(len(reach_fracs)-1) if reach_fracs[i+1] < reach_fracs[i] - 0.05)
        print(f"Reachable fraction monotonicity: {non_mono} violations")
        print("  [PASS]" if non_mono <= 3 else "  [FAIL]")

        if hw_thr:
            crit_idx = min(range(len(probabilities)), key=lambda i: abs(probabilities[i] - hw_thr))
            crit_reach = hw_metrics[crit_idx]['reachable_fraction']
            print(f"Reachable fraction at p_c={hw_thr:.3f}: {crit_reach:.3f}")
            print("  [PASS]" if 0.2 < crit_reach < 0.5 else "  [UNEXPECTED]")


if __name__ == '__main__':
    raise SystemExit(main())
