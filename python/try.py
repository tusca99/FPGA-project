from time import monotonic

from percolation_uart.protocol import PercolationRequest, encode_request
from percolation_uart.transport import UartTransport


PORT = "/dev/ttyUSB1"
BAUDRATE = 115200
TIMEOUT = 0.2


request = PercolationRequest.from_probability(
    probability=0.6,
    cfg_seed=0x12345678,
    steps_per_run=1,
    cfg_runs=1,
)
payload = encode_request(request)

print(f"TX {len(payload)} bytes: {payload.hex(' ')}")

with UartTransport(port=PORT, baudrate=BAUDRATE, timeout=TIMEOUT, write_timeout=TIMEOUT) as transport:
    transport.write(payload)

    serial_port = transport.serial_port
    received = bytearray()
    silence_deadline = monotonic() + .1
    end_deadline = monotonic() + .2

    while monotonic() < end_deadline:
        waiting = serial_port.in_waiting
        chunk = serial_port.read(waiting or 1)
        if chunk:
            received.extend(chunk)
            silence_deadline = monotonic()
            print(f"RX chunk {len(chunk)} bytes: {chunk.hex(' ')}")
            continue

        if received and monotonic() >= silence_deadline:
            break

    print(f"RX total {len(received)} bytes: {received.hex(' ')}")