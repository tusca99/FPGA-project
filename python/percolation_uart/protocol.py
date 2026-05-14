"""Binary UART protocol helpers for the percolation core."""

from __future__ import annotations

from dataclasses import dataclass
import math
import struct

REQUEST_BYTES = 16
RESPONSE_BYTES = 16
WORD_BYTES = 4
UQ32_SCALE = 1 << 32
MAX_GRID_SIZE = 1023
CORE_WIDTH = 64
MAX_TOTAL_OCCUPIED = 0xFFFFFFFF
MAX_CFG_RUNS = 0xFFFFFFFF


def max_cfg_runs_for_steps(steps_per_run: int, width: int = CORE_WIDTH, total_limit: int = MAX_TOTAL_OCCUPIED) -> int:
    """Return the largest cfg_runs that keeps the total occupied count in 32 bits."""

    if steps_per_run < 1:
        raise ValueError("steps_per_run must be positive")
    if width < 1:
        raise ValueError("width must be positive")
    return total_limit // (width * steps_per_run)


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
    steps_per_run: int
    cfg_runs: int

    def __post_init__(self) -> None:
        _ensure_u32(self.cfg_p_uq32, "cfg_p_uq32")
        _ensure_u32(self.cfg_seed, "cfg_seed")
        if not 1 <= self.steps_per_run <= MAX_GRID_SIZE:
            raise ValueError(f"steps_per_run must be in the range 1..{MAX_GRID_SIZE}")
        max_safe_runs = min(MAX_CFG_RUNS, max_cfg_runs_for_steps(self.steps_per_run))
        if not 1 <= self.cfg_runs <= max_safe_runs:
            raise ValueError(
                f"cfg_runs must be in the range 1..{max_safe_runs} for steps_per_run={self.steps_per_run} "
                f"at width {CORE_WIDTH}"
            )

    @classmethod
    def from_probability(
        cls,
        probability: float,
        cfg_seed: int,
        steps_per_run: int,
        cfg_runs: int,
    ) -> "PercolationRequest":
        return cls(
            cfg_p_uq32=probability_to_uq32(probability),
            cfg_seed=cfg_seed,
            steps_per_run=steps_per_run,
            cfg_runs=cfg_runs,
        )

    @property
    def word2(self) -> int:
        return self.steps_per_run & 0xFFFFFFFF

    @property
    def grid_size(self) -> int:
        return self.steps_per_run


@dataclass(frozen=True)
class PercolationResponse:
    """Response payload returned by the FPGA UART top."""

    step_count: int
    spanning_count: int
    total_occupied: int
    spanning_occupied: int

    @property
    def is_error(self) -> bool:
        return False  # No status word in v3.1; errors are implicit (step_count mismatch)

    def as_tuple(self) -> tuple[int, int, int, int]:
        return (
            self.step_count,
            self.spanning_count,
            self.total_occupied,
            self.spanning_occupied,
        )


def encode_request(request: PercolationRequest) -> bytes:
    """Pack a request into the 16-byte wire format."""

    return struct.pack(
        ">IIII",
        request.cfg_p_uq32 & 0xFFFFFFFF,
        request.cfg_seed & 0xFFFFFFFF,
        request.word2 & 0xFFFFFFFF,
        request.cfg_runs & 0xFFFFFFFF,
    )


def encode_response(response: PercolationResponse) -> bytes:
    """Pack a response into the 16-byte wire format."""

    return struct.pack(
        ">IIII",
        response.step_count & 0xFFFFFFFF,
        response.spanning_count & 0xFFFFFFFF,
        response.total_occupied & 0xFFFFFFFF,
        response.spanning_occupied & 0xFFFFFFFF,
    )


def decode_response(payload: bytes) -> PercolationResponse:
    """Unpack a 16-byte response from the FPGA."""

    if len(payload) != RESPONSE_BYTES:
        raise ProtocolError(f"expected {RESPONSE_BYTES} response bytes, got {len(payload)}")

    step_count, spanning_count, total_occupied, spanning_occupied = struct.unpack(
        ">IIII", payload
    )
    return PercolationResponse(
        step_count=step_count,
        spanning_count=spanning_count,
        total_occupied=total_occupied,
        spanning_occupied=spanning_occupied,
    )
