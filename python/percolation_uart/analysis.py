"""SQLite analysis helpers for percolation benchmark history.

This module keeps the analysis layer intentionally small: load benchmark rows,
summarize sessions, and provide a basic throughput plot that can be extended
later once the desired figures are clearer.
"""

from __future__ import annotations

import argparse
import json
import math
import sqlite3
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


DEFAULT_DB = Path(__file__).resolve().parents[1] / "output" / "benchmark.sqlite3"


@dataclass(frozen=True)
class BenchmarkSession:
    session_id: str
    created_at: str
    payload: dict[str, object]


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def list_sessions(conn: sqlite3.Connection) -> list[BenchmarkSession]:
    rows = conn.execute(
        "SELECT session_id, created_at, payload_json FROM benchmark_sessions ORDER BY created_at"
    ).fetchall()
    sessions: list[BenchmarkSession] = []
    for row in rows:
        sessions.append(
            BenchmarkSession(
                session_id=str(row["session_id"]),
                created_at=str(row["created_at"]),
                payload=json.loads(row["payload_json"]),
            )
        )
    return sessions


def latest_session_id(conn: sqlite3.Connection) -> str | None:
    row = conn.execute(
        "SELECT session_id FROM benchmark_sessions ORDER BY created_at DESC LIMIT 1"
    ).fetchone()
    return None if row is None else str(row["session_id"])


def load_summary_rows(conn: sqlite3.Connection, session_id: str | None = None) -> list[dict[str, object]]:
    if session_id is None:
        rows = conn.execute("SELECT row_json FROM benchmark_summary ORDER BY p").fetchall()
    else:
        rows = conn.execute(
            "SELECT row_json FROM benchmark_summary WHERE session_id = ? ORDER BY p",
            (session_id,),
        ).fetchall()
    return [json.loads(row["row_json"]) for row in rows]


def load_raw_rows(conn: sqlite3.Connection, session_id: str | None = None) -> list[dict[str, object]]:
    if session_id is None:
        rows = conn.execute("SELECT row_json FROM benchmark_raw ORDER BY p, repeat_index").fetchall()
    else:
        rows = conn.execute(
            "SELECT row_json FROM benchmark_raw WHERE session_id = ? ORDER BY p, repeat_index",
            (session_id,),
        ).fetchall()
    return [json.loads(row["row_json"]) for row in rows]


def summarize_db(conn: sqlite3.Connection) -> str:
    session_count = conn.execute("SELECT COUNT(*) AS n FROM benchmark_sessions").fetchone()["n"]
    summary_count = conn.execute("SELECT COUNT(*) AS n FROM benchmark_summary").fetchone()["n"]
    raw_count = conn.execute("SELECT COUNT(*) AS n FROM benchmark_raw").fetchone()["n"]

    if summary_count == 0:
        return f"sessions={session_count}, summary_rows=0, raw_rows={raw_count}"

    p_min, p_max = conn.execute(
        "SELECT MIN(p) AS p_min, MAX(p) AS p_max FROM benchmark_summary"
    ).fetchone()
    return (
        f"sessions={session_count}, summary_rows={summary_count}, raw_rows={raw_count}, "
        f"p_range=[{p_min:.4f}, {p_max:.4f}]"
    )


def _mean_std_err(values: list[float]) -> tuple[float, float, float]:
    if not values:
        return 0.0, 0.0, 0.0
    n = len(values)
    mean = sum(values) / n
    if n < 2:
        return mean, 0.0, 0.0
    variance = sum((value - mean) ** 2 for value in values) / (n - 1)
    std = math.sqrt(variance)
    err = std / math.sqrt(n)
    return mean, std, err


def _group_by_p(rows: list[dict[str, object]], value_key: str) -> tuple[list[float], list[float], list[float], list[float]]:
    buckets: dict[float, list[float]] = defaultdict(list)
    for row in rows:
        if value_key not in row:
            continue
        buckets[float(row["p"])].append(float(row[value_key]))

    probabilities = sorted(buckets)
    means: list[float] = []
    stds: list[float] = []
    errs: list[float] = []
    for probability in probabilities:
        mean, std, err = _mean_std_err(buckets[probability])
        means.append(mean)
        stds.append(std)
        errs.append(err)
    return probabilities, means, stds, errs


def _linear_regression_3sigma(x: list[float], y: list[float], n_points: int = 300) -> tuple[list[float], list[float], list[float], list[float]]:
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
        se_mean = sigma * math.sqrt((1.0 / n) + ((xi - x_mean) ** 2 / sxx))
        delta = 3.0 * se_mean
        fit.append(y_fit)
        upper.append(y_fit + delta)
        lower.append(y_fit - delta)

    return xs, fit, upper, lower


def _sigmoid_regression_3sigma(x: list[float], y: list[float], n_points: int = 300) -> tuple[list[float], list[float], list[float], list[float]]:
    if not x or not y or len(x) != len(y):
        return [], [], [], []
    if len(x) < 2:
        return x[:], y[:], y[:], y[:]

    eps = 1e-6
    clipped = [min(max(value, eps), 1.0 - eps) for value in y]
    logits = [math.log(value / (1.0 - value)) for value in clipped]
    fit_x, fit_logit, fit_hi_logit, fit_lo_logit = _linear_regression_3sigma(x, logits, n_points=n_points)
    if not fit_x:
        return [], [], [], []

    def sigmoid(value: float) -> float:
        if value >= 0:
            z = math.exp(-value)
            return 1.0 / (1.0 + z)
        z = math.exp(value)
        return z / (1.0 + z)

    fit = [sigmoid(value) for value in fit_logit]
    upper = [sigmoid(value) for value in fit_hi_logit]
    lower = [sigmoid(value) for value in fit_lo_logit]
    return fit_x, fit, upper, lower


def _plot_with_error_bars(
    ax,
    x: list[float],
    y: list[float],
    yerr: list[float],
    *,
    marker: str,
    color: str,
    label: str,
    fit_label: str,
    shade_label: str,
) -> None:
    ax.errorbar(
        x,
        y,
        yerr=yerr,
        fmt=marker,
        linestyle="none",
        capsize=3,
        markersize=5,
        label=label,
        color=color,
        alpha=0.95,
    )
    fit_x, fit_y, fit_hi, fit_lo = _linear_regression_3sigma(x, y)
    if fit_x:
        ax.plot(fit_x, fit_y, "-", linewidth=2, alpha=0.9, color=color, label=fit_label)
        ax.fill_between(fit_x, fit_lo, fit_hi, color=color, alpha=0.15, label=shade_label)


def _plot_with_sigmoid_fit(
    ax,
    x: list[float],
    y: list[float],
    yerr: list[float],
    *,
    marker: str,
    color: str,
    label: str,
    fit_label: str,
    shade_label: str,
) -> None:
    ax.errorbar(
        x,
        y,
        yerr=yerr,
        fmt=marker,
        linestyle="none",
        capsize=3,
        markersize=5,
        label=label,
        color=color,
        alpha=0.95,
    )
    fit_x, fit_y, fit_hi, fit_lo = _sigmoid_regression_3sigma(x, y)
    if fit_x:
        ax.plot(fit_x, fit_y, "-", linewidth=2, alpha=0.9, color=color, label=fit_label)
        ax.fill_between(fit_x, fit_lo, fit_hi, color=color, alpha=0.15, label=shade_label)


def _derived_front_density_rows(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    derived_rows: list[dict[str, object]] = []
    for row in rows:
        p_value = row.get("p")
        if p_value is None:
            continue
        if "reachable_fraction" in row:
            front_density = float(row["reachable_fraction"])
        elif "reachable_sites_per_run" in row and "steps" in row and "width" in row:
            area = float(row["steps"]) * float(row["width"])
            front_density = float(row["reachable_sites_per_run"]) / area if area > 0 else 0.0
        elif "mass" in row and "spanning_rate" in row and "steps" in row and "width" in row:
            area = float(row["steps"]) * float(row["width"])
            front_density = float(row["mass"]) * float(row["spanning_rate"]) / area if area > 0 else 0.0
        else:
            continue
        derived_rows.append({"p": float(p_value), "front_density": front_density})
    return derived_rows


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

    span_p, span_mean, span_std, _ = _group_by_p(raw_rows, "spanning_rate")
    if span_p:
        _plot_with_sigmoid_fit(
            axes[1, 1],
            span_p,
            span_mean,
            span_std,
            marker="^",
            color="tab:red",
            label="Spanning probability (mean ± std)",
            fit_label="Sigmoid fit",
            shade_label="Sigmoid fit ± 3σ",
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
        _plot_with_sigmoid_fit(
            ax,
            p_values,
            density_values,
            density_std,
            marker="D",
            color="green",
            label="Reachable density (mean ± std)",
            fit_label="Density sigmoid fit",
            shade_label="Density sigmoid fit ± 3σ",
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

    p_values, mass_values, mass_std, mass_err = _group_by_p(rows, "mass")

    fig, ax = plt.subplots(1, 1, figsize=(10, 5))
    if p_values:
        ax.errorbar(
            p_values,
            mass_values,
            yerr=mass_std,
            fmt="v",
            linestyle="none",
            capsize=3,
            markersize=5,
            color="purple",
            label="Mass per spanning run (mean ± std)",
        )
        fit_x, fit_y, fit_hi, fit_lo = _linear_regression_3sigma(p_values, mass_values)
        if fit_x:
            ax.plot(fit_x, fit_y, "-", linewidth=2, alpha=0.9, color="purple", label="Mass linear fit")
            ax.fill_between(fit_x, fit_lo, fit_hi, color="purple", alpha=0.15, label="Mass fit ± 3σ")

    ax.set_xlabel("Occupation probability p")
    ax.set_ylabel("Average reachable sites")
    ax.set_title("Spanning Cluster Mass")
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

    p_values, span_values, span_std, span_err = _group_by_p(rows, "spanning_rate")

    fig, ax = plt.subplots(1, 1, figsize=(10, 5))
    if p_values:
        _plot_with_sigmoid_fit(
            ax,
            p_values,
            span_values,
            span_std,
            marker="^",
            color="tab:red",
            label="Spanning probability (mean ± std)",
            fit_label="Sigmoid fit",
            shade_label="Sigmoid fit ± 3σ",
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect percolation benchmark SQLite history")
    parser.add_argument("--db", type=str, default=str(DEFAULT_DB))
    parser.add_argument("--latest", action="store_true", help="Only inspect latest session")
    parser.add_argument("--plot", type=str, default="", help="Optional throughput plot output path")
    parser.add_argument("--plot-dir", type=str, default="", help="Optional output directory for starter plots")
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.exists():
        raise SystemExit(f"database not found: {db_path}")

    conn = _connect(db_path)
    try:
        print(summarize_db(conn))
        sessions = list_sessions(conn)
        if sessions:
            latest = sessions[-1]
            print(f"latest_session={latest.session_id}")
            print(f"latest_created_at={latest.created_at}")
            if "config_hash" in latest.payload:
                print(f"latest_config_hash={latest.payload['config_hash']}")

        session_id = latest_session_id(conn) if args.latest else None
        rows = load_summary_rows(conn, session_id=session_id)
        raw_rows = load_raw_rows(conn, session_id=session_id)
        print(f"loaded_summary_rows={len(rows)}")
        print(f"loaded_raw_rows={len(raw_rows)}")
        if rows:
            print(f"p_min={min(float(row['p']) for row in rows):.6f}")
            print(f"p_max={max(float(row['p']) for row in rows):.6f}")

        if args.plot:
            plot_dashboard(rows, raw_rows, Path(args.plot))
            print(f"plot_saved={args.plot}")
        if args.plot_dir:
            plot_dir = Path(args.plot_dir)
            plot_dashboard(rows, raw_rows, plot_dir / "dashboard.png")
            plot_front_density(raw_rows, plot_dir / "front_density.png")
            plot_cluster_mass(raw_rows, plot_dir / "cluster_mass.png")
            plot_occupancy_bias(raw_rows, plot_dir / "occupancy_bias.png")
            plot_core_latency(raw_rows, plot_dir / "core_latency.png")
            plot_spanning_probability(raw_rows, plot_dir / "spanning_probability.png")
            print(f"plot_dir_saved={plot_dir}")
    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())