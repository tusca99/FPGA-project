"""Percolation UART client and benchmark helpers."""

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
    "decode_response",
    "encode_request",
    "probability_to_uq32",
    "simulate_request",
    "simulate_run",
    "uq32_to_probability",
]
