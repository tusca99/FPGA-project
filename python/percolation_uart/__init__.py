"""Percolation UART client and benchmark helpers."""

from .algorithms import (
    bfs_spanning,
    fpga_directed_spanning,
    fpga_reach_row,
    generate_grid,
    run_sweep_software,
)
from .client import PercolationClient
from .protocol import (
    MAX_CFG_RUNS,
    MAX_GRID_SIZE,
    MAX_STEPS_PER_RUN,
    REQUEST_BYTES,
    RESPONSE_BYTES,
    PercolationRequest,
    PercolationResponse,
    decode_response,
    encode_request,
    probability_to_uq32,
    max_cfg_runs_for_probability,
    max_steps_per_run_for_probability,
    uq32_to_probability,
)
from .reference import RunResult, simulate_request, simulate_run
from .transport import UartTransport

__all__ = [
    "MAX_CFG_RUNS",
    "MAX_GRID_SIZE",
    "MAX_STEPS_PER_RUN",
    "PercolationClient",
    "PercolationRequest",
    "PercolationResponse",
    "REQUEST_BYTES",
    "RESPONSE_BYTES",
    "RunResult",
    "UartTransport",
    "bfs_spanning",
    "decode_response",
    "encode_request",
    "fpga_directed_spanning",
    "fpga_reach_row",
    "generate_grid",
    "probability_to_uq32",
    "max_cfg_runs_for_probability",
    "max_steps_per_run_for_probability",
    "run_sweep_software",
    "simulate_request",
    "simulate_run",
    "uq32_to_probability",
]
