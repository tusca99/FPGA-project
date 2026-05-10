"""Serial transport helpers for the FPGA UART link."""

from __future__ import annotations

import os
import select
import termios
import time
from typing import Any


_BAUD_MAP = {
    9600: getattr(termios, "B9600", None),
    19200: getattr(termios, "B19200", None),
    38400: getattr(termios, "B38400", None),
    57600: getattr(termios, "B57600", None),
    115200: getattr(termios, "B115200", None),
    230400: getattr(termios, "B230400", None),
    460800: getattr(termios, "B460800", None),
    500000: getattr(termios, "B500000", None),
    576000: getattr(termios, "B576000", None),
    921600: getattr(termios, "B921600", None),
    1000000: getattr(termios, "B1000000", None),
}


def _baud_constant(baudrate: int) -> int:
    baud_constant = _BAUD_MAP.get(baudrate)
    if baud_constant is None:
        raise ValueError(f"unsupported baudrate: {baudrate}")
    return baud_constant


class UartTransport:
    """Small UART wrapper built on Linux termios and file descriptors."""

    def __init__(
        self,
        port: str,
        baudrate: int = 115200,
        timeout: float = 1.0,
        write_timeout: float = 1.0,
    ) -> None:
        self._timeout = timeout
        self._write_timeout = write_timeout
        self._fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
        self._closed = False
        self._previous_attrs = termios.tcgetattr(self._fd)
        self._configure_port(baudrate)

    @classmethod
    def from_serial(cls, serial_port: Any) -> "UartTransport":
        transport = cls.__new__(cls)
        transport._fd = serial_port
        transport._timeout = 1.0
        transport._write_timeout = 1.0
        transport._previous_attrs = None
        transport._closed = False
        return transport

    @property
    def serial_port(self) -> Any:
        return self._fd

    def _configure_port(self, baudrate: int) -> None:
        attrs = termios.tcgetattr(self._fd)
        speed = _baud_constant(baudrate)

        attrs[0] &= ~(termios.BRKINT | termios.ICRNL | termios.INPCK | termios.ISTRIP | termios.IXON | termios.IXOFF | termios.IXANY)
        attrs[1] &= ~termios.OPOST
        attrs[2] &= ~(termios.CSIZE | termios.PARENB | termios.CSTOPB)
        attrs[2] |= termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] &= ~(termios.ECHO | termios.ECHONL | termios.ICANON | termios.ISIG | termios.IEXTEN)
        attrs[4] = speed
        attrs[5] = speed
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 0

        termios.tcsetattr(self._fd, termios.TCSANOW, attrs)

    def write(self, payload: bytes) -> None:
        deadline = time.monotonic() + self._write_timeout if self._write_timeout is not None else None
        total_written = 0
        view = memoryview(payload)

        while total_written < len(payload):
            if deadline is not None and time.monotonic() > deadline:
                raise TimeoutError(f"expected to write {len(payload)} bytes, wrote {total_written}")

            written = os.write(self._fd, view[total_written:])
            if written <= 0:
                raise IOError("write returned no data")
            total_written += written

        termios.tcdrain(self._fd)

    def flush(self) -> None:
        termios.tcdrain(self._fd)

    def reset_input_buffer(self) -> None:
        termios.tcflush(self._fd, termios.TCIFLUSH)

    def reset_output_buffer(self) -> None:
        termios.tcflush(self._fd, termios.TCOFLUSH)

    def read(self, size: int) -> bytes:
        return self.read_exactly(size)

    def read_exactly(self, size: int) -> bytes:
        data = bytearray()
        deadline = time.monotonic() + self._timeout if self._timeout is not None else None

        while len(data) < size:
            if deadline is not None:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
            else:
                remaining = None

            ready, _, _ = select.select([self._fd], [], [], remaining)
            if not ready:
                continue

            chunk = os.read(self._fd, size - len(data))
            if not chunk:
                continue
            data.extend(chunk)

        if len(data) != size:
            raise TimeoutError(f"expected {size} bytes, received {len(data)}")

        return bytes(data)

    def close(self) -> None:
        if self._closed:
            return

        if self._previous_attrs is not None:
            try:
                termios.tcsetattr(self._fd, termios.TCSANOW, self._previous_attrs)
            except Exception:
                pass

        os.close(self._fd)
        self._closed = True

    def __enter__(self) -> "UartTransport":
        return self

    def __exit__(self, exc_type, exc, exc_tb) -> None:
        self.close()
