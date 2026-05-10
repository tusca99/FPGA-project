"""Benchmark and sweep utilities for FPGA and Python reference runs."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import asdict, dataclass
import argparse
import csv
from pathlib import Path
from statistics import fmean
from time import perf_counter_ns
from typing import Iterable

from .client import PercolationClient
from .protocol import PercolationRequest
from .reference import simulate_request


@dataclass(frozen=True)
class BenchmarkRow:
    backend: str
    grid_size: int
    probability: float
    cfg_runs: int
    sample_index: int
    elapsed_us: float
    step_count: int
    spanning_count: int
    total_occupied: int
    status: int
    rng_init_cycles: int
    core_run_cycles: int
    batch_cycles: int


def _parse_int_list(values: Iterable[str]) -> list[int]:
    return [int(value) for value in values]


def _parse_float_list(values: Iterable[str]) -> list[float]:
    return [float(value) for value in values]


def _run_reference(request: PercolationRequest) -> tuple[object, float]:
    start_ns = perf_counter_ns()
    response = simulate_request(request)
    elapsed_us = (perf_counter_ns() - start_ns) / 1_000.0
    return response, elapsed_us


def _run_fpga(client: PercolationClient, request: PercolationRequest) -> tuple[object, float]:
    start_ns = perf_counter_ns()
    response = client.run(request)
    elapsed_us = (perf_counter_ns() - start_ns) / 1_000.0
    return response, elapsed_us


def run_sweep(
    backend: str,
    grid_sizes: Iterable[int],
    probabilities: Iterable[float],
    samples: int,
    cfg_runs: int,
    seed_base: int,
    port: str | None = None,
    baudrate: int = 115200,
    timeout: float = 1.0,
) -> list[BenchmarkRow]:
    rows: list[BenchmarkRow] = []
    grid_size_list = list(grid_sizes)
    probability_list = list(probabilities)

    client: PercolationClient | None = None
    if backend == "fpga":
        if port is None:
            raise ValueError("port is required when backend='fpga'")
        client = PercolationClient(port=port, baudrate=baudrate, timeout=timeout)

    try:
        for grid_size in grid_size_list:
            for probability in probability_list:
                for sample_index in range(samples):
                    request = PercolationRequest.from_probability(
                        probability=probability,
                        cfg_seed=seed_base + sample_index,
                        steps_per_run=grid_size,
                        cfg_runs=cfg_runs,
                    )

                    if backend == "reference":
                        response, elapsed_us = _run_reference(request)
                    elif backend == "fpga":
                        assert client is not None
                        response, elapsed_us = _run_fpga(client, request)
                    else:
                        raise ValueError("backend must be 'reference' or 'fpga'")

                    rows.append(
                        BenchmarkRow(
                            backend=backend,
                            grid_size=grid_size,
                            probability=probability,
                            cfg_runs=cfg_runs,
                            sample_index=sample_index,
                            elapsed_us=elapsed_us,
                            step_count=response.step_count,
                            spanning_count=response.spanning_count,
                            total_occupied=response.total_occupied,
                            status=response.status,
                            rng_init_cycles=response.rng_init_cycles,
                            core_run_cycles=response.core_run_cycles,
                            batch_cycles=response.batch_cycles,
                        )
                    )
    finally:
        if client is not None:
            client.close()

    return rows


def write_csv(rows: Iterable[BenchmarkRow], output_path: Path) -> None:
    fieldnames = [
        "backend",
        "grid_size",
        "probability",
        "cfg_runs",
        "sample_index",
        "elapsed_us",
        "step_count",
        "spanning_count",
        "total_occupied",
        "status",
        "rng_init_cycles",
        "core_run_cycles",
        "batch_cycles",
    ]
    with output_path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def summarize(rows: Iterable[BenchmarkRow]) -> str:
    grouped: dict[tuple[str, int, float], list[BenchmarkRow]] = defaultdict(list)
    for row in rows:
        grouped[(row.backend, row.grid_size, row.probability)].append(row)

    lines = []
    for (backend, grid_size, probability), group in sorted(grouped.items()):
        elapsed_mean = fmean(row.elapsed_us for row in group)
        error_rate = fmean(row.status for row in group)
        rng_mean = fmean(row.rng_init_cycles for row in group)
        core_mean = fmean(row.core_run_cycles for row in group)
        batch_mean = fmean(row.batch_cycles for row in group)
        lines.append(
            f"{backend:9s} N={grid_size:3d} p={probability:.4f} "
            f"samples={len(group):4d} elapsed_us={elapsed_mean:10.3f} error_rate={error_rate:8.4f} "
            f"rng={rng_mean:10.3f} core={core_mean:10.3f} batch={batch_mean:10.3f}"
        )
    return "\n".join(lines)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Percolation FPGA/Python benchmark sweep")
    parser.add_argument("--backend", choices=("reference", "fpga"), default="reference")
    parser.add_argument("--port", help="Serial port used when backend=fpga")
    parser.add_argument("--baudrate", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument("--grid-sizes", nargs="+", type=int, default=[8, 16, 32, 64, 128])
    parser.add_argument("--probabilities", nargs="+", type=float, default=[0.4, 0.5, 0.5927, 0.6, 0.7])
    parser.add_argument("--samples", type=int, default=100)
    parser.add_argument("--cfg-runs", type=int, default=1)
    parser.add_argument("--seed-base", type=int, default=0x12345678)
    parser.add_argument("--output", type=Path, help="Optional CSV output path")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    rows = run_sweep(
        backend=args.backend,
        grid_sizes=args.grid_sizes,
        probabilities=args.probabilities,
        samples=args.samples,
        cfg_runs=args.cfg_runs,
        seed_base=args.seed_base,
        port=args.port,
        baudrate=args.baudrate,
        timeout=args.timeout,
    )

    if args.output is not None:
        write_csv(rows, args.output)

    print(summarize(rows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
