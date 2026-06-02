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

from .protocol import REQUEST_BYTES, RESPONSE_BYTES


# FPGA timing constants (from VHDL analysis)
RNG_WARMUP_CYCLES = 1573        # AES seeding (1536) + Trivium warmup (37) @ 100 MHz
RNG_WARMUP_S = RNG_WARMUP_CYCLES / 100e6
FRONTIER_CYCLES_PER_STEP = 3    # 3-stage pipelined prefix scan
PER_RUN_SM_OVERHEAD_CYCLES = 115  # per-run state machine cost (asymptotic fit)
UART_WIRE_S_CALC = (REQUEST_BYTES + RESPONSE_BYTES) * 10.0 / 115200.0  # ≈ 2.78 ms

DEFAULT_DB = Path(__file__).resolve().parents[1] / "output" / "benchmark.sqlite3"
DEFAULT_DB2 = Path(__file__).resolve().parents[1] / "output" / "benchmark-2.sqlite3"


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


def _aggregate_mass_by_p(rows: list[dict[str, object]], min_spanning_count: int = 10) -> tuple[list[float], list[float], list[float], list[float]]:
    buckets: dict[float, dict[str, float]] = defaultdict(lambda: {"spanning_occupied": 0.0, "spanning_count": 0.0})
    for row in rows:
        if "p" not in row:
            continue
        p_value = float(row["p"])
        buckets[p_value]["spanning_occupied"] += float(row.get("spanning_occupied", 0.0))
        buckets[p_value]["spanning_count"] += float(row.get("spanning_count", 0.0))

    probabilities = sorted(buckets)
    pooled_mass: list[float] = []
    pooled_spanning_count: list[float] = []
    low_stat_flags: list[float] = []
    for probability in probabilities:
        total_spanning_occupied = buckets[probability]["spanning_occupied"]
        total_spanning_count = buckets[probability]["spanning_count"]
        mass = total_spanning_occupied / total_spanning_count if total_spanning_count > 0 else 0.0
        pooled_mass.append(mass)
        pooled_spanning_count.append(total_spanning_count)
        low_stat_flags.append(1.0 if total_spanning_count < min_spanning_count else 0.0)
    return probabilities, pooled_mass, pooled_spanning_count, low_stat_flags


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


def _sigmoid_regression_nonlinear(x: list[float], y: list[float], n_points: int = 300, yerr: list[float] | None = None):
    """Try a true nonlinear logistic fit y = 1/(1+exp(-(a*x + b))).

    Falls back to `_sigmoid_regression_3sigma` if required libraries or
    fitting fails.
    Returns (xs, fit, upper, lower).
    """
    if not x or not y or len(x) != len(y):
        return [], [], [], []
    if len(x) < 2:
        return x[:], y[:], y[:], y[:]

    try:
        import numpy as _np
        from math import exp
        try:
            from scipy.optimize import curve_fit

            def _model(xv, a, b):
                return 1.0 / (1.0 + _np.exp(-(a * _np.asarray(xv) + b)))

            # initial guess: use linear logit regression if possible
            eps = 1e-6
            clipped = [_np.clip(v, eps, 1.0 - eps) for v in y]
            logits = [_np.log(v / (1.0 - v)) for v in clipped]
            # linear fit in logit space
            a0 = 0.0
            b0 = 0.0
            try:
                A = _np.vstack([x, _np.ones_like(x)]).T
                sol, *_ = _np.linalg.lstsq(A, _np.asarray(logits), rcond=None)
                a0, b0 = sol[0], sol[1]
            except Exception:
                a0, b0 = 10.0, -6.0

            sigma = None
            if yerr is not None:
                try:
                    sigma = _np.asarray(yerr, dtype=float)
                    sigma = _np.maximum(sigma, 1e-8)
                except Exception:
                    sigma = None

            popt, pcov = curve_fit(_model, _np.asarray(x), _np.asarray(y), p0=[a0, b0], sigma=sigma, maxfev=10000)
            a, b = popt[0], popt[1]

            xs = [min(x) + i * (max(x) - min(x)) / (n_points - 1) for i in range(n_points)]
            vals = 1.0 / (1.0 + _np.exp(-(a * _np.asarray(xs) + b)))
            fit = [float(vals[i]) for i in range(len(xs))]

            # approximate uncertainty via parameter covariance (delta method)
            upper = fit[:]  # conservative fallback
            lower = fit[:]
            try:
                vars = _np.diag(pcov)
                # simple +/- 3 sigma on parameters to make envelopes (conservative)
                a_hi, a_lo = a + 3.0 * _np.sqrt(max(vars[0], 0.0)), a - 3.0 * _np.sqrt(max(vars[0], 0.0))
                b_hi, b_lo = b + 3.0 * _np.sqrt(max(vars[1], 0.0)), b - 3.0 * _np.sqrt(max(vars[1], 0.0))
                fit_hi = [1.0 / (1.0 + _np.exp(-(a_hi * xi + b_hi))) for xi in xs]
                fit_lo = [1.0 / (1.0 + _np.exp(-(a_lo * xi + b_lo))) for xi in xs]
                upper = fit_hi
                lower = fit_lo
            except Exception:
                pass

            return xs, fit, upper, lower
        except Exception:
            # scipy not available or fit failed: fall back
            return _sigmoid_regression_3sigma(x, y, n_points=n_points)
    except Exception:
        return _sigmoid_regression_3sigma(x, y, n_points=n_points)


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


def _binomial_logit_regression_from_buckets(buckets: dict[float, tuple[float, float]], n_points: int = 300):
    """Fit a binomial logistic regression to aggregated (successes, trials) buckets.

    buckets: mapping p_value -> (successes, trials)
    Returns (xs, fit, upper, lower) where xs is a grid of p values.
    """
    try:
        import numpy as _np
        from scipy.optimize import minimize
    except Exception:
        return [], [], [], []

    probs = sorted(buckets)
    successes = _np.asarray([buckets[p][0] for p in probs], dtype=float)
    trials = _np.asarray([buckets[p][1] for p in probs], dtype=float)
    # avoid zero-trial buckets
    mask = trials > 0
    if not _np.any(mask):
        return [], [], [], []

    xs_data = _np.asarray([float(p) for p in probs])[mask]
    ks = successes[mask]
    ns = trials[mask]

    # observed proportions
    ys = ks / ns

    # initial linear logit guess
    eps = 1e-9
    ys_clipped = _np.clip(ys, eps, 1.0 - eps)
    logits = _np.log(ys_clipped / (1.0 - ys_clipped))
    try:
        A = _np.vstack([xs_data, _np.ones_like(xs_data)]).T
        sol, *_ = _np.linalg.lstsq(A, logits, rcond=None)
        a0, b0 = float(sol[0]), float(sol[1])
    except Exception:
        a0, b0 = 50.0, -30.0

    def neg_loglik(params):
        a, b = params[0], params[1]
        lin = a * xs_data + b
        p = 1.0 / (1.0 + _np.exp(-lin))
        p = _np.clip(p, 1e-12, 1.0 - 1e-12)
        ll = ks * _np.log(p) + (ns - ks) * _np.log(1.0 - p)
        return -_np.sum(ll)

    res = None
    try:
        res = minimize(neg_loglik, x0=_np.asarray([a0, b0], dtype=float), method="BFGS")
    except Exception:
        return [], [], [], []

    if not res.success:
        # fallback
        return [], [], [], []

    a_hat, b_hat = float(res.x[0]), float(res.x[1])

    # Grid
    xs = [float(min(probs) + i * (max(probs) - min(probs)) / (n_points - 1)) for i in range(n_points)]
    xs_arr = _np.asarray(xs)
    fit_vals = 1.0 / (1.0 + _np.exp(-(a_hat * xs_arr + b_hat)))
    fit = [float(v) for v in fit_vals]

    # covariance approximation from inverse Hessian (BFGS provides hess_inv)
    upper = fit[:]
    lower = fit[:]
    try:
        hess_inv = _np.asarray(res.hess_inv)
        if hess_inv.shape == (2, 2):
            param_vars = _np.diag(hess_inv)
            se_a = _np.sqrt(max(param_vars[0], 0.0))
            se_b = _np.sqrt(max(param_vars[1], 0.0))
            # 95% approximate CI using normal approximation (z=1.96)
            z = 1.96
            a_hi, a_lo = a_hat + z * se_a, a_hat - z * se_a
            b_hi, b_lo = b_hat + z * se_b, b_hat - z * se_b
            fit_hi = 1.0 / (1.0 + _np.exp(-(a_hi * xs_arr + b_hi)))
            fit_lo = 1.0 / (1.0 + _np.exp(-(a_lo * xs_arr + b_lo)))
            upper = [float(v) for v in fit_hi]
            lower = [float(v) for v in fit_lo]
    except Exception:
        pass

    return xs, fit, upper, lower


def _plot_with_binomial_logit(ax, rows: list[dict[str, object]], *, marker: str, color: str, label: str, fit_label: str, shade_label: str):
    """Aggregate raw rows by `p` and plot binomial logistic regression fit with binomial error bars."""
    try:
        import numpy as _np
    except Exception:
        _np = None
    buckets: dict[float, tuple[float, float]] = defaultdict(lambda: (0.0, 0.0))
    for row in rows:
        if "p" not in row or "spanning_count" not in row or "runs" not in row:
            continue
        p = float(row["p"])
        k, n = float(row.get("spanning_count", 0.0)), float(row.get("runs", 1.0))
        s, t = buckets[p]
        buckets[p] = (s + k, t + n)

    probs = sorted(buckets)
    if not probs:
        return

    means = []
    stderr = []
    for p in probs:
        s, t = buckets[p]
        prop = (s / t) if t > 0 else 0.0
        means.append(prop)
        if _np is not None:
            stderr.append((_np.sqrt(prop * (1.0 - prop) / t) if t > 0 else 0.0))
        else:
            stderr.append(0.0)

    # plot error bars
    ax.errorbar(probs, means, yerr=stderr, fmt=marker, linestyle="none", capsize=3, markersize=5, label=label, color=color, alpha=0.95)

    fit_x, fit_y, fit_hi, fit_lo = _binomial_logit_regression_from_buckets({p: buckets[p] for p in probs})
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


def _plot_with_sigmoid_fit_nonlinear(
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
    """Plot points with error bars and a nonlinear logistic fit when available.

    Falls back to the existing linear-logit fit implementation if nonlinear
    fitting is not possible.
    """
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
    fit_x, fit_y, fit_hi, fit_lo = _sigmoid_regression_nonlinear(x, y, yerr=yerr)
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

    # Use binomial logistic regression over raw repeats for spanning probability
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
        # Show sigmoid-style approximation for front density (approximate)
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
    # Plot binomial logistic regression using raw rows (successes/trials)
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
    uart_wire_s = float(first_raw.get("uart_wire_s", (REQUEST_BYTES + RESPONSE_BYTES) * 10.0 / baudrate))
    ideal_core_cycles_per_run = steps * 3.0 + 3.0
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


def _find_sessions_by_params(conn: sqlite3.Connection, *, hw_width: int) -> list[dict]:
    """Return all session metadata matching the given effective HW width."""
    cur = conn.execute(
        "SELECT session_id, created_at, payload_json FROM benchmark_sessions ORDER BY created_at"
    )
    matches: list[dict] = []
    for row in cur.fetchall():
        payload = json.loads(row["payload_json"])
        if payload.get("effective_hw_width") == hw_width:
            matches.append(
                {
                    "session_id": str(row["session_id"]),
                    "created_at": str(row["created_at"]),
                    "runs": payload.get("runs", 0),
                    "steps": payload.get("steps", 0),
                    "points": payload.get("points", 0),
                    "repeats": payload.get("repeats", 1),
                }
            )
    return matches


def _session_data(conn: sqlite3.Connection, session_id: str) -> list[dict[str, object]]:
    return load_raw_rows(conn, session_id=session_id)


def _closest_row(rows: list[dict[str, object]], target_p: float) -> dict[str, object]:
    return min(rows, key=lambda r: abs(float(r.get("p", 0.0)) - target_p))


def plot_amdahl_speedup(conn: sqlite3.Connection, output: Path, *, hw_width: int = 128, target_p: float = 0.60) -> None:
    """Amdahl speedup vs batch size (Fig 3a/3b in the FPGA analysis guide)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    sessions = _find_sessions_by_params(conn, hw_width=hw_width)
    if not sessions:
        print(f"  [amdahl] no sessions found for hw_width={hw_width}")
        return

    # Group by steps, then sort by runs
    from collections import defaultdict

    by_steps: dict[int, list[dict]] = defaultdict(list)
    for s in sessions:
        by_steps[s["steps"]].append(s)
    for steps in by_steps:
        by_steps[steps].sort(key=lambda x: x["runs"])

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    colors = ["tab:blue", "tab:orange", "tab:green", "tab:red", "tab:purple", "tab:brown"]

    for idx, steps in enumerate(sorted(by_steps)):
        color = colors[idx % len(colors)]
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
        label = f"steps={steps}"

        ax1.plot(runs_list, lat_list, "o-", color=color, label=label)
        ax2.plot(runs_list, speedup, "o-", color=color, label=label)

    ax1.set_xscale("log", base=2)
    ax1.set_yscale("log")
    ax1.set_xlabel("cfg_runs (batch size)")
    ax1.set_ylabel("Total latency [s]")
    ax1.set_title(f"Latency vs Batch Size (N={hw_width}, p≈{target_p})")
    ax1.grid(True, alpha=0.3)
    ax1.legend(fontsize=8)

    ax2.set_xscale("log", base=2)
    ax2.set_xlabel("cfg_runs (batch size)")
    ax2.set_ylabel("Speedup vs R=1")
    ax2.set_title(f"Amdahl Speedup (N={hw_width}, p≈{target_p})")
    ax2.grid(True, alpha=0.3)
    ax2.legend(fontsize=8)

    fig.tight_layout()
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)
    plt.close(fig)


def plot_breakdown_fit(conn: sqlite3.Connection, output: Path, *, hw_width: int = 128, target_p: float = 0.60) -> None:
    """Asymptotic cycles-per-run fit separating fixed overhead from marginal cost (Fig 4)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    sessions = _find_sessions_by_params(conn, hw_width=hw_width)
    if not sessions:
        return

    by_steps: dict[int, list[dict]] = defaultdict(list)
    for s in sessions:
        by_steps[s["steps"]].append(s)
    for steps in by_steps:
        by_steps[steps].sort(key=lambda x: x["runs"])

    fig, ax = plt.subplots(1, 1, figsize=(10, 6))

    results: list[dict] = []

    for steps in sorted(by_steps):
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

        # Fit: C_total × R = C_fixed + C_marginal × R
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

        # Plot raw data
        ax.plot(
            runs_list,
            core_cyc_list,
            "o-",
            label=f"S={steps} measured",
            alpha=0.7,
        )
        # Plot fit
        fit_y = [C_fixed / r + C_marginal for r in runs_list]
        ax.plot(runs_list, fit_y, "--", alpha=0.5, label=f"S={steps} fit: {C_marginal:.0f} cyc/run")

    ax.set_xscale("log", base=2)
    ax.set_yscale("log")
    ax.set_xlabel("cfg_runs")
    ax.set_ylabel("Core cycles per run (est)")
    ax.set_title(f"Asymptotic Cycles/Run Fit (N={hw_width}, p≈{target_p})\nC_total×R = C_fixed + C_marginal×R")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8)

    # Print results table
    print(f"\n=== Asymptotic Fit Results (N={hw_width}, p≈{target_p}) ===")
    print(f"{'steps':>6}  {'C_marginal':>10}  {'C_fixed':>10}  {'frontier_ideal':>14}  {'overhead':>8}")
    print("-" * 58)
    for r in sorted(results, key=lambda x: x["steps"]):
        s = r["steps"]
        frontier_ideal = s * FRONTIER_CYCLES_PER_STEP
        overhead = r["C_marginal"] - frontier_ideal
        print(
            f"{s:6d}  {r['C_marginal']:10.1f}  {r['C_fixed']:10.0f}  {frontier_ideal:14.1f}  {overhead:8.1f}"
        )

    fig.tight_layout()
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)
    plt.close(fig)

    return results


def plot_pipeline_efficiency(conn: sqlite3.Connection, output: Path, *, hw_width: int = 128, target_p: float = 0.60) -> None:
    """Frontier cost breakdown: marginal cycles/run vs steps (Fig 5/6)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    sessions = _find_sessions_by_params(conn, hw_width=hw_width)
    if not sessions:
        return

    # Use only largest runs (host overhead amortized)
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

    # Linear fit: C_marginal = C_per_step × S + C_fixed_per_run
    n = len(steps_vals)
    x = [float(s) for s in steps_vals]
    y = cyc_vals[:]
    x_mean = sum(x) / n
    y_mean = sum(y) / n
    sxx = sum((xi - x_mean) ** 2 for xi in x)
    sxy = sum((xi - x_mean) * (yi - y_mean) for xi, yi in zip(x, y))
    if sxx > 0:
        slope = sxy / sxx
        intercept = y_mean - slope * x_mean
    else:
        slope = 0
        intercept = 0

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    # Left: C_marginal vs S with fit
    ax1.plot(steps_vals, cyc_vals, "o-", label=f"Measured (runs={max_runs})")
    fit_x = [min(x), max(x)]
    fit_y = [intercept + slope * xi for xi in fit_x]
    ax1.plot(fit_x, fit_y, "--", label=f"Fit: {slope:.2f}×S + {intercept:.1f}")
    ax1.axhline(FRONTIER_CYCLES_PER_STEP, color="gray", linestyle=":", alpha=0.5, label=f"Ideal frontier={FRONTIER_CYCLES_PER_STEP}/step")
    ax1.set_xlabel("Grid height (steps)")
    ax1.set_ylabel("Core cycles per run")
    ax1.set_title(f"Frontier Cost (N={hw_width}, runs={max_runs})")
    ax1.grid(True, alpha=0.3)
    ax1.legend()

    # Right: efficiency vs S
    ideal_cyc = [s * FRONTIER_CYCLES_PER_STEP + PER_RUN_SM_OVERHEAD_CYCLES for s in steps_vals]
    efficiency = [cyc_vals[i] / ideal_cyc[i] * 100 if ideal_cyc[i] > 0 else 0 for i in range(len(steps_vals))]
    excess = [cyc_vals[i] - ideal_cyc[i] for i in range(len(steps_vals))]

    ax2.plot(steps_vals, efficiency, "s-", color="tab:green", label="Efficiency [%]")
    ax2_twin = ax2.twinx()
    ax2_twin.plot(steps_vals, excess, "o--", color="tab:red", alpha=0.7, label="Excess cycles")
    ax2.set_xlabel("Grid height (steps)")
    ax2.set_ylabel("Pipeline efficiency [%]")
    ax2_twin.set_ylabel("Excess cycles")
    ax2.set_title(f"Pipeline Utilization (N={hw_width})")
    ax2.grid(True, alpha=0.3)
    ax2.legend(loc="upper left")
    ax2_twin.legend(loc="upper right")

    print(
        f"\n=== Pipeline Efficiency (N={hw_width}, runs={max_runs}, p≈{target_p}) ===\n"
        f"  Fit: C_core/run = {slope:.2f} × steps + {intercept:.1f}\n"
        f"  Ideal frontier: {FRONTIER_CYCLES_PER_STEP} cyc/step, SM overhead: {PER_RUN_SM_OVERHEAD_CYCLES} cyc/run\n"
        f"  Per-step cost:  {slope:.2f} cyc/step (vs ideal {FRONTIER_CYCLES_PER_STEP})\n"
        f"  Fixed overhead: {intercept:.1f} cyc/run (vs ideal {PER_RUN_SM_OVERHEAD_CYCLES})"
    )

    fig.tight_layout()
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)
    plt.close(fig)


def plot_throughput_invariance(conn: sqlite3.Connection, output: Path, *, hw_width: int = 128, target_p: float = 0.60) -> None:
    """Grid-height invariance: cells/s vs steps for multiple batch sizes (Fig 7)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    sessions = _find_sessions_by_params(conn, hw_width=hw_width)
    if not sessions:
        return

    # Group by runs
    by_runs: dict[int, list[dict]] = defaultdict(list)
    for s in sessions:
        by_runs[s["runs"]].append(s)
    for runs in by_runs:
        by_runs[runs].sort(key=lambda x: x["steps"])

    fig, ax = plt.subplots(1, 1, figsize=(10, 6))

    colors = ["tab:blue", "tab:orange", "tab:green", "tab:red", "tab:purple", "tab:brown", "tab:pink", "tab:gray"]

    for idx, runs in enumerate(sorted(by_runs)):
        color = colors[idx % len(colors)]
        steps_list: list[int] = []
        cells_list: list[float] = []
        for s in by_runs[runs]:
            rows = _session_data(conn, s["session_id"])
            if not rows:
                continue
            row = _closest_row(rows, target_p)
            steps_list.append(s["steps"])
            cells_list.append(float(row.get("cells_per_s", 0)))

        if not steps_list:
            continue

        ax.plot(steps_list, cells_list, "o-", color=color, label=f"runs={runs}")

    ax.set_xscale("log", base=2)
    ax.set_yscale("log")
    ax.set_xlabel("Grid height (steps)")
    ax.set_ylabel("Throughput [cells/s]")
    ax.set_title(f"Grid-Height Invariance (N={hw_width}, p≈{target_p})")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8)

    fig.tight_layout()
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=150)
    plt.close(fig)


def plot_determinism_cv(conn: sqlite3.Connection, output: Path, *, hw_width: int = 128, target_p: float = 0.60) -> None:
    """Coefficient of variation across repeats to quantify determinism (Fig 8)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    sessions = _find_sessions_by_params(conn, hw_width=hw_width)
    if not sessions:
        return

    # Only sessions with repeats > 1
    multi_repeat = [s for s in sessions if s["repeats"] > 1]

    if not multi_repeat:
        fig, ax = plt.subplots(1, 1, figsize=(10, 5))
        ax.text(0.5, 0.5, "No multi-repeat data available for hw_width={hw_width}", ha="center", va="center", transform=ax.transAxes)
        output.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(output, dpi=150)
        plt.close(fig)
        return

    fig, ax = plt.subplots(1, 1, figsize=(10, 5))

    from collections import defaultdict

    # Group repeat data by (steps, runs)
    config_cv: dict[tuple[int, int], list[float]] = defaultdict(list)

    for s in multi_repeat:
        rows = _session_data(conn, s["session_id"])
        if not rows:
            continue
        # Group repeats by p
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

    # Average CV per config
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


def plot_throughput_contour(conn: sqlite3.Connection, output: Path, *, hw_width: int = 128) -> None:
    """2D heatmap of throughput across p × steps for large batch size (Fig 9)."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    sessions = _find_sessions_by_params(conn, hw_width=hw_width)
    if not sessions:
        return

    # Find largest runs
    max_runs = max(s["runs"] for s in sessions)
    best_sessions = [s for s in sessions if s["runs"] == max_runs]

    # Build 2D grid
    all_steps = sorted({s["steps"] for s in best_sessions})
    all_p: set[float] = set()

    # First pass: collect all p values
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

    # Mask NaN for contour
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
    """Convenience: run all FPGA engineering plots and save to output_dir."""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Use benchmark-2 for runs-sweep data (includes N=128, N=180 runs sweeps)
    conn2 = _connect(db2_path)
    try:
        print(f"\n{'='*60}")
        print(f"FPGA Engineering Analysis (N={hw_width}, p≈{target_p})")
        print(f"{'='*60}")

        print("\n[1/5] Amdahl Speedup...")
        plot_amdahl_speedup(conn2, output_dir / "amdahl_speedup.png", hw_width=hw_width, target_p=target_p)

        print("\n[2/5] Asymptotic Breakdown Fit...")
        plot_breakdown_fit(conn2, output_dir / "breakdown_fit.png", hw_width=hw_width, target_p=target_p)

        print("\n[3/5] Pipeline Efficiency...")
        plot_pipeline_efficiency(conn2, output_dir / "pipeline_efficiency.png", hw_width=hw_width, target_p=target_p)

        print("\n[4/5] Throughput Invariance...")
        plot_throughput_invariance(conn2, output_dir / "throughput_invariance.png", hw_width=hw_width, target_p=target_p)

        print("\n[5/5] Throughput Contour...")
        plot_throughput_contour(conn2, output_dir / "throughput_contour.png", hw_width=hw_width)

        print("\n[extra] Determinism CV (N=128)...")
        plot_determinism_cv(conn2, output_dir / "determinism_cv.png", hw_width=128, target_p=target_p)

        print("\n[extra] Determinism CV (N=180)...")
        plot_determinism_cv(conn2, output_dir / "determinism_cv_180.png", hw_width=180, target_p=target_p)
    finally:
        conn2.close()

    # Software comparison data is in benchmark.sqlite3
    print(f"\nAll FPGA engineering plots saved to {output_dir}")

    print(f"\nAll FPGA engineering plots saved to {output_dir}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect percolation benchmark SQLite history")
    parser.add_argument("--db", type=str, default=str(DEFAULT_DB))
    parser.add_argument("--latest", action="store_true", help="Only inspect latest session")
    parser.add_argument("--plot", type=str, default="", help="Optional throughput plot output path")
    parser.add_argument("--plot-dir", type=str, default="", help="Optional output directory for starter plots")
    parser.add_argument(
        "--fpga-plot",
        type=str,
        default="",
        help="Output directory for FPGA engineering analysis plots (uses benchmark-2)",
    )
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
            plot_latency_decomposition(rows, raw_rows, plot_dir / "latency_decomposition.png")
            plot_front_density(raw_rows, plot_dir / "front_density.png")
            plot_cluster_mass(raw_rows, plot_dir / "cluster_mass.png")
            plot_occupancy_bias(raw_rows, plot_dir / "occupancy_bias.png")
            plot_core_latency(raw_rows, plot_dir / "core_latency.png")
            plot_spanning_probability(raw_rows, plot_dir / "spanning_probability.png")
            print(f"plot_dir_saved={plot_dir}")
    finally:
        conn.close()

    if args.fpga_plot:
        plot_fpga_all(
            Path(args.fpga_plot),
            db2_path=DEFAULT_DB2,
        )
        print(f"fpga_analysis_saved={args.fpga_plot}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())