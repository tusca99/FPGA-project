"""High-level UART client for the FPGA percolation core."""

from __future__ import annotations

from dataclasses import dataclass

from .protocol import (
    RESPONSE_BYTES,
    PercolationRequest,
    PercolationResponse,
    decode_response,
    encode_request,
    probability_to_uq32,
)
from .transport import UartTransport


@dataclass
class PercolationClient:
    """High-level API for sending a request and reading the response."""

    transport: UartTransport

    def __init__(
        self,
        port: str,
        baudrate: int = 115200,
        timeout: float = 1.0,
        write_timeout: float = 1.0,
    ) -> None:
        self.transport = UartTransport(
            port=port,
            baudrate=baudrate,
            timeout=timeout,
            write_timeout=write_timeout,
        )

    @classmethod
    def from_transport(cls, transport: UartTransport) -> "PercolationClient":
        client = cls.__new__(cls)
        client.transport = transport
        return client

    def run(self, request: PercolationRequest) -> PercolationResponse:
        self.transport.write(encode_request(request))
        payload = self.transport.read_exactly(RESPONSE_BYTES)
        return decode_response(payload)

    def run_from_probability(
        self,
        probability: float,
        seed: int,
        steps_per_run: int,
        cfg_runs: int,
    ) -> PercolationResponse:
        request = PercolationRequest.from_probability(
            probability=probability,
            cfg_seed=seed,
            steps_per_run=steps_per_run,
            cfg_runs=cfg_runs,
        )
        return self.run(request)

    def close(self) -> None:
        self.transport.close()

    def __enter__(self) -> "PercolationClient":
        return self

    def __exit__(self, exc_type, exc, exc_tb) -> None:
        self.close()


__all__ = [
    "PercolationClient",
    "probability_to_uq32",
]
