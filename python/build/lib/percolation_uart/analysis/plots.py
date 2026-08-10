"""Plotting functions for percolation benchmark analysis."""

from __future__ import annotations

import math
from collections import defaultdict
from pathlib import Path

from .data import (
    FRONTIER_CYCLES_PER_STEP,
    RNG_WARMUP_CYCLES,
    RNG_WARMUP_S,
    UART_WIRE_S_CALC,
    DEFAULT_DB,
    DEFAULT_DB2,
    _PLOT_STYLE,
    _connect,
    _find_sessions_by_params,
    _session_data,
    _closest_row,
    _find_square_sessions,
)
from .stats import (
    _mean_std_err,
    _group_by_p,
    _aggregate_mass_by_p,
    _linear_regression_3sigma,
    _sigmoid_regression_3sigma,
    _sigmoid_regression_nonlinear,
    _binomial_logit_regression_from_buckets,
    _plot_with_error_bars,
    _plot_with_binomial_logit,
    _plot_with_sigmoid_fit,
    _plot_with_sigmoid_fit_nonlinear,
    _derived_front_density_rows,
)


def plot_dashboard(summary_rows: list[dict[str, object]], raw_rows: list[dict[str, object]], output: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(2, 2, figsize=(14, 10))

    hw_summary = [row for row in summary_rows if "hw_runs_per_s" in row]
    if hw_summary:
        hw_p = [float(row["p"]) for row in hw_summary]
        hw_runs = [float(row["hw_runs_per_s"]) for row in hw_summary]
        hw_runs_err = [float(row.get("hw_runs_per_s_err", 0.0)) for row in hw_summary]
        _plot_with_error_bars(
            axes[0, 0],
            hw_p,
            hw_runs,
            hw_runs_err,
            marker="s",
            color="tab:blue",
            label="HW runs/s (mean ± err)",
            fit_label="HW linear fit",
            shade_label="HW fit ± 3σ",
        )
    axes[0, 0].set_xlabel("Occupation probability p")
    axes[0, 0].set_ylabel("Throughput [runs/s]")
    axes[0, 0].set_title("Percolation Throughput")
    axes[0, 0].grid(True, alpha=0.3)
    axes[0, 0].legend()

    bias_p, bias_mean, bias_std, _ = _group_by_p(raw_rows, "occ_bias")
    if bias_p:
        _plot_with_error_bars(
            axes[0, 1],
            bias_p,
            bias_mean,
            bias_std,
            marker="o",
            color="tab:green",
            label="Occupancy bias (mean ± std)",
            fit_label="Bias linear fit",
            shade_label="Bias fit ± 3σ",
        )
    axes[0, 1].axhline(0.0, color="black", linewidth=1, alpha=0.5)
    axes[0, 1].set_xlabel("Occupation probability p")
    axes[0, 1].set_ylabel("Observed - target occupancy")
    axes[0, 1].set_title("Percolation Occupancy Bias")
    axes[0, 1].grid(True, alpha=0.3)
    axes[0, 1].legend()

    lat_p, lat_mean, lat_std, _ = _group_by_p(raw_rows, "core_latency_per_run_cycles_est")
    if lat_p:
        _plot_with_error_bars(
            axes[1, 0],
            lat_p,
            lat_mean,
            lat_std,
            marker="s",
            color="tab:orange",
            label="Estimated core cycles/run (mean ± std)",
            fit_label="Core latency fit",
            shade_label="Core latency fit ± 3σ",
        )
    axes[1, 0].set_xlabel("Occupation probability p")
    axes[1, 0].set_ylabel("Estimated cycles per run")
    axes[1, 0].set_title("Percolation Core Latency Estimate")
    axes[1, 0].grid(True, alpha=0.3)
    axes[1, 0].legend()

    _plot_with_binomial_logit(
        axes[1, 1],
        raw_rows,
        marker="^",
        color="tab:red",
        label="Spanning probability (mean ± std)",
        fit_label="Binomial logistic fit",
        shade_label="Fit 95% CI (α=0.05)",
    )
    axes[1, 1].set_xlabel("Occupation probability p")
    axes[1, 1].set_ylabel("Spanning probability")
    axes[1, 1].set_title("Percolation Spanning Probability (phase transition)")
    axes[1, 1].grid(True, alpha=0.3)
    axes[1, 1].set_ylim(-0.05, 1.05)
    axes[1, 1].legend()

    fig.tight_layout()

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)


def plot_front_density(rows: list[dict[str, object]], output: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    derived_rows = _derived_front_density_rows(rows)
    p_values, density_values, density_std, density_err = _group_by_p(derived_rows, "front_density")

    fig, ax = plt.subplots(1, 1, figsize=(10, 5))
    if p_values:
        _plot_with_sigmoid_fit_nonlinear(
            ax,
            p_values,
            density_values,
            density_std,
            marker="D",
            color="green",
            label="Reachable density (mean ± std)",
            fit_label="Sigmoid (approx.)",
            shade_label="Sigmoid approx ± 3σ",
        )

    ax.set_xlabel("Occupation probability p")
    ax.set_ylabel("Reachable density")
    ax.set_title("Percolation Front Density")
    ax.grid(True, alpha=0.3)
    ax.set_ylim(-0.05, 1.05)
    ax.legend()
    fig.tight_layout()

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)


def plot_cluster_mass(rows: list[dict[str, object]], output: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    p_values, mass_values, spanning_count_totals, low_stat_flags = _aggregate_mass_by_p(rows)

    fig, ax = plt.subplots(1, 1, figsize=(10, 5))
    if p_values:
        positive_points = [i for i, mass in enumerate(mass_values) if mass > 0]
        if positive_points:
            positive_p = [p_values[i] for i in positive_points]
            positive_mass = [mass_values[i] for i in positive_points]
            ax.scatter(
                positive_p,
                positive_mass,
                marker="v",
                s=32,
                color="purple",
                label="Pooled mass per spanning run",
            )

        low_points = [i for i, low_stat in enumerate(low_stat_flags) if low_stat != 0.0 and mass_values[i] > 0]
        if low_points:
            low_p = [p_values[i] for i in low_points]
            low_mass = [mass_values[i] for i in low_points]
            ax.scatter(
                low_p,
                low_mass,
                marker="o",
                s=26,
                facecolors="none",
                edgecolors="tab:gray",
                alpha=0.6,
                label="Low-stat pooled points",
            )

        ax.set_yscale("log")

    ax.set_xlabel("Occupation probability p")
    ax.set_ylabel("Average reachable sites")
    ax.set_title("Spanning Cluster Mass (pooled per p, log y)")
    ax.grid(True, alpha=0.3)
    ax.legend()
    fig.tight_layout()

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)


def plot_occupancy_bias(rows: list[dict[str, object]], output: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    p_values, bias_values, bias_std, bias_err = _group_by_p(rows, "occ_bias")

    fig, ax = plt.subplots(1, 1, figsize=(10, 5))
    if p_values:
        ax.errorbar(
            p_values,
            bias_values,
            yerr=bias_std,
            fmt="o",
            linestyle="none",
            capsize=3,
            markersize=5,
            color="tab:blue",
            label="HW occ bias (mean ± std)",
        )
        fit_x, fit_y, fit_hi, fit_lo = _linear_regression_3sigma(p_values, bias_values)
        if fit_x:
            ax.plot(fit_x, fit_y, "-", linewidth=2, alpha=0.9, color="tab:blue", label="Bias linear fit")
            ax.fill_between(fit_x, fit_lo, fit_hi, color="tab:blue", alpha=0.15, label="Bias fit ± 3σ")

    ax.axhline(0.0, color="black", linewidth=1, alpha=0.5)
    ax.set_xlabel("Occupation probability p")
    ax.set_ylabel("Observed - target occupancy")
    ax.set_title("Percolation Benchmark Occupancy Bias")
    ax.grid(True, alpha=0.3)
    ax.legend()
    fig.tight_layout()

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)


def plot_core_latency(rows: list[dict[str, object]], output: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    p_values, latency_cycles, latency_std, latency_err = _group_by_p(rows, "core_latency_per_run_cycles_est")

    fig, ax = plt.subplots(1, 1, figsize=(10, 5))
    if p_values:
        ax.errorbar(
            p_values,
            latency_cycles,
            yerr=latency_std,
            fmt="s",
            linestyle="none",
            capsize=3,
            markersize=5,
            color="tab:orange",
            label="Estimated core cycles/run (mean ± err)",
        )
        fit_x, fit_y, fit_hi, fit_lo = _linear_regression_3sigma(p_values, latency_cycles)
        if fit_x:
            ax.plot(fit_x, fit_y, "-", linewidth=2, alpha=0.9, color="tab:orange", label="Core latency fit")
            ax.fill_between(fit_x, fit_lo, fit_hi, color="tab:orange", alpha=0.15, label="Core latency fit ± 3σ")

    ax.set_xlabel("Occupation probability p")
    ax.set_ylabel("Estimated cycles per run")
    ax.set_title("Percolation Benchmark Core Latency Estimate")
    ax.grid(True, alpha=0.3)
    ax.legend()
    fig.tight_layout()

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)


def plot_spanning_probability(rows: list[dict[str, object]], output: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(1, 1, figsize=(10, 5))
    _plot_with_binomial_logit(
        ax,
        rows,
        marker="^",
        color="tab:red",
        label="Spanning probability (mean ± std)",
        fit_label="Binomial logistic fit",
        shade_label="Fit 95% CI (α=0.05)",
    )

    ax.set_xlabel("Occupation probability p")
    ax.set_ylabel("Spanning probability")
    ax.set_title("Percolation Benchmark Spanning Probability (phase transition)")
    ax.grid(True, alpha=0.3)
    ax.set_ylim(-0.05, 1.05)
    ax.legend()
    fig.tight_layout()

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)


def plot_latency_decomposition(summary_rows: list[dict[str, object]], raw_rows: list[dict[str, object]], output: Path) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    if not summary_rows or not raw_rows:
        fig, ax = plt.subplots(1, 1, figsize=(10, 5))
        ax.set_axis_off()
        ax.text(0.5, 0.5, "No rows available for latency decomposition", ha="center", va="center")
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, dpi=150)
        return

    first_raw = raw_rows[0]
    first_summary = summary_rows[0]
    runs = float(first_raw.get("runs", 1.0))
    steps = float(first_raw.get("steps", 0.0))
    baudrate = 115200.0
    uart_wire_s = float(first_raw.get("uart_wire_s", (16 + 16) * 10.0 / baudrate))
    ideal_core_cycles_per_run = steps * FRONTIER_CYCLES_PER_STEP + 3.0
    uart_wire_cycles_per_run = uart_wire_s * 100_000_000.0 / runs if runs > 0 else 0.0

    p_values = [float(row["p"]) for row in summary_rows]
    measured_cycles = [float(row.get("hw_latency_per_run_cycles", 0.0)) for row in summary_rows]
    core_est_cycles = [float(row.get("hw_core_latency_per_run_cycles_est", 0.0)) for row in summary_rows]
    measured_minus_ideal = [value - ideal_core_cycles_per_run for value in measured_cycles]
    residual_after_wire = [value - uart_wire_cycles_per_run for value in measured_minus_ideal]
    ideal_core_line = [ideal_core_cycles_per_run for _ in p_values]
    wire_line = [uart_wire_cycles_per_run for _ in p_values]

    fig, axes = plt.subplots(2, 1, figsize=(12, 9), sharex=True)

    axes[0].plot(p_values, measured_cycles, "o-", label="Measured latency per run")
    axes[0].plot(p_values, core_est_cycles, "s-", label="Benchmark core estimate")
    axes[0].plot(p_values, ideal_core_line, "--", color="black", label=f"Ideal core budget ~{ideal_core_cycles_per_run:.0f} cycles/run")
    axes[0].set_ylabel("Cycles per run")
    axes[0].set_title("Latency decomposition")
    axes[0].grid(True, alpha=0.3)
    axes[0].legend()

    axes[1].plot(p_values, measured_minus_ideal, "o-", label="Measured overhead beyond ideal core")
    axes[1].plot(p_values, wire_line, "s-", label="Theoretical UART wire time per run")
    axes[1].plot(p_values, residual_after_wire, "^-", label="Residual after subtracting wire time")
    axes[1].set_xlabel("Occupation probability p")
    axes[1].set_ylabel("Cycles per run")
    axes[1].grid(True, alpha=0.3)
    axes[1].legend()

    fig.suptitle("Latency decomposition")
    fig.tight_layout()

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)


# ---------------------------------------------------------------------------
# FPGA-engineering analysis plots (non-physics)
# ---------------------------------------------------------------------------


def plot_latency_vs_batch(conn, output: Path, *, hw_width: int = 128, target_p: float = 0.60) -> None:
    """Latency vs batch size, showing fixed UART overhead amortization."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    with plt.style.context(_PLOT_STYLE):
        sessions = _find_sessions_by_params(conn, hw_width=hw_width)
        if not sessions:
            print(f"  [latency_vs_batch] no sessions for hw_width={hw_width}")
            return

        by_steps: dict[int, list[dict]] = defaultdict(list)
        for s in sessions:
            by_steps[s["steps"]].append(s)
        for steps in by_steps:
            by_steps[steps].sort(key=lambda x: x["runs"])

        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))
        colors = plt.cm.Set1(np.linspace(0, 1, len(by_steps)))

        for idx, steps in enumerate(sorted(by_steps)):
            runs_list: list[float] = []
            lat_list: list[float] = []
            for s in by_steps[steps]:
                rows = _session_data(conn, s["session_id"])
                if not rows:
                    continue
                row = _closest_row(rows, target_p)
                runs_list.append(float(row["runs"]))
                lat_list.append(float(row["latency_s"]))

            if not runs_list:
                continue

            lat1 = lat_list[0]
            speedup = [lat1 / lat for lat in lat_list]
            label = f"S={steps}"

            ax1.plot(runs_list, lat_list, "o-", color=colors[idx], label=label)
            ax2.plot(runs_list, speedup, "o-", color=colors[idx], label=label)

            if len(runs_list) >= 2:
                r_big = runs_list[-1]
                s_big = speedup[-1]
                f_serial = (1 / s_big - 1 / r_big) / (1 - 1 / r_big) if r_big > 1 else 1.0
                ax2.annotate(
                    f"f_serial≈{f_serial:.2f}",
                    xy=(r_big, s_big),
                    xytext=(5, 5),
                    textcoords="offset points",
                    fontsize=8,
                    color=colors[idx],
                )

        ax1.set_xscale("log", base=2)
        ax1.set_yscale("log")
        ax1.set_xlabel("Batch size (cfg_runs)")
        ax1.set_ylabel("Total latency [s]")
        ax1.set_title("Latency vs Batch Size")
        ax1.legend(fontsize=8)

        ax2.set_xscale("log", base=2)
        ax2.set_xlabel("Batch size (cfg_runs)")
        ax2.set_ylabel("Speedup vs R=1")
        ax2.set_title("Amdahl Speedup — Fixed Overhead Amortization")
        ax2.axhline(1.0, color="gray", linewidth=0.5)
        ax2.legend(fontsize=8)

        fig.suptitle(f"N={hw_width}, p≈{target_p}", fontsize=12, y=1.02)
        fig.tight_layout()
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, bbox_inches="tight")
        plt.close(fig)


def plot_breakdown_fit(conn, output: Path, *, hw_width: int = 128, target_p: float = 0.60):
    """Asymptotic cycles-per-run fit separating fixed overhead from marginal cost."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    with plt.style.context(_PLOT_STYLE):
        sessions = _find_sessions_by_params(conn, hw_width=hw_width)
        if not sessions:
            return

        by_steps: dict[int, list[dict]] = defaultdict(list)
        for s in sessions:
            by_steps[s["steps"]].append(s)
        for steps in by_steps:
            by_steps[steps].sort(key=lambda x: x["runs"])

        fig, ax = plt.subplots(1, 1, figsize=(10, 6))
        colors = plt.cm.Set1(np.linspace(0, 1, len(by_steps)))

        results: list[dict] = []

        for idx, steps in enumerate(sorted(by_steps)):
            runs_list: list[float] = []
            core_cyc_list: list[float] = []
            tot_cyc_list: list[float] = []

            for s in by_steps[steps]:
                rows = _session_data(conn, s["session_id"])
                if not rows:
                    continue
                row = _closest_row(rows, target_p)
                r_val = float(row["runs"])
                runs_list.append(r_val)
                core_cyc_list.append(float(row.get("core_latency_per_run_cycles_est", 0)))
                tot_cyc_list.append(float(row.get("latency_per_run_cycles", 0)))

            if len(runs_list) < 3:
                continue

            n = len(runs_list)
            y = [tot_cyc_list[i] * runs_list[i] for i in range(n)]
            x = runs_list[:]
            x_mean = sum(x) / n
            y_mean = sum(y) / n
            sxx = sum((xi - x_mean) ** 2 for xi in x)
            sxy = sum((xi - x_mean) * (yi - y_mean) for xi, yi in zip(x, y))
            if sxx <= 0:
                continue
            slope = sxy / sxx
            intercept = y_mean - slope * x_mean

            C_marginal = slope
            C_fixed = intercept
            results.append({"steps": steps, "C_marginal": C_marginal, "C_fixed": C_fixed})

            ax.plot(
                runs_list, core_cyc_list, "o-",
                color=colors[idx], label=f"S={steps} measured", alpha=0.7,
            )
            fit_y = [C_fixed / r + C_marginal for r in runs_list]
            ax.plot(
                runs_list, fit_y, "--",
                color=colors[idx], alpha=0.5,
                label=f"S={steps} fit: asymptote={C_marginal:.0f} cyc/run",
            )

            ax.axhline(C_marginal, color=colors[idx], linestyle=":", alpha=0.3)

        ax.set_xscale("log", base=2)
        ax.set_yscale("log")
        ax.set_xlabel("Batch size (cfg_runs)")
        ax.set_ylabel("Core cycles per run (estimated)")
        ax.set_title("Asymptotic Cycles-per-Run Decomposition\n"
                     "T_total×R = C_fixed + C_marginal×R")
        ax.legend(fontsize=8, ncol=2)

        print(f"\n=== Asymptotic Fit Results (N={hw_width}, p≈{target_p}) ===")
        print(f"{'steps':>6}  {'C_marginal':>10}  {'C_fixed':>10}  {'ideal(S×3)':>12}  {'overhead':>9}  {'util':>6}")
        print("-" * 53)
        for r in sorted(results, key=lambda x: x["steps"]):
            s = r["steps"]
            frontier_ideal = s * FRONTIER_CYCLES_PER_STEP
            overhead = r["C_marginal"] - frontier_ideal
            util = frontier_ideal / r["C_marginal"] * 100 if r["C_marginal"] > 0 else 0
            print(
                f"{s:6d}  {r['C_marginal']:10.1f}  {r['C_fixed']:10.0f}  "
                f"{frontier_ideal:12.1f}  {overhead:9.1f}  {util:5.1f}%"
            )

        fig.tight_layout()
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, bbox_inches="tight")
        plt.close(fig)

    return results


def plot_breakdown_throughput(conn, output: Path, *, hw_width: int = 128, target_p: float = 0.60):
    """Side-by-side asymptotic decomposition: core cycles/run (left) and
    throughput in rows/s (right), both fitted to the Amdahl model

        T_total_cycles = C_fixed + C_marginal × R

    so that, as the batch size R→∞,
        core cycles/run → C_marginal
        throughput     → steps × f_clk / C_marginal
    """
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    F_CLK = 100_000_000.0

    with plt.style.context(_PLOT_STYLE):
        sessions = _find_sessions_by_params(conn, hw_width=hw_width)
        if not sessions:
            print(f"  [breakdown_throughput] no sessions for hw_width={hw_width}")
            return

        by_steps: dict[int, list[dict]] = defaultdict(list)
        for s in sessions:
            by_steps[s["steps"]].append(s)
        for steps in by_steps:
            by_steps[steps].sort(key=lambda x: x["runs"])

        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
        colors = plt.cm.Set1(np.linspace(0, 1, len(by_steps)))
        results: list[dict] = []

        for idx, steps in enumerate(sorted(by_steps)):
            runs_list: list[float] = []
            core_cyc_list: list[float] = []
            tot_cyc_list: list[float] = []
            rows_s_list: list[float] = []

            for s in by_steps[steps]:
                rows = _session_data(conn, s["session_id"])
                if not rows:
                    continue
                row = _closest_row(rows, target_p)
                r_val = float(row["runs"])
                runs_list.append(r_val)
                core_cyc_list.append(float(row.get("core_latency_per_run_cycles_est", 0)))
                tot_cyc_list.append(float(row.get("latency_per_run_cycles", 0)))
                cells_s = float(row.get("cells_per_s", 0))
                rows_s_list.append(cells_s / hw_width if hw_width > 0 else 0.0)

            if len(runs_list) < 3:
                continue

            n = len(runs_list)
            y = [tot_cyc_list[i] * runs_list[i] for i in range(n)]
            x = runs_list[:]
            x_mean = sum(x) / n
            y_mean = sum(y) / n
            sxx = sum((xi - x_mean) ** 2 for xi in x)
            sxy = sum((xi - x_mean) * (yi - y_mean) for xi, yi in zip(x, y))
            if sxx <= 0:
                continue
            slope = sxy / sxx
            intercept = y_mean - slope * x_mean

            C_marginal = slope
            C_fixed = intercept
            asymptote_rows_s = (steps * F_CLK / C_marginal) if C_marginal > 0 else float("inf")
            results.append(
                {
                    "steps": steps,
                    "C_marginal": C_marginal,
                    "C_fixed": C_fixed,
                    "asymptote_rows_s": asymptote_rows_s,
                }
            )

            # Left panel: core cycles per run (asymptotic decomposition).
            ax1.plot(runs_list, core_cyc_list, "o-",
                     color=colors[idx], label=f"S={steps} measured", alpha=0.7)
            fit_cyc = [C_fixed / r + C_marginal for r in runs_list]
            ax1.plot(runs_list, fit_cyc, "--",
                     color=colors[idx], alpha=0.5,
                     label=f"S={steps} fit: asymptote={C_marginal:.0f} cyc/run")
            ax1.axhline(C_marginal, color=colors[idx], linestyle=":", alpha=0.3)

            # Right panel: throughput in rows/s (Amdahl saturation).
            ax2.plot(runs_list, rows_s_list, "o-",
                     color=colors[idx], label=f"S={steps} measured", alpha=0.7)
            fit_rows = [r * steps * F_CLK / (C_fixed + C_marginal * r) for r in runs_list]
            ax2.plot(runs_list, fit_rows, "--",
                     color=colors[idx], alpha=0.5,
                     label=f"S={steps} fit: asymptote={asymptote_rows_s:.0f} rows/s")
            ax2.axhline(asymptote_rows_s, color=colors[idx], linestyle=":", alpha=0.3)

        ax1.set_xscale("log", base=2)
        ax1.set_yscale("log")
        ax1.set_xlabel("Batch size (cfg_runs)")
        ax1.set_ylabel("Core cycles per run (estimated)")
        ax1.set_title("Asymptotic Cycles-per-Run Decomposition\n"
                      "T_total×R = C_fixed + C_marginal×R")
        ax1.legend(fontsize=8, ncol=2)

        ax2.set_xscale("log", base=2)
        ax2.set_yscale("log")
        ax2.set_xlabel("Batch size (cfg_runs)")
        ax2.set_ylabel("Throughput [rows/s]")
        ax2.set_title("Asymptotic Throughput (Amdahl)\n"
                      "rows/s → steps×f_clk / C_marginal")
        ax2.legend(fontsize=8, ncol=2)

        print(f"\n=== Breakdown vs Throughput (N={hw_width}, p≈{target_p}) ===")
        print(f"{'steps':>6}  {'C_marginal':>10}  {'C_fixed':>10}  {'ideal(S×3)':>12}  "
              f"{'overhead':>9}  {'util':>6}  {'asympt rows/s':>14}")
        print("-" * 76)
        for r in sorted(results, key=lambda x: x["steps"]):
            s = r["steps"]
            frontier_ideal = s * FRONTIER_CYCLES_PER_STEP
            overhead = r["C_marginal"] - frontier_ideal
            util = frontier_ideal / r["C_marginal"] * 100 if r["C_marginal"] > 0 else 0
            print(
                f"{s:6d}  {r['C_marginal']:10.1f}  {r['C_fixed']:10.0f}  "
                f"{frontier_ideal:12.1f}  {overhead:9.1f}  {util:5.1f}%  "
                f"{r['asymptote_rows_s']:14.0f}"
            )

        fig.suptitle(f"N={hw_width}, p≈{target_p}", fontsize=12, y=1.02)
        fig.tight_layout()
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, bbox_inches="tight")
        plt.close(fig)

    return results


def plot_pipeline_efficiency(conn, output: Path, *, hw_width: int = 128, target_p: float = 0.60) -> None:
    """Frontier cost breakdown and pipeline utilization efficiency."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    with plt.style.context(_PLOT_STYLE):
        sessions = _find_sessions_by_params(conn, hw_width=hw_width)
        if not sessions:
            return

        max_runs = max(s["runs"] for s in sessions)
        best_sessions = [s for s in sessions if s["runs"] == max_runs and s["steps"] >= 1]
        if not best_sessions:
            return

        steps_vals: list[int] = []
        cyc_vals: list[float] = []
        for s in sorted(best_sessions, key=lambda x: x["steps"]):
            rows = _session_data(conn, s["session_id"])
            if not rows:
                continue
            row = _closest_row(rows, target_p)
            steps_vals.append(s["steps"])
            cyc_vals.append(float(row.get("core_latency_per_run_cycles_est", 0)))

        if len(steps_vals) < 2:
            return

        n = len(steps_vals)
        x = [float(s) for s in steps_vals]
        y = cyc_vals[:]
        coeffs = np.polyfit(x, y, 1)
        slope, intercept = coeffs[0], coeffs[1]

        ideal_per_step = FRONTIER_CYCLES_PER_STEP
        # Theoretical frontier cost: 4 cycles/row x S rows + 3 (start/done/accumulate).
        # The fitted `intercept` is NOT part of the frontier — it is residual
        # host/UART overhead that leaked into core_latency_per_run_cycles_est
        # (that metric only subtracts UART wire time, not Python/serial/USB
        # dispatch). So the ideal line uses the theoretical +3, and the fitted
        # intercept is reported separately as residual host overhead.
        ideal_intercept = 3.0
        ideal_line = [ideal_per_step * s + ideal_intercept for s in steps_vals]

        fig = plt.figure(figsize=(12, 5))
        gs = fig.add_gridspec(1, 2, width_ratios=[1, 1.1])

        ax1 = fig.add_subplot(gs[0])
        ax1.set_xscale("log", base=2)
        ax1.plot(steps_vals, cyc_vals, "o-", color="tab:blue", linewidth=2,
                 label=f"Measured (R={max_runs})")
        fit_x = np.linspace(min(x), max(x), 100)
        fit_y = coeffs[1] + coeffs[0] * fit_x
        ax1.plot(fit_x, fit_y, "--", color="tab:blue", alpha=0.6,
                 label=f"Fit: {slope:.2f}×S + {intercept:.0f}")
        ideal_y = ideal_per_step * fit_x + ideal_intercept
        ax1.plot(fit_x, ideal_y, ":", color="tab:green", linewidth=2,
                 label=f"Ideal: {ideal_per_step}×S + {ideal_intercept:.0f}")

        ax1.fill_between(fit_x, ideal_y, fit_y, alpha=0.1, color="tab:red",
                         label=f"Excess (slope={slope-ideal_per_step:.2f}/step)")
        ax1.set_xlabel("Grid height (steps)")
        ax1.set_ylabel("Core cycles per run")
        ax1.set_title(f"Frontier Cost (N={hw_width})")
        ax1.legend(fontsize=9)

        ax2 = fig.add_subplot(gs[1])
        efficiency = [ideal_line[i] / cyc_vals[i] * 100 for i in range(len(steps_vals))]
        excess = [cyc_vals[i] - ideal_line[i] for i in range(len(steps_vals))]

        # The steps span decades (64..2048), so a log x-axis keeps the small
        # points readable and lets the bars share the same scale without
        # overlapping. On a log axis the bar width is expressed in log2 units;
        # adjacent steps are 1.0 apart, so a width < 1 guarantees no collision.
        ax2.set_xscale("log", base=2)
        ax2.plot(steps_vals, efficiency, "s-", color="tab:green", linewidth=2,
                 label="Efficiency = ideal/measured")
        ax2.axhline(100, color="gray", linestyle=":", alpha=0.5)

        bar_width = 1  # log2 units; adjacent steps are 1.0 apart
        ax2_twin = ax2.twinx()
        ax2_twin.bar(steps_vals, excess, color="tab:red",
                     alpha=0.4, width=bar_width, label="Excess cycles")
        ax2_twin.set_ylabel("Excess cycles (measured − ideal)")
        ax2_twin.set_ylim(bottom=0)

        ax2.set_xlabel("Grid height (steps)")
        ax2.set_ylabel("Pipeline efficiency [%]")
        ax2.set_title(f"Pipeline Utilization (N={hw_width}, R={max_runs})")
        ax2.set_ylim(0, 110)
        ax2.legend(loc="upper left", fontsize=9)
        ax2_twin.legend(loc="upper right", fontsize=9)

        print(
            f"\n=== Pipeline Efficiency (N={hw_width}, R={max_runs}, p≈{target_p}) ===\n"
            f"  Fit: C_core/run = {slope:.3f} × steps + {intercept:.1f}\n"
            f"  Ideal frontier: {FRONTIER_CYCLES_PER_STEP} cyc/step + {ideal_intercept:.0f}\n"
            f"  Per-step cost:  {slope:.3f} cyc/step (vs ideal {FRONTIER_CYCLES_PER_STEP}, "
            f"excess {slope-FRONTIER_CYCLES_PER_STEP:.3f}/step)\n"
            f"  Residual host overhead (fitted intercept − ideal): {intercept-ideal_intercept:.1f} cyc/run\n"
        )
        for i, s in enumerate(steps_vals):
            print(f"    S={s:4d}: measured={cyc_vals[i]:.0f}  ideal={ideal_line[i]:.0f}  "
                  f"excess={excess[i]:.0f}  efficiency={efficiency[i]:.1f}%")

        fig.tight_layout()
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, bbox_inches="tight")
        plt.close(fig)


# ---------------------------------------------------------------------------
# Physics / DP analysis plots
# ---------------------------------------------------------------------------


def plot_spanning_curves_multi_size(
        conn, output: Path, *,
        hw_widths: tuple[int, ...] = (64, 128, 180),
) -> None:
    """Spanning probability curves for multiple square-grid sizes, with
    finite-size scaling collapse."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    with plt.style.context(_PLOT_STYLE):
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5.5))
        colors = plt.cm.Set1(np.linspace(0, 1, len(hw_widths)))
        markers = ["o", "s", "^", "D", "v"]

        NU_DP = 1.096

        data_by_n: dict[int, tuple[np.ndarray, np.ndarray]] = {}
        p_candidates: list[float] = []

        for idx, hw in enumerate(sorted(hw_widths)):
            sessions = _find_square_sessions(conn, hw_width=hw)
            if not sessions:
                print(f"  [multi-size] no square sessions for N={hw}")
                continue

            best = max(sessions, key=lambda s: s["total_runs"])
            rows = _session_data(conn, best["session_id"])
            if not rows:
                continue

            buckets: dict[float, dict[str, float]] = defaultdict(
                lambda: {"k": 0.0, "n": 0.0}
            )
            for r in rows:
                pv = float(r["p"])
                buckets[pv]["k"] += float(r.get("spanning_count", 0))
                buckets[pv]["n"] += float(r.get("runs", 1.0))

            probs = sorted(buckets)
            p_arr = np.array([float(p) for p in probs])
            span_arr = np.array(
                [
                    buckets[p]["k"] / buckets[p]["n"] if buckets[p]["n"] > 0 else 0.0
                    for p in probs
                ]
            )
            data_by_n[hw] = (p_arr, span_arr)

            p_half = None
            for i in range(len(probs) - 1):
                if (span_arr[i] - 0.5) * (span_arr[i + 1] - 0.5) <= 0:
                    dy = span_arr[i + 1] - span_arr[i]
                    if abs(dy) > 1e-12:
                        p_half = p_arr[i] + (0.5 - span_arr[i]) * (
                            p_arr[i + 1] - p_arr[i]
                        ) / dy
                    else:
                        p_half = p_arr[i]
                    break

            label = f"N={hw}×{hw}"
            if p_half is not None:
                p_candidates.append(p_half)
                label += f"  (p_c≈{p_half:.4f})"

            ax1.plot(
                p_arr,
                span_arr,
                marker=markers[idx % len(markers)],
                color=colors[idx],
                linewidth=2,
                label=label,
                markersize=5,
                alpha=0.85,
            )

        ax1.set_xlabel("Occupation probability p")
        ax1.set_ylabel("Spanning probability")
        ax1.set_title("Phase Transition Sharpening with System Size")
        ax1.set_ylim(-0.02, 1.02)
        ax1.legend(fontsize=9)

        p_c_est = (
            sorted(p_candidates)[-1] if len(p_candidates) > 1 else 0.6046
        )

        for idx, hw in enumerate(sorted(hw_widths)):
            if hw not in data_by_n:
                continue
            p_arr, span_arr = data_by_n[hw]
            scaled_x = (p_arr - p_c_est) * (hw ** (1.0 / NU_DP))
            ax2.plot(
                scaled_x,
                span_arr,
                marker=markers[idx % len(markers)],
                color=colors[idx],
                linewidth=2,
                label=f"N={hw}×{hw}",
                markersize=5,
                alpha=0.85,
            )

        ax2.axvline(0, color="gray", linestyle=":", alpha=0.4)
        ax2.set_xlabel(f"(p − p_c) × N^(1/{NU_DP:.3f})")
        ax2.set_ylabel("Spanning probability")
        ax2.set_title(f"Scaling Collapse  (p_c ≈ {p_c_est:.4f})")
        ax2.set_ylim(-0.02, 1.02)
        ax2.legend(fontsize=9)

        fig.suptitle(
            "Directed Percolation — Finite-Size Scaling  (square grids)",
            fontsize=13,
            y=1.02,
        )
        fig.tight_layout()
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, bbox_inches="tight")
        plt.close(fig)

        print(f"\n=== Finite-Size Scaling (square grids) ===")
        for hw in sorted(hw_widths):
            best = max(
                _find_square_sessions(conn, hw_width=hw) or [{"total_runs": 0}],
                key=lambda s: s["total_runs"],
            )
            print(
                f"  N={hw}×{hw}:  session={best.get('session_id', '?')[:8]}  "
                f"total_runs={best.get('total_runs', 0)}"
            )
        if p_candidates:
            print(f"  p_c estimates: {[f'{pc:.4f}' for pc in p_candidates]}")
            print(f"  Using p_c={p_c_est:.4f} for collapse")


def plot_threshold_bootstrap(
        conn, output: Path, *,
        session_id: str = "ba1fe7e8-e636-4fd5-af9e-78363786a637",
        n_bootstrap: int = 2000,
):
    """Precise threshold estimation via binomial logistic regression with
    binomial bootstrap confidence intervals."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    try:
        from scipy.optimize import minimize
    except ImportError:
        print("  [bootstrap] scipy required, skipping")
        return

    with plt.style.context(_PLOT_STYLE):
        rows = _session_data(conn, session_id)
        if not rows:
            print(f"  [bootstrap] no rows for session {session_id[:8]}...")
            return

        buckets: dict[float, dict[str, float]] = defaultdict(
            lambda: {"k": 0.0, "n": 0.0}
        )
        for r in rows:
            pv = float(r["p"])
            buckets[pv]["k"] += float(r.get("spanning_count", 0))
            buckets[pv]["n"] += float(r.get("runs", 1.0))

        probs = sorted(buckets)
        p_all = np.array([float(p) for p in probs])
        k_all = np.array([buckets[p]["k"] for p in probs], dtype=float)
        n_all = np.array([buckets[p]["n"] for p in probs], dtype=float)
        y_all = k_all / n_all

        mask = (y_all > 0.001) & (y_all < 0.999)
        p_arr = p_all[mask]
        k_arr = k_all[mask]
        n_arr = n_all[mask]
        y_arr = y_all[mask]

        if len(p_arr) < 5:
            print(f"  [bootstrap] too few transition points ({len(p_arr)}), skipping")
            return

        p_hat = k_arr / n_arr

        def _logistic_fit(xs, ks, ns):
            eps = 1e-12
            y_clipped = np.clip(ks / ns, eps, 1.0 - eps)
            logits = np.log(y_clipped / (1.0 - y_clipped))
            A = np.vstack([xs, np.ones_like(xs)]).T
            try:
                sol, *_ = np.linalg.lstsq(A, logits, rcond=None)
                a0, b0 = float(sol[0]), float(sol[1])
            except Exception:
                a0, b0 = 50.0, -30.0

            def nll(params):
                a, b = params[0], params[1]
                lin = a * xs + b
                phat = 1.0 / (1.0 + np.exp(-lin))
                phat = np.clip(phat, 1e-12, 1.0 - 1e-12)
                return -np.sum(ks * np.log(phat) + (ns - ks) * np.log(1.0 - phat))

            res = minimize(
                nll,
                x0=np.array([a0, b0], dtype=float),
                method="BFGS",
                options={"maxiter": 5000},
            )
            if res.success:
                return float(res.x[0]), float(res.x[1])
            return a0, b0

        a_fit, b_fit = _logistic_fit(p_arr, k_arr, n_arr)
        p_c_fit = -b_fit / a_fit
        slope_at_pc = a_fit / 4.0

        rng = np.random.default_rng(42)
        p_c_samples: list[float] = []
        a_samples: list[float] = []

        for _ in range(n_bootstrap):
            bs_k = rng.binomial(n_arr.astype(np.int64), p_hat).astype(float)
            try:
                a_bs, b_bs = _logistic_fit(p_arr, bs_k, n_arr)
                p_c_bs = -b_bs / a_bs
                if 0.55 < p_c_bs < 0.65:
                    p_c_samples.append(p_c_bs)
                    a_samples.append(a_bs)
            except Exception:
                continue

        pc_arr = np.array(p_c_samples)
        a_arr = np.array(a_samples)
        pc_mean = float(np.mean(pc_arr))
        pc_median = float(np.median(pc_arr))
        pc_lo, pc_hi = float(np.percentile(pc_arr, 2.5)), float(
            np.percentile(pc_arr, 97.5)
        )

        fig = plt.figure(figsize=(12, 5.5))
        gs = fig.add_gridspec(1, 2, width_ratios=[1.2, 1])

        ax1 = fig.add_subplot(gs[0])
        ax1.plot(
            p_arr,
            y_arr,
            "o",
            color="tab:blue",
            markersize=3,
            alpha=0.5,
            label=f"N=180×180 data  (transition only, {len(p_arr)} pts)",
        )
        fit_x = np.linspace(0.55, 0.65, 500)
        fit_y = 1.0 / (1.0 + np.exp(-(a_fit * fit_x + b_fit)))
        ax1.plot(fit_x, fit_y, "-", color="tab:red", linewidth=2, label="Logistic fit")

        if len(pc_arr) > 20:
            fit_ys = []
            for i in range(min(500, len(pc_arr))):
                sample_a = a_arr[i]
                sample_pc = pc_arr[i]
                sample_b = -sample_a * sample_pc
                fit_ys.append(1.0 / (1.0 + np.exp(-(sample_a * fit_x + sample_b))))
            fit_ys = np.array(fit_ys)
            ax1.fill_between(
                fit_x,
                np.percentile(fit_ys, 2.5, axis=0),
                np.percentile(fit_ys, 97.5, axis=0),
                color="tab:red",
                alpha=0.15,
                label="95% CI (binomial bootstrap)",
            )

        ax1.axvline(
            pc_mean,
            color="tab:red",
            linestyle="--",
            linewidth=1.5,
            label=f"p_c = {pc_mean:.4f}\n[{pc_lo:.4f}, {pc_hi:.4f}]",
        )
        ax1.set_xlabel("Occupation probability p")
        ax1.set_ylabel("Spanning probability")
        ax1.set_title("Threshold via Binomial Logistic Regression\n"
                       f"slope at p_c ≈ {slope_at_pc:.1f}")
        ax1.set_ylim(-0.02, 1.02)
        ax1.legend(fontsize=8)

        ax2 = fig.add_subplot(gs[1])
        ax2.hist(
            pc_arr,
            bins=50,
            color="tab:blue",
            alpha=0.7,
            edgecolor="white",
            linewidth=0.5,
        )
        ax2.axvline(
            pc_mean, color="tab:red", linewidth=2, label=f"mean={pc_mean:.4f}"
        )
        ax2.axvline(pc_lo, color="gray", linestyle="--", label=f"2.5%={pc_lo:.4f}")
        ax2.axvline(pc_hi, color="gray", linestyle="--", label=f"97.5%={pc_hi:.4f}")
        ax2.set_xlabel("p_c = −b/a")
        ax2.set_ylabel("Count (bootstrap)")
        ax2.set_title(f"Binomial Bootstrap (n={len(pc_arr)})")
        ax2.legend(fontsize=8)

        fig.suptitle(
            "Directed Percolation Threshold Estimation  (180×180, 131k runs/pt)",
            fontsize=13,
            y=1.02,
        )
        fig.tight_layout()
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, bbox_inches="tight")
        plt.close(fig)

        print(f"\n=== Threshold Estimation (N=180, {n_bootstrap} binomial bootstrap) ===")
        print(f"  Fit range: {p_arr[0]:.4f} – {p_arr[-1]:.4f}  ({len(p_arr)} points)")
        print(f"  Logistic: a={a_fit:.1f}, b={b_fit:.1f}")
        print(f"  p_c = −b/a = {p_c_fit:.6f}")
        print(f"  Slope at p_c = a/4 = {slope_at_pc:.1f}")
        print(f"  Bootstrap: median={pc_median:.6f}, mean={pc_mean:.6f}")
        print(f"  95% CI: [{pc_lo:.6f}, {pc_hi:.6f}]")
        print(f"  CI width: {pc_hi - pc_lo:.6f}")

    return p_c_fit, (pc_lo, pc_hi)


def plot_cluster_mass_curves(
        conn, output: Path, *,
        hw_widths: tuple[int, ...] = (64, 128, 180),
) -> None:
    """Average spanning-cluster mass vs p for multiple square-grid sizes."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    with plt.style.context(_PLOT_STYLE):
        fig, ax = plt.subplots(1, 1, figsize=(10, 6))
        colors = plt.cm.Set1(np.linspace(0, 1, len(hw_widths)))
        markers = ["o", "s", "^", "D", "v"]

        for idx, hw in enumerate(sorted(hw_widths)):
            sessions = _find_square_sessions(conn, hw_width=hw)
            if not sessions:
                continue
            best = max(sessions, key=lambda s: s["total_runs"])
            rows = _session_data(conn, best["session_id"])
            if not rows:
                continue

            buckets: dict[float, list[float]] = defaultdict(list)
            for r in rows:
                pv = float(r["p"])
                k = float(r.get("spanning_count", 0))
                mass_val = float(r.get("mass", 0.0))
                if k > 0 and mass_val > 0:
                    buckets[pv].append(mass_val)

            probs = sorted(buckets)
            p_vals = []
            m_vals = []
            for pv in probs:
                masses = buckets[pv]
                m_mean = np.mean(masses)
                p_vals.append(pv)
                m_vals.append(m_mean)

            if not p_vals:
                continue

            ax.semilogy(
                p_vals,
                m_vals,
                marker=markers[idx % len(markers)],
                color=colors[idx],
                linewidth=2,
                label=f"N={hw}×{hw}",
                markersize=5,
                alpha=0.85,
            )

        ax.set_xlabel("Occupation probability p")
        ax.set_ylabel("Mean spanning-cluster mass [sites]")
        ax.set_title("Spanning Cluster Mass vs Occupation Probability")
        ax.legend(fontsize=9)
        fig.tight_layout()
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, bbox_inches="tight")
        plt.close(fig)


def plot_binder_cumulant(
        conn, output: Path, *,
        hw_widths: tuple[int, ...] = (64, 128, 180),
) -> None:
    """Binder cumulant U(p, N) = 1 − ⟨k²⟩/(3⟨k⟩²) for multiple square-grid sizes."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    with plt.style.context(_PLOT_STYLE):
        fig, ax = plt.subplots(1, 1, figsize=(10, 6))
        colors = plt.cm.Set1(np.linspace(0, 1, len(hw_widths)))
        markers = ["o", "s", "^", "D", "v"]

        crossings: list[tuple[int, float]] = []

        for idx, hw in enumerate(sorted(hw_widths)):
            sessions = _find_square_sessions(conn, hw_width=hw)
            if not sessions:
                continue
            best = max(sessions, key=lambda s: s["total_runs"])
            rows = _session_data(conn, best["session_id"])
            if not rows:
                continue

            buckets: dict[float, dict[str, float]] = defaultdict(
                lambda: {"k": 0.0, "n": 0.0}
            )
            for r in rows:
                pv = float(r["p"])
                buckets[pv]["k"] += float(r.get("spanning_count", 0))
                buckets[pv]["n"] += float(r.get("runs", 1.0))

            probs = sorted(buckets)
            p_vals = []
            u_vals = []
            for pv in probs:
                k = buckets[pv]["k"]
                n_total = buckets[pv]["n"]
                if k <= 0 or n_total <= 0:
                    continue
                p_hat = k / n_total
                k2_exp = k * k + k * (1.0 - p_hat)
                U = 1.0 - (k2_exp / (3.0 * k * k))
                p_vals.append(pv)
                u_vals.append(U)

            if not p_vals:
                continue

            ax.plot(
                p_vals,
                u_vals,
                marker=markers[idx % len(markers)],
                color=colors[idx],
                linewidth=2,
                label=f"N={hw}×{hw}",
                markersize=5,
                alpha=0.85,
            )

            for i in range(len(u_vals) - 1):
                if (u_vals[i] - 2.0 / 3.0) * (u_vals[i + 1] - 2.0 / 3.0) <= 0:
                    dy = u_vals[i + 1] - u_vals[i]
                    p_cross = (
                        p_vals[i]
                        + (2.0 / 3.0 - u_vals[i]) * (p_vals[i + 1] - p_vals[i]) / dy
                        if abs(dy) > 1e-12
                        else p_vals[i]
                    )
                    crossings.append((hw, p_cross))
                    break

        ax.axhline(
            2.0 / 3.0,
            color="gray",
            linestyle=":",
            alpha=0.4,
            label="U = 2/3 (crossing)",
        )

        if crossings:
            crossing_x = [c[1] for c in crossings]
            crossing_y = [2.0 / 3.0] * len(crossings)
            ax.scatter(
                crossing_x,
                crossing_y,
                marker="*",
                s=160,
                color="black",
                zorder=5,
                label="Crossings",
            )
            for c in crossings:
                print(f"  N={c[0]:3d}×{c[0]:3d}:  Binder crossing at p={c[1]:.4f}")

        ax.set_xlabel("Occupation probability p")
        ax.set_ylabel("Binder cumulant U = 1 − ⟨k²⟩/(3⟨k⟩²)")
        ax.set_title("Binder Cumulant — Crossing Point Estimate of p_c")
        ax.legend(fontsize=9)

        fig.tight_layout()
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, bbox_inches="tight")
        plt.close(fig)


def plot_throughput_invariance(conn, output: Path, *, hw_width: int = 128, target_p: float = 0.60) -> None:
    """Grid-height invariance: throughput vs steps for multiple batch sizes,
    with an Amdahl-style asymptotic fit per (steps) curve.

    For each (steps) curve the fixed + marginal cost model
        T_total_cycles = C_fixed + C_marginal × R
    is fitted and used to draw the asymptotic throughput
        rows/s → steps × f_clk / C_marginal   as R→∞.
    """
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    F_CLK = 100_000_000.0

    sessions = _find_sessions_by_params(conn, hw_width=hw_width)
    if not sessions:
        return

    by_runs: dict[int, list[dict]] = defaultdict(list)
    for s in sessions:
        by_runs[s["runs"]].append(s)
    for runs in by_runs:
        by_runs[runs].sort(key=lambda x: x["steps"])

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

    colors = ["tab:blue", "tab:orange", "tab:green", "tab:red", "tab:purple", "tab:brown", "tab:pink", "tab:gray"]

    for idx, runs in enumerate(sorted(by_runs)):
        color = colors[idx % len(colors)]
        steps_list: list[int] = []
        cells_list: list[float] = []
        core_cyc_list: list[float] = []
        for s in by_runs[runs]:
            rows = _session_data(conn, s["session_id"])
            if not rows:
                continue
            row = _closest_row(rows, target_p)
            steps_list.append(s["steps"])
            cells_list.append(float(row.get("cells_per_s", 0)))
            core_cyc_list.append(float(row.get("core_latency_per_run_cycles_est", 0)))

        if not steps_list:
            continue

        ax1.plot(steps_list, cells_list, "o-", color=color, label=f"runs={runs}")

        # Fit C_core = a×S + b per batch size, then map to asymptotic rows/s
        # throughput: rows/s = S×f_clk / (a×S + b) → f_clk/a as S→∞.
        if len(steps_list) >= 2:
            xs = np.array([float(s) for s in steps_list])
            ys = np.array(core_cyc_list)
            if len(ys) == len(xs):
                coeffs = np.polyfit(xs, ys, 1)
                a_slope, b_int = coeffs[0], coeffs[1]
                if a_slope > 0:
                    asympt_rows_s = F_CLK / a_slope
                    fit_rows = [s * F_CLK / (a_slope * s + b_int) for s in steps_list]
                    ax2.plot(steps_list, fit_rows, "--", color=color, alpha=0.6,
                             label=f"runs={runs} fit: asymptote≈{asympt_rows_s:.0f} rows/s")
                    ax2.axhline(asympt_rows_s, color=color, linestyle=":", alpha=0.3)

    ax1.set_xscale("log", base=2)
    ax1.set_yscale("log")
    ax1.set_xlabel("Grid height (steps)")
    ax1.set_ylabel("Throughput [cells/s]")
    ax1.set_title(f"Grid-Height Invariance (N={hw_width}, p≈{target_p})")
    ax1.grid(True, alpha=0.3)
    ax1.legend(fontsize=8)

    ax2.set_xscale("log", base=2)
    ax2.set_yscale("log")
    ax2.set_xlabel("Grid height (steps)")
    ax2.set_ylabel("Asymptotic throughput [rows/s]")
    ax2.set_title(f"Throughput Asymptotic (N={hw_width}, p≈{target_p})\n"
                  "rows/s → f_clk / (∂C_core/∂S)")
    ax2.grid(True, alpha=0.3)
    ax2.legend(fontsize=8)

    fig.suptitle(f"Grid-Height Invariance — cells/s vs asymptotic rows/s", fontsize=12, y=1.02)
    fig.tight_layout()
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)
    plt.close(fig)


def plot_determinism_cv(conn, output: Path, *, hw_width: int = 128, target_p: float = 0.60) -> None:
    """Coefficient of variation across repeats to quantify determinism."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    sessions = _find_sessions_by_params(conn, hw_width=hw_width)
    if not sessions:
        return

    multi_repeat = [s for s in sessions if s["repeats"] > 1]

    if not multi_repeat:
        fig, ax = plt.subplots(1, 1, figsize=(10, 5))
        ax.text(0.5, 0.5, f"No multi-repeat data available for hw_width={hw_width}", ha="center", va="center", transform=ax.transAxes)
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, dpi=150)
        plt.close(fig)
        return

    fig, ax = plt.subplots(1, 1, figsize=(10, 5))

    config_cv: dict[tuple[int, int], list[float]] = defaultdict(list)

    for s in multi_repeat:
        rows = _session_data(conn, s["session_id"])
        if not rows:
            continue
        by_p: dict[float, list[float]] = defaultdict(list)
        for r in rows:
            by_p[float(r["p"])].append(float(r["latency_s"]))
        for p_val, lats in by_p.items():
            if abs(p_val - target_p) > 0.01 and target_p != 0.60:
                continue
            if len(lats) < 2:
                continue
            mean = sum(lats) / len(lats)
            var = sum((v - mean) ** 2 for v in lats) / (len(lats) - 1)
            cv = math.sqrt(var) / mean if mean > 0 else 0
            config_cv[(s["steps"], s["runs"])].append(cv)

    configs = sorted(config_cv)
    steps_display = [c[0] for c in configs]
    runs_display = [c[1] for c in configs]
    cv_means = [sum(config_cv[c]) / len(config_cv[c]) * 100 for c in configs]

    scatter = ax.scatter(
        runs_display,
        steps_display,
        c=cv_means,
        s=80,
        cmap="RdYlGn_r",
        vmin=0,
        vmax=max(cv_means) if cv_means else 5,
        edgecolors="black",
        linewidths=0.5,
    )
    cbar = fig.colorbar(scatter, ax=ax, label="CV [%]")
    ax.set_xscale("log", base=2)
    ax.set_xlabel("cfg_runs")
    ax.set_ylabel("Grid height (steps)")
    ax.set_title(f"Latency Coefficient of Variation (N={hw_width})\n(lower = more deterministic)")
    ax.grid(True, alpha=0.3)

    fig.tight_layout()
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)
    plt.close(fig)

    print(f"\n=== Determinism CV (N={hw_width}) ===")
    for i, c in enumerate(configs):
        print(f"  steps={c[0]:4d} runs={c[1]:6d}  CV={cv_means[i]:.2f}%")


def plot_throughput_contour(conn, output: Path, *, hw_width: int = 128) -> None:
    """2D heatmap of throughput across p × steps for large batch size."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    sessions = _find_sessions_by_params(conn, hw_width=hw_width)
    if not sessions:
        return

    max_runs = max(s["runs"] for s in sessions)
    best_sessions = [s for s in sessions if s["runs"] == max_runs]

    all_steps = sorted({s["steps"] for s in best_sessions})
    all_p: set[float] = set()

    for s in best_sessions:
        rows = _session_data(conn, s["session_id"])
        for r in rows:
            all_p.add(float(r["p"]))

    sorted_p = sorted(all_p)
    if not all_steps or not sorted_p:
        return

    Z = np.full((len(all_steps), len(sorted_p)), np.nan)
    for si, steps in enumerate(all_steps):
        matches = [s for s in best_sessions if s["steps"] == steps]
        if not matches:
            continue
        rows = _session_data(conn, matches[0]["session_id"])
        p_to_cells: dict[float, float] = {}
        for r in rows:
            p_val = float(r["p"])
            p_to_cells[p_val] = float(r.get("cells_per_s", 0))
        for pi, p_val in enumerate(sorted_p):
            if p_val in p_to_cells:
                Z[si, pi] = p_to_cells[p_val]

    fig, ax = plt.subplots(1, 1, figsize=(12, 6))

    mask = np.isnan(Z)
    Z_masked = np.ma.masked_where(mask, Z)

    if np.any(~mask):
        levels = 20
        contour = ax.contourf(
            sorted_p,
            all_steps,
            np.log10(Z_masked),
            levels=levels,
            cmap="viridis",
        )
        cbar = fig.colorbar(contour, ax=ax, label="log₁₀(cells/s)")
    else:
        ax.text(0.5, 0.5, "No valid data for contour", ha="center", va="center", transform=ax.transAxes)

    ax.set_xlabel("Occupation probability p")
    ax.set_ylabel("Grid height (steps)")
    ax.set_title(f"Throughput Contour (N={hw_width}, runs={max_runs})")
    ax.grid(True, alpha=0.2)

    fig.tight_layout()
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)
    plt.close(fig)


def plot_fpga_all(output_dir: Path, *,
                  db2_path: Path = DEFAULT_DB2,
                  hw_width: int = 128,
                  target_p: float = 0.60) -> None:
    """Convenience: run all plots and save to output_dir."""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    conn2 = _connect(db2_path)
    try:
        print(f"\n{'='*60}")
        print(f"FPGA Engineering Analysis (N={hw_width}, p≈{target_p})")
        print(f"{'='*60}")

        print("\n[1/6] Latency vs Batch (Amdahl Speedup)...")
        plot_latency_vs_batch(conn2, output_dir / "latency_vs_batch.png",
                              hw_width=hw_width, target_p=target_p)

        print("\n[2/6] Asymptotic Breakdown Fit...")
        plot_breakdown_fit(conn2, output_dir / "breakdown_fit.png",
                           hw_width=hw_width, target_p=target_p)

        print("\n[3/6] Pipeline Efficiency...")
        plot_pipeline_efficiency(conn2, output_dir / "pipeline_efficiency.png",
                                 hw_width=hw_width, target_p=target_p)

        print("\n[4/6] Throughput Invariance...")
        plot_throughput_invariance(conn2, output_dir / "throughput_invariance.png",
                                   hw_width=hw_width, target_p=target_p)

        print("\n[5/6] Throughput Contour...")
        plot_throughput_contour(conn2, output_dir / "throughput_contour.png",
                                hw_width=hw_width)

        print("\n[6/6] Determinism CV (N=128)...")
        plot_determinism_cv(conn2, output_dir / "determinism_cv.png",
                            hw_width=128, target_p=target_p)

        print("\n[extra] Determinism CV (N=180)...")
        plot_determinism_cv(conn2, output_dir / "determinism_cv_180.png",
                            hw_width=180, target_p=target_p)

        # Physics plots
        print("\n[physics 1/3] Finite-Size Scaling...")
        plot_spanning_curves_multi_size(conn2, output_dir / "finite_size_scaling.png")

        print("\n[physics 2/3] Threshold Bootstrap...")
        plot_threshold_bootstrap(conn2, output_dir / "threshold_bootstrap.png")

        print("\n[physics 3/3] Cluster Mass Curves...")
        plot_cluster_mass_curves(conn2, output_dir / "cluster_mass_curves.png")
    finally:
        conn2.close()

    print(f"\nAll plots saved to {output_dir}")
