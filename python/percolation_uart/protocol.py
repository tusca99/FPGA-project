"""Binary UART protocol helpers for the percolation core."""

from __future__ import annotations

from dataclasses import dataclass
import math
import struct

REQUEST_BYTES = 16
RESPONSE_BYTES = 16
WORD_BYTES = 4
UQ32_SCALE = 1 << 32
CORE_WIDTH = 64
MAX_TOTAL_OCCUPIED = 0xFFFFFFFF
MAX_CFG_RUNS = 0xFFFFFFFF
MAX_STEPS_PER_RUN = 0xFFFFFFFF
MAX_GRID_SIZE = MAX_STEPS_PER_RUN


def max_cfg_runs_for_probability(
    steps_per_run: int,
    probability: float,
    width: int = CORE_WIDTH,
    total_limit: int = MAX_TOTAL_OCCUPIED,
) -> int:
    """Return a conservative cfg_runs bound for the given width, p, and step count."""

    if steps_per_run < 1:
        raise ValueError("steps_per_run must be positive")
    if not math.isfinite(probability):
        raise ValueError("probability must be finite")
    if not 0.0 <= probability < 1.0:
        raise ValueError("probability must be in the range [0, 1)")
    if width < 1:
        raise ValueError("width must be positive")
    if probability == 0.0:
        return MAX_CFG_RUNS

    expected_occupied_per_run = max(1, math.ceil(width * steps_per_run * probability))
    return total_limit // expected_occupied_per_run


def max_steps_per_run_for_probability(
    probability: float,
    width: int = CORE_WIDTH,
    total_limit: int = MAX_TOTAL_OCCUPIED,
) -> int:
    """Return a conservative upper bound on steps_per_run for the given width and p.

    The limit is derived from the expected occupied sites per run, so wider grids or
    higher occupancy probabilities reduce the safe step budget.
    """

    if not math.isfinite(probability):
        raise ValueError("probability must be finite")
    if not 0.0 <= probability < 1.0:
        raise ValueError("probability must be in the range [0, 1)")
    if width < 1:
        raise ValueError("width must be positive")
    if probability == 0.0:
        return MAX_STEPS_PER_RUN

    expected_occupied_per_step = max(1, math.ceil(width * probability))
    return total_limit // expected_occupied_per_step


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
    width: int = CORE_WIDTH

    def __post_init__(self) -> None:
        _ensure_u32(self.cfg_p_uq32, "cfg_p_uq32")
        _ensure_u32(self.cfg_seed, "cfg_seed")
        if self.width < 1:
            raise ValueError("width must be positive")

        probability = uq32_to_probability(self.cfg_p_uq32)
        max_safe_steps = min(MAX_STEPS_PER_RUN, max_steps_per_run_for_probability(probability, width=self.width))
        if not 1 <= self.steps_per_run <= max_safe_steps:
            raise ValueError(
                f"steps_per_run must be in the range 1..{max_safe_steps} for p={probability:.6f} and width={self.width}"
            )

        max_safe_runs = min(
            MAX_CFG_RUNS,
            max_cfg_runs_for_probability(self.steps_per_run, probability, width=self.width),
        )
        if not 1 <= self.cfg_runs <= max_safe_runs:
            raise ValueError(
                f"cfg_runs must be in the range 1..{max_safe_runs} for steps_per_run={self.steps_per_run} "
                f"at width {self.width}"
            )

    @classmethod
    def from_probability(
        cls,
        probability: float,
        cfg_seed: int,
        steps_per_run: int,
        cfg_runs: int,
        width: int = CORE_WIDTH,
    ) -> "PercolationRequest":
        return cls(
            cfg_p_uq32=probability_to_uq32(probability),
            cfg_seed=cfg_seed,
            steps_per_run=steps_per_run,
            cfg_runs=cfg_runs,
            width=width,
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
