"""Binary UART protocol helpers for the percolation core."""

from __future__ import annotations

from dataclasses import dataclass
import math
import struct

REQUEST_BYTES = 12
RESPONSE_BYTES = 16
WORD_BYTES = 4
UQ32_SCALE = 1 << 32
MAX_GRID_SIZE = 128
MAX_CFG_RUNS = 0xFFFFFF


class ProtocolError(ValueError):
    """Raised when a payload or field does not match the protocol."""


def _ensure_u32(value: int, field_name: str) -> None:
    if not 0 <= value <= 0xFFFFFFFF:
        raise ValueError(f"{field_name} must fit in 32 bits")


def probability_to_uq32(probability: float) -> int:
    """Convert a probability in [0, 1) to the fixed-point format used by the FPGA."""

    if not math.isfinite(probability):
        raise ValueError("probability must be finite")
    if not 0.0 <= probability < 1.0:
        raise ValueError("probability must be in the range [0, 1)")

    scaled = int(round(probability * UQ32_SCALE))
    return min(scaled, 0xFFFFFFFF)


def uq32_to_probability(raw_value: int) -> float:
    """Convert a 32-bit fixed-point threshold back to a floating point probability."""

    _ensure_u32(raw_value, "raw_value")
    return raw_value / UQ32_SCALE


@dataclass(frozen=True)
class PercolationRequest:
    """Request payload accepted by the FPGA UART top."""

    cfg_p_uq32: int
    cfg_seed: int
    grid_size: int
    cfg_runs: int

    def __post_init__(self) -> None:
        _ensure_u32(self.cfg_p_uq32, "cfg_p_uq32")
        _ensure_u32(self.cfg_seed, "cfg_seed")
        if not 1 <= self.grid_size <= MAX_GRID_SIZE:
            raise ValueError(f"grid_size must be in the range 1..{MAX_GRID_SIZE}")
        if not 1 <= self.cfg_runs <= MAX_CFG_RUNS:
            raise ValueError(f"cfg_runs must be in the range 1..{MAX_CFG_RUNS}")

    @classmethod
    def from_probability(
        cls,
        probability: float,
        cfg_seed: int,
        grid_size: int,
        cfg_runs: int,
    ) -> "PercolationRequest":
        return cls(
            cfg_p_uq32=probability_to_uq32(probability),
            cfg_seed=cfg_seed,
            grid_size=grid_size,
            cfg_runs=cfg_runs,
        )

    @property
    def word2(self) -> int:
        return ((self.grid_size & 0xFF) << 24) | (self.cfg_runs & MAX_CFG_RUNS)


@dataclass(frozen=True)
class PercolationResponse:
    """Response payload returned by the FPGA UART top."""

    step_count: int
    spanning_count: int
    total_occupied: int
    bfs_step_count: int

    def as_tuple(self) -> tuple[int, int, int, int]:
        return (
            self.step_count,
            self.spanning_count,
            self.total_occupied,
            self.bfs_step_count,
        )


def encode_request(request: PercolationRequest) -> bytes:
    """Pack a request into the 12-byte wire format."""

    return struct.pack(
        ">III",
        request.cfg_p_uq32 & 0xFFFFFFFF,
        request.cfg_seed & 0xFFFFFFFF,
        request.word2 & 0xFFFFFFFF,
    )


def encode_response(response: PercolationResponse) -> bytes:
    """Pack a response into the 16-byte wire format."""

    return struct.pack(
        ">IIII",
        response.step_count & 0xFFFFFFFF,
        response.spanning_count & 0xFFFFFFFF,
        response.total_occupied & 0xFFFFFFFF,
        response.bfs_step_count & 0xFFFFFFFF,
    )


def decode_response(payload: bytes) -> PercolationResponse:
    """Unpack a 16-byte response from the FPGA."""

    if len(payload) != RESPONSE_BYTES:
        raise ProtocolError(f"expected {RESPONSE_BYTES} response bytes, got {len(payload)}")

    step_count, spanning_count, total_occupied, bfs_step_count = struct.unpack(
        ">IIII", payload
    )
    return PercolationResponse(
        step_count=step_count,
        spanning_count=spanning_count,
        total_occupied=total_occupied,
        bfs_step_count=bfs_step_count,
    )
