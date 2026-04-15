"""Serial transport helpers for the FPGA UART link."""

from __future__ import annotations

from typing import Any

try:
    import serial
except ImportError:  # pragma: no cover - exercised only when pyserial is absent
    serial = None


class UartTransport:
    """Small wrapper around a pyserial port."""

    def __init__(
        self,
        port: str,
        baudrate: int = 115200,
        timeout: float = 1.0,
        write_timeout: float = 1.0,
    ) -> None:
        if serial is None:
            raise RuntimeError("pyserial is required to use the UART transport")

        self._serial = serial.Serial(
            port=port,
            baudrate=baudrate,
            timeout=timeout,
            write_timeout=write_timeout,
        )

    @classmethod
    def from_serial(cls, serial_port: Any) -> "UartTransport":
        transport = cls.__new__(cls)
        transport._serial = serial_port
        return transport

    @property
    def serial_port(self) -> Any:
        return self._serial

    def write(self, payload: bytes) -> None:
        written = self._serial.write(payload)
        self._serial.flush()
        if written != len(payload):
            raise IOError(f"wrote {written} bytes but expected {len(payload)}")

    def read_exactly(self, size: int) -> bytes:
        data = bytearray()
        while len(data) < size:
            chunk = self._serial.read(size - len(data))
            if not chunk:
                break
            data.extend(chunk)

        if len(data) != size:
            raise TimeoutError(f"expected {size} bytes, received {len(data)}")

        return bytes(data)

    def close(self) -> None:
        self._serial.close()

    def __enter__(self) -> "UartTransport":
        return self

    def __exit__(self, exc_type, exc, exc_tb) -> None:
        self.close()
