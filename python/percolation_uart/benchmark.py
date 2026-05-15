"""Benchmark CLI for percolation software and FPGA UART paths.

Hardware note: FPGA grid width is compile-time constant in bitstream.
Only `steps_per_run` is runtime configurable through UART protocol.
"""

from __future__ import annotations

import argparse
import json
import math
import hashlib
import sqlite3
import sys
import time
import uuid
from pathlib import Path
from datetime import datetime, timezone

from .algorithms import run_sweep_software
from .client import PercolationClient
from .protocol import REQUEST_BYTES, RESPONSE_BYTES, PercolationRequest

try:
    from tqdm import tqdm
except ImportError:  # pragma: no cover - optional progress bar
    tqdm = None


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


def _progress(iterable, *, total: int, enabled: bool, desc: str):
    if not enabled or tqdm is None:
        return iterable
    return tqdm(iterable, total=total, desc=desc, leave=False, file=sys.stderr)


def _run_software_benchmark(
    probabilities: list[float],
    runs: int,
    width: int,
    steps: int,
    seed: int,
    workers: int,
    repeats: int,
    progress: bool,
) -> tuple[list[dict[str, float]], list[dict[str, float]]]:
    rows: list[dict[str, float]] = []
    raw_rows: list[dict[str, float]] = []
    for p in _progress(probabilities, total=len(probabilities), enabled=progress, desc="SW points"):
        bfs_samples: list[float] = []
        fpga_samples: list[float] = []
        occ_samples: list[float] = []
        latency_samples: list[float] = []
        runs_per_s_samples: list[float] = []
        cells_per_s_samples: list[float] = []

        for repeat_index in _progress(range(repeats), total=repeats, enabled=progress and repeats > 1, desc=f"SW p={p:.4f}"):
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

            raw_rows.append(
                {
                    "mode": "sw",
                    "p": p,
                    "repeat_index": float(repeat_index + 1),
                    "runs": float(runs),
                    "steps": float(steps),
                    "width": float(width),
                    "hw_width": float(width),
                    "latency_s": dt,
                    "bfs_rate": bfs_rates[0],
                    "fpga_rate": fpga_rates[0],
                    "occ": occ_rates[0],
                    "runs_per_s": runs / dt if dt > 0 else 0.0,
                    "cells_per_s": (runs * steps * width) / dt if dt > 0 else 0.0,
                }
            )

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
    return rows, raw_rows


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
    progress: bool,
) -> tuple[list[dict[str, float]], list[dict[str, float]]]:
    rows: list[dict[str, float]] = []
    raw_rows: list[dict[str, float]] = []
    client = PercolationClient(port=port, baudrate=baudrate, timeout=timeout)
    try:
        for p in _progress(probabilities, total=len(probabilities), enabled=progress, desc="HW points"):
            rate_samples: list[float] = []
            occ_samples: list[float] = []
            occ_bias_samples: list[float] = []
            total_occupied_samples: list[float] = []
            spanning_occupied_samples: list[float] = []
            reachable_fraction_samples: list[float] = []
            reachable_sites_per_run_samples: list[float] = []
            mass_samples: list[float] = []
            span_count_samples: list[float] = []
            latency_samples: list[float] = []
            runs_per_s_samples: list[float] = []
            cells_per_s_samples: list[float] = []
            low_stats_hits = 0

            for repeat_index in _progress(range(repeats), total=repeats, enabled=progress and repeats > 1, desc=f"HW p={p:.4f}"):
                req = PercolationRequest.from_probability(
                    probability=p,
                    cfg_seed=seed,
                    steps_per_run=steps,
                    cfg_runs=runs,
                    width=hw_width,
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
                reachable_fraction = resp.spanning_occupied / resp.total_occupied if resp.total_occupied > 0 else 0.0
                reachable_sites_per_run = resp.spanning_occupied / runs if runs > 0 else 0.0
                mass = resp.spanning_occupied / resp.spanning_count if resp.spanning_count > 0 else 0.0

                rate_samples.append(rate)
                occ_samples.append(avg_occ)
                occ_bias_samples.append(occ_bias)
                total_occupied_samples.append(float(resp.total_occupied))
                spanning_occupied_samples.append(float(resp.spanning_occupied))
                reachable_fraction_samples.append(reachable_fraction)
                reachable_sites_per_run_samples.append(reachable_sites_per_run)
                mass_samples.append(mass)
                span_count_samples.append(float(resp.spanning_count))
                latency_samples.append(dt)
                runs_per_s_samples.append(runs / dt if dt > 0 else 0.0)
                cells_per_s_samples.append((runs * steps * hw_width) / dt if dt > 0 else 0.0)
                if low_stats:
                    low_stats_hits += 1

                raw_rows.append(
                    {
                        "mode": "hw",
                        "p": p,
                        "repeat_index": float(repeat_index + 1),
                        "runs": float(runs),
                        "steps": float(steps),
                        "width": float(hw_width),
                        "hw_width": float(hw_width),
                        "latency_s": dt,
                        "spanning_rate": rate,
                        "occ": avg_occ,
                        "occ_bias": occ_bias,
                        "total_occupied": float(resp.total_occupied),
                        "spanning_occupied": float(resp.spanning_occupied),
                        "reachable_fraction": reachable_fraction,
                        "reachable_sites_per_run": reachable_sites_per_run,
                        "mass": mass,
                        "spanning_count": float(resp.spanning_count),
                        "low_stats": 1.0 if low_stats else 0.0,
                        "uart_wire_s": (REQUEST_BYTES + RESPONSE_BYTES) * 10.0 / baudrate,
                        "latency_per_run_s": dt / runs if runs > 0 else 0.0,
                        "latency_per_run_cycles": (dt / runs if runs > 0 else 0.0) * 100_000_000.0,
                        "core_latency_s_est": max(0.0, dt - (REQUEST_BYTES + RESPONSE_BYTES) * 10.0 / baudrate),
                        "core_latency_per_run_s_est": max(0.0, dt - (REQUEST_BYTES + RESPONSE_BYTES) * 10.0 / baudrate) / runs if runs > 0 else 0.0,
                        "core_latency_per_run_cycles_est": (max(0.0, dt - (REQUEST_BYTES + RESPONSE_BYTES) * 10.0 / baudrate) / runs if runs > 0 else 0.0) * 100_000_000.0,
                        "runs_per_s": runs / dt if dt > 0 else 0.0,
                        "cells_per_s": (runs * steps * hw_width) / dt if dt > 0 else 0.0,
                    }
                )

            rate_mean, _, _ = _mean_std_err(rate_samples)
            occ_mean, _, _ = _mean_std_err(occ_samples)
            occ_bias_mean, _, _ = _mean_std_err(occ_bias_samples)
            total_occupied_mean, total_occupied_std, total_occupied_err = _mean_std_err(total_occupied_samples)
            spanning_occupied_mean, spanning_occupied_std, spanning_occupied_err = _mean_std_err(spanning_occupied_samples)
            reachable_fraction_mean, reachable_fraction_std, reachable_fraction_err = _mean_std_err(reachable_fraction_samples)
            reachable_sites_per_run_mean, reachable_sites_per_run_std, reachable_sites_per_run_err = _mean_std_err(reachable_sites_per_run_samples)
            mass_mean, _, _ = _mean_std_err(mass_samples)
            span_count_mean, _, _ = _mean_std_err(span_count_samples)
            latency_mean, latency_std, latency_err = _mean_std_err(latency_samples)
            runs_per_s_mean, runs_per_s_std, runs_per_s_err = _mean_std_err(runs_per_s_samples)
            cells_per_s_mean, cells_per_s_std, cells_per_s_err = _mean_std_err(cells_per_s_samples)
            uart_wire_s = (REQUEST_BYTES + RESPONSE_BYTES) * 10.0 / baudrate
            latency_per_run_s = latency_mean / runs if runs > 0 else 0.0
            latency_per_run_cycles = latency_per_run_s * 100_000_000.0
            core_latency_s_est = max(0.0, latency_mean - uart_wire_s)
            core_latency_per_run_s_est = core_latency_s_est / runs if runs > 0 else 0.0
            core_latency_per_run_cycles_est = core_latency_per_run_s_est * 100_000_000.0

            rows.append(
                {
                    "p": p,
                    "hw_repeats": float(repeats),
                    "hw_spanning_rate": rate_mean,
                    "hw_occ": occ_mean,
                    "hw_occ_bias": occ_bias_mean,
                    "hw_total_occupied": total_occupied_mean,
                    "hw_total_occupied_std": total_occupied_std,
                    "hw_total_occupied_err": total_occupied_err,
                    "hw_spanning_occupied": spanning_occupied_mean,
                    "hw_spanning_occupied_std": spanning_occupied_std,
                    "hw_spanning_occupied_err": spanning_occupied_err,
                    "hw_reachable_fraction": reachable_fraction_mean,
                    "hw_reachable_fraction_std": reachable_fraction_std,
                    "hw_reachable_fraction_err": reachable_fraction_err,
                    "hw_reachable_sites_per_run": reachable_sites_per_run_mean,
                    "hw_reachable_sites_per_run_std": reachable_sites_per_run_std,
                    "hw_reachable_sites_per_run_err": reachable_sites_per_run_err,
                    "hw_mass": mass_mean,
                    "hw_spanning_count": span_count_mean,
                    "hw_low_stats": 1.0 if low_stats_hits > 0 else 0.0,
                    "hw_low_stats_count": float(low_stats_hits),
                    "hw_latency_s": latency_mean,
                    "hw_latency_s_std": latency_std,
                    "hw_latency_s_err": latency_err,
                    "hw_uart_wire_s": uart_wire_s,
                    "hw_latency_per_run_s": latency_per_run_s,
                    "hw_latency_per_run_cycles": latency_per_run_cycles,
                    "hw_core_latency_s_est": core_latency_s_est,
                    "hw_core_latency_per_run_s_est": core_latency_per_run_s_est,
                    "hw_core_latency_per_run_cycles_est": core_latency_per_run_cycles_est,
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

    return rows, raw_rows


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
            "hw_latency_per_run_cycles",
            "hw_core_latency_per_run_cycles_est",
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
        "hw_latency_per_run_cycles",
        "hw_core_latency_per_run_cycles_est",
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


def _write_sqlite(path: Path, session: dict[str, object], summary_rows: list[dict[str, float]], raw_rows: list[dict[str, float]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS benchmark_sessions (
                session_id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                payload_json TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS benchmark_summary (
                session_id TEXT NOT NULL,
                p REAL NOT NULL,
                row_json TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS benchmark_raw (
                session_id TEXT NOT NULL,
                mode TEXT NOT NULL,
                p REAL NOT NULL,
                repeat_index INTEGER NOT NULL,
                row_json TEXT NOT NULL
            )
            """
        )
        conn.execute(
            "INSERT INTO benchmark_sessions(session_id, created_at, payload_json) VALUES (?, ?, ?)",
            (str(session["session_id"]), str(session["created_at"]), str(session["payload_json"])),
        )
        conn.executemany(
            "INSERT INTO benchmark_summary(session_id, p, row_json) VALUES (?, ?, ?)",
            [
                (str(session["session_id"]), float(row["p"]), json.dumps(row, sort_keys=True, default=str))
                for row in summary_rows
            ],
        )
        conn.executemany(
            "INSERT INTO benchmark_raw(session_id, mode, p, repeat_index, row_json) VALUES (?, ?, ?, ?, ?)",
            [
                (
                    str(session["session_id"]),
                    str(row.get("mode", "")),
                    float(row["p"]),
                    int(row.get("repeat_index", 0)),
                    json.dumps(row, sort_keys=True, default=str),
                )
                for row in raw_rows
            ],
        )
        conn.commit()
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark software and hardware percolation paths")
    parser.add_argument("--port", default="/dev/ttyUSB1")
    parser.add_argument("--baudrate", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=120.0, help="UART response timeout [s]")
    parser.add_argument("--runs", type=int, default=1000, help="cfg_runs per point")
    parser.add_argument("--steps", type=int, default=64, help="Grid height (runtime configurable)")
    parser.add_argument("--width", type=int, default=64, help="Software grid width")
    parser.add_argument("--hw-width", type=int, default=None, help="Hardware compile-time width; defaults to --width")
    parser.add_argument("--seed", type=lambda x: int(x, 0), default=0x12345678)
    parser.add_argument("--pmin", type=float, default=0.50)
    parser.add_argument("--pmax", type=float, default=0.70)
    parser.add_argument("--points", type=int, default=9)
    parser.add_argument("--workers", type=int, default=0, help="Software workers; 0 uses auto")
    parser.add_argument("--repeats", type=int, default=1, help="Repeated measurements per probability point")
    parser.add_argument("--settle", type=float, default=0.05, help="UART settle delay before each HW request [s]")
    parser.add_argument("--software-only", action="store_true")
    parser.add_argument("--hardware-only", action="store_true")
    parser.add_argument("--progress", action="store_true", help="Show coarse progress bars if tqdm is installed")
    parser.add_argument(
        "--sqlite",
        type=str,
        default="python/output/benchmark.sqlite3",
        help="Append raw and summary rows to an SQLite database",
    )
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
    effective_hw_width = args.width if args.hw_width is None else args.hw_width

    if have_hw:
        print(f"Hardware width fixed by bitstream: {effective_hw_width}")
        if args.width != effective_hw_width:
            print(
                "[WARNING] software width differs from hardware width; "
                "HW metrics use --hw-width, SW metrics use --width"
            )

    sw_rows = None
    hw_rows = None
    sw_raw_rows: list[dict[str, float]] = []
    hw_raw_rows: list[dict[str, float]] = []

    if have_sw:
        print("Running software benchmark...")
        sw_rows, sw_raw_rows = _run_software_benchmark(
            probabilities=probabilities,
            runs=args.runs,
            width=args.width,
            steps=args.steps,
            seed=args.seed,
            workers=args.workers,
            repeats=args.repeats,
            progress=args.progress,
        )

    if have_hw:
        print(f"Running hardware benchmark on {args.port}...")
        hw_rows, hw_raw_rows = _run_hardware_benchmark(
            probabilities=probabilities,
            runs=args.runs,
            hw_width=effective_hw_width,
            steps=args.steps,
            seed=args.seed,
            port=args.port,
            baudrate=args.baudrate,
            timeout=args.timeout,
            settle_s=args.settle,
            repeats=args.repeats,
            progress=args.progress,
        )

    rows = _merge_rows(probabilities, sw_rows, hw_rows)
    _print_table(rows, have_sw=have_sw, have_hw=have_hw)

    if args.sqlite:
        sqlite_path = Path(args.sqlite)
        config_payload = {
            key: value
            for key, value in vars(args).items()
            if key not in {"sqlite"}
        }
        config_payload["effective_hw_width"] = effective_hw_width
        config_json = json.dumps(config_payload, sort_keys=True, default=str)
        config_hash = hashlib.sha256(config_json.encode("utf-8")).hexdigest()
        session = {
            "session_id": str(uuid.uuid4()),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "command": "percolation_uart.benchmark",
            "args": vars(args),
            "effective_hw_width": effective_hw_width,
            "config_hash": config_hash,
            "payload_json": config_json,
        }
        raw_rows: list[dict[str, float]] = []
        if sw_rows is not None:
            raw_rows.extend(sw_raw_rows)
        if hw_rows is not None:
            raw_rows.extend(hw_raw_rows)
        _write_sqlite(sqlite_path, session, rows, raw_rows)
        print(f"SQLite saved to {sqlite_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())