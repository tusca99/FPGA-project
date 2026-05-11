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
    REQUEST_BYTES,
    RESPONSE_BYTES,
    PercolationRequest,
    PercolationResponse,
    decode_response,
    encode_request,
    probability_to_uq32,
    uq32_to_probability,
)
from .reference import RunResult, simulate_request, simulate_run
from .transport import UartTransport

__all__ = [
    "MAX_CFG_RUNS",
    "MAX_GRID_SIZE",
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
    "run_sweep_software",
    "simulate_request",
    "simulate_run",
    "uq32_to_probability",
]
