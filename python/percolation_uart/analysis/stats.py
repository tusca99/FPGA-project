"""Statistical helpers: aggregation, regression, plotting wrappers."""

from __future__ import annotations

import math
from collections import defaultdict


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

            upper = fit[:]
            lower = fit[:]
            try:
                vars = _np.diag(pcov)
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
            return _sigmoid_regression_3sigma(x, y, n_points=n_points)
    except Exception:
        return _sigmoid_regression_3sigma(x, y, n_points=n_points)


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
    mask = trials > 0
    if not _np.any(mask):
        return [], [], [], []

    xs_data = _np.asarray([float(p) for p in probs])[mask]
    ks = successes[mask]
    ns = trials[mask]

    ys = ks / ns

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
        return [], [], [], []

    a_hat, b_hat = float(res.x[0]), float(res.x[1])

    xs = [float(min(probs) + i * (max(probs) - min(probs)) / (n_points - 1)) for i in range(n_points)]
    xs_arr = _np.asarray(xs)
    fit_vals = 1.0 / (1.0 + _np.exp(-(a_hat * xs_arr + b_hat)))
    fit = [float(v) for v in fit_vals]

    upper = fit[:]
    lower = fit[:]
    try:
        hess_inv = _np.asarray(res.hess_inv)
        if hess_inv.shape == (2, 2):
            param_vars = _np.diag(hess_inv)
            se_a = _np.sqrt(max(param_vars[0], 0.0))
            se_b = _np.sqrt(max(param_vars[1], 0.0))
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
