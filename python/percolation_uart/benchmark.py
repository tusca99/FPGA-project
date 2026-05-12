"""Benchmark CLI for percolation software and FPGA UART paths.

Hardware note: FPGA grid width is compile-time constant in bitstream.
Only `steps_per_run` is runtime configurable through UART protocol.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import time
from pathlib import Path

from .algorithms import run_sweep_software
from .client import PercolationClient
from .protocol import PercolationRequest


def _build_probabilities(pmin: float, pmax: float, points: int) -> list[float]:
    if points < 2:
        raise ValueError("points must be >= 2")
    return [pmin + i * (pmax - pmin) / (points - 1) for i in range(points)]


def _mean_std_err(samples: list[float]) -> tuple[float, float, float]:
    if not samples:
        return 0.0, 0.0, 0.0
    n = len(samples)
    mean = sum(samples) / n
    if n < 2:
        return mean, 0.0, 0.0
    variance = sum((x - mean) ** 2 for x in samples) / (n - 1)
    std = math.sqrt(variance)
    err = std / math.sqrt(n)
    return mean, std, err


def _run_software_benchmark(
    probabilities: list[float],
    runs: int,
    width: int,
    steps: int,
    seed: int,
    workers: int,
    repeats: int,
) -> list[dict[str, float]]:
    rows: list[dict[str, float]] = []
    for p in probabilities:
        bfs_samples: list[float] = []
        fpga_samples: list[float] = []
        occ_samples: list[float] = []
        latency_samples: list[float] = []
        runs_per_s_samples: list[float] = []
        cells_per_s_samples: list[float] = []

        for _ in range(repeats):
            t0 = time.perf_counter()
            bfs_rates, fpga_rates, occ_rates = run_sweep_software(
                [p],
                runs,
                width,
                steps,
                seed,
                workers=workers,
            )
            dt = time.perf_counter() - t0

            bfs_samples.append(bfs_rates[0])
            fpga_samples.append(fpga_rates[0])
            occ_samples.append(occ_rates[0])
            latency_samples.append(dt)
            runs_per_s_samples.append(runs / dt if dt > 0 else 0.0)
            cells_per_s_samples.append((runs * steps * width) / dt if dt > 0 else 0.0)

        bfs_mean, _, _ = _mean_std_err(bfs_samples)
        fpga_mean, _, _ = _mean_std_err(fpga_samples)
        occ_mean, _, _ = _mean_std_err(occ_samples)
        latency_mean, latency_std, latency_err = _mean_std_err(latency_samples)
        runs_per_s_mean, runs_per_s_std, runs_per_s_err = _mean_std_err(runs_per_s_samples)
        cells_per_s_mean, cells_per_s_std, cells_per_s_err = _mean_std_err(cells_per_s_samples)

        rows.append(
            {
                "p": p,
                "sw_repeats": float(repeats),
                "sw_bfs_rate": bfs_mean,
                "sw_fpga_rate": fpga_mean,
                "sw_occ": occ_mean,
                "sw_latency_s": latency_mean,
                "sw_latency_s_std": latency_std,
                "sw_latency_s_err": latency_err,
                "sw_runs_per_s": runs_per_s_mean,
                "sw_runs_per_s_std": runs_per_s_std,
                "sw_runs_per_s_err": runs_per_s_err,
                "sw_cells_per_s": cells_per_s_mean,
                "sw_cells_per_s_std": cells_per_s_std,
                "sw_cells_per_s_err": cells_per_s_err,
            }
        )
    return rows


def _run_hardware_benchmark(
    probabilities: list[float],
    runs: int,
    hw_width: int,
    steps: int,
    seed: int,
    port: str,
    baudrate: int,
    timeout: float,
    settle_s: float,
    repeats: int,
) -> list[dict[str, float]]:
    rows: list[dict[str, float]] = []
    client = PercolationClient(port=port, baudrate=baudrate, timeout=timeout)
    try:
        for p in probabilities:
            rate_samples: list[float] = []
            occ_samples: list[float] = []
            occ_bias_samples: list[float] = []
            mass_samples: list[float] = []
            span_count_samples: list[float] = []
            latency_samples: list[float] = []
            runs_per_s_samples: list[float] = []
            cells_per_s_samples: list[float] = []
            low_stats_hits = 0

            for _ in range(repeats):
                req = PercolationRequest.from_probability(
                    probability=p,
                    cfg_seed=seed,
                    steps_per_run=steps,
                    cfg_runs=runs,
                )
                client.transport.reset_input_buffer()
                client.transport.reset_output_buffer()
                if settle_s > 0:
                    time.sleep(settle_s)

                t0 = time.perf_counter()
                resp = client.run(req)
                dt = time.perf_counter() - t0

                rate = resp.spanning_count / runs
                avg_occ = resp.total_occupied / (runs * steps * hw_width)
                occ_bias = avg_occ - p
                low_stats = 0 < resp.spanning_count < 10
                mass = resp.spanning_occupied / resp.spanning_count if resp.spanning_count > 0 else 0.0

                rate_samples.append(rate)
                occ_samples.append(avg_occ)
                occ_bias_samples.append(occ_bias)
                mass_samples.append(mass)
                span_count_samples.append(float(resp.spanning_count))
                latency_samples.append(dt)
                runs_per_s_samples.append(runs / dt if dt > 0 else 0.0)
                cells_per_s_samples.append((runs * steps * hw_width) / dt if dt > 0 else 0.0)
                if low_stats:
                    low_stats_hits += 1

            rate_mean, _, _ = _mean_std_err(rate_samples)
            occ_mean, _, _ = _mean_std_err(occ_samples)
            occ_bias_mean, _, _ = _mean_std_err(occ_bias_samples)
            mass_mean, _, _ = _mean_std_err(mass_samples)
            span_count_mean, _, _ = _mean_std_err(span_count_samples)
            latency_mean, latency_std, latency_err = _mean_std_err(latency_samples)
            runs_per_s_mean, runs_per_s_std, runs_per_s_err = _mean_std_err(runs_per_s_samples)
            cells_per_s_mean, cells_per_s_std, cells_per_s_err = _mean_std_err(cells_per_s_samples)

            rows.append(
                {
                    "p": p,
                    "hw_repeats": float(repeats),
                    "hw_spanning_rate": rate_mean,
                    "hw_occ": occ_mean,
                    "hw_occ_bias": occ_bias_mean,
                    "hw_mass": mass_mean,
                    "hw_spanning_count": span_count_mean,
                    "hw_low_stats": 1.0 if low_stats_hits > 0 else 0.0,
                    "hw_low_stats_count": float(low_stats_hits),
                    "hw_latency_s": latency_mean,
                    "hw_latency_s_std": latency_std,
                    "hw_latency_s_err": latency_err,
                    "hw_runs_per_s": runs_per_s_mean,
                    "hw_runs_per_s_std": runs_per_s_std,
                    "hw_runs_per_s_err": runs_per_s_err,
                    "hw_cells_per_s": cells_per_s_mean,
                    "hw_cells_per_s_std": cells_per_s_std,
                    "hw_cells_per_s_err": cells_per_s_err,
                }
            )
    finally:
        client.close()

    return rows


def _merge_rows(
    probabilities: list[float],
    sw_rows: list[dict[str, float]] | None,
    hw_rows: list[dict[str, float]] | None,
) -> list[dict[str, float]]:
    merged: list[dict[str, float]] = []
    for idx, p in enumerate(probabilities):
        row: dict[str, float] = {"p": p}
        if sw_rows is not None:
            row.update(sw_rows[idx])
        if hw_rows is not None:
            row.update(hw_rows[idx])
        merged.append(row)
    return merged


def _print_table(rows: list[dict[str, float]], have_sw: bool, have_hw: bool) -> None:
    headers = ["p"]
    if have_sw:
        headers += ["sw_latency_s", "sw_runs_per_s", "sw_cells_per_s"]
    if have_hw:
        headers += [
            "hw_latency_s",
            "hw_runs_per_s",
            "hw_runs_per_s_err",
            "hw_cells_per_s",
            "hw_cells_per_s_err",
            "hw_occ_bias",
            "hw_low_stats",
        ]

    int_columns = {
        "hw_runs_per_s",
        "hw_runs_per_s_err",
        "hw_cells_per_s",
        "hw_cells_per_s_err",
        "hw_low_stats",
    }

    print("\n=== Benchmark Summary ===")
    print(" ".join(f"{h:>14}" for h in headers))
    for row in rows:
        values: list[str] = []
        for h in headers:
            if h in int_columns:
                values.append(f"{int(round(row.get(h, 0.0))):14d}")
            else:
                values.append(f"{row.get(h, float('nan')):14.6f}")
        print(" ".join(values))


def _write_csv(path: Path, rows: list[dict[str, float]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames: list[str] = []
    for row in rows:
        for key in row.keys():
            if key not in fieldnames:
                fieldnames.append(key)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _write_json(path: Path, rows: list[dict[str, float]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(rows, f, indent=2)


def _linear_regression_3sigma(
    x: list[float],
    y: list[float],
    n_points: int = 300,
) -> tuple[list[float], list[float], list[float], list[float]]:
    """Return x-grid, fitted line, and +/-3 sigma confidence band for mean response."""
    if not x or not y or len(x) != len(y):
        return [], [], [], []
    if len(x) < 2:
        return x[:], y[:], y[:], y[:]

    n = len(x)
    x_mean = sum(x) / n
    y_mean = sum(y) / n
    sxx = sum((xi - x_mean) ** 2 for xi in x)
    if sxx <= 0.0:
        return x[:], y[:], y[:], y[:]

    sxy = sum((xi - x_mean) * (yi - y_mean) for xi, yi in zip(x, y))
    slope = sxy / sxx
    intercept = y_mean - slope * x_mean

    y_hat = [intercept + slope * xi for xi in x]
    dof = n - 2
    if dof > 0:
        sse = sum((yi - yfi) ** 2 for yi, yfi in zip(y, y_hat))
        sigma = math.sqrt(sse / dof)
    else:
        sigma = 0.0

    x_min = min(x)
    x_max = max(x)
    if n_points < 2 or x_max <= x_min:
        xs = x[:]
    else:
        xs = [x_min + i * (x_max - x_min) / (n_points - 1) for i in range(n_points)]

    fit: list[float] = []
    upper: list[float] = []
    lower: list[float] = []
    for xi in xs:
        y_fit = intercept + slope * xi
        se_mean = sigma * math.sqrt((1.0 / n) + ((xi - x_mean) ** 2 / sxx)) if n > 0 else 0.0
        delta = 3.0 * se_mean
        fit.append(y_fit)
        upper.append(y_fit + delta)
        lower.append(y_fit - delta)

    return xs, fit, upper, lower


def _plot_throughput(path: Path, rows: list[dict[str, float]], have_sw: bool, have_hw: bool) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    p = [r["p"] for r in rows]

    fig, ax = plt.subplots(1, 1, figsize=(10, 5))
    if have_sw:
        sw_y = [r["sw_runs_per_s"] for r in rows]
        sw_err = [r.get("sw_runs_per_s_err", 0.0) for r in rows]

        # Error bars as points only (no connecting line)
        ax.errorbar(
            p,
            sw_y,
            yerr=sw_err,
            fmt="o",
            linestyle="none",
            capsize=3,
            markersize=5,
            label="SW runs/s (mean ± err)",
            alpha=0.9,
        )

        # Linear regression trend + 3 sigma confidence band
        sw_xi, sw_yi, sw_hi, sw_lo = _linear_regression_3sigma(p, sw_y)
        if sw_xi:
            ax.plot(sw_xi, sw_yi, "-", linewidth=2, alpha=0.9, label="SW linear fit")
            ax.fill_between(sw_xi, sw_lo, sw_hi, alpha=0.15, label="SW fit +/- 3sigma")

    if have_hw:
        hw_y = [r["hw_runs_per_s"] for r in rows]
        hw_err = [r.get("hw_runs_per_s_err", 0.0) for r in rows]

        # Error bars as points only (no connecting line)
        ax.errorbar(
            p,
            hw_y,
            yerr=hw_err,
            fmt="s",
            linestyle="none",
            capsize=3,
            markersize=5,
            label="HW runs/s (mean ± err)",
            alpha=0.9,
        )

        # Linear regression trend + 3 sigma confidence band
        hw_xi, hw_yi, hw_hi, hw_lo = _linear_regression_3sigma(p, hw_y)
        if hw_xi:
            ax.plot(hw_xi, hw_yi, "-", linewidth=2, alpha=0.9, label="HW linear fit")
            ax.fill_between(hw_xi, hw_lo, hw_hi, alpha=0.15, label="HW fit +/- 3sigma")

    ax.set_xlabel("Occupation probability p")
    ax.set_ylabel("Throughput [runs/s]")
    ax.set_title("Percolation Benchmark Throughput")
    ax.grid(True, alpha=0.3)
    ax.legend()
    fig.tight_layout()

    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=150)


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark software and hardware percolation paths")
    parser.add_argument("--port", default="/dev/ttyUSB1")
    parser.add_argument("--baudrate", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--runs", type=int, default=1000, help="cfg_runs per point")
    parser.add_argument("--steps", type=int, default=64, help="Grid height (runtime configurable)")
    parser.add_argument("--width", type=int, default=64, help="Software grid width")
    parser.add_argument("--hw-width", type=int, default=64, help="Hardware compile-time width (bitstream constant)")
    parser.add_argument("--seed", type=lambda x: int(x, 0), default=0x12345678)
    parser.add_argument("--pmin", type=float, default=0.50)
    parser.add_argument("--pmax", type=float, default=0.70)
    parser.add_argument("--points", type=int, default=9)
    parser.add_argument("--workers", type=int, default=0, help="Software workers; 0 uses auto")
    parser.add_argument("--repeats", type=int, default=1, help="Repeated measurements per probability point")
    parser.add_argument("--settle", type=float, default=0.05, help="UART settle delay before each HW request [s]")
    parser.add_argument("--software-only", action="store_true")
    parser.add_argument("--hardware-only", action="store_true")
    parser.add_argument("--csv", type=str, default="")
    parser.add_argument("--json", type=str, default="")
    parser.add_argument("--plot", type=str, default="")
    args = parser.parse_args()

    if args.software_only and args.hardware_only:
        raise SystemExit("choose only one of --software-only or --hardware-only")
    if args.repeats < 1:
        raise SystemExit("--repeats must be >= 1")

    probabilities = _build_probabilities(args.pmin, args.pmax, args.points)

    have_sw = not args.hardware_only
    have_hw = not args.software_only

    print(f"Benchmark points: {[f'{p:.4f}' for p in probabilities]}")
    print(f"Runs per point: {args.runs}, repeats per point: {args.repeats}, steps: {args.steps}")
    if have_hw:
        print(f"Hardware width fixed by bitstream: {args.hw_width}")
        if args.width != args.hw_width:
            print(
                "[WARNING] software width differs from hardware width; "
                "HW metrics use --hw-width, SW metrics use --width"
            )

    sw_rows = None
    hw_rows = None

    if have_sw:
        print("Running software benchmark...")
        sw_rows = _run_software_benchmark(
            probabilities=probabilities,
            runs=args.runs,
            width=args.width,
            steps=args.steps,
            seed=args.seed,
            workers=args.workers,
            repeats=args.repeats,
        )

    if have_hw:
        print(f"Running hardware benchmark on {args.port}...")
        hw_rows = _run_hardware_benchmark(
            probabilities=probabilities,
            runs=args.runs,
            hw_width=args.hw_width,
            steps=args.steps,
            seed=args.seed,
            port=args.port,
            baudrate=args.baudrate,
            timeout=args.timeout,
            settle_s=args.settle,
            repeats=args.repeats,
        )

    rows = _merge_rows(probabilities, sw_rows, hw_rows)
    _print_table(rows, have_sw=have_sw, have_hw=have_hw)

    if args.csv:
        csv_path = Path(args.csv)
        _write_csv(csv_path, rows)
        print(f"CSV saved to {csv_path}")
    if args.json:
        json_path = Path(args.json)
        _write_json(json_path, rows)
        print(f"JSON saved to {json_path}")
    if args.plot:
        plot_path = Path(args.plot)
        _plot_throughput(plot_path, rows, have_sw=have_sw, have_hw=have_hw)
        print(f"Plot saved to {plot_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())