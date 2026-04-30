from percolation_uart.protocol import decode_response, encode_request, PercolationRequest
from percolation_uart.transport import UartTransport
import time

# Test with manual serial to see raw bytes
test_runs = [1, 10, 100, 255, 1500]

with UartTransport(port="/dev/ttyUSB1", baudrate=115200, timeout=2.0) as ser:
    for cfg_runs in test_runs:
        # Flush any pending data
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        time.sleep(0.1)
        
        # Build and send request
        req = PercolationRequest.from_probability(
            probability=0.9999,
            cfg_seed=0x12345678,
            steps_per_run=128,
            cfg_runs=cfg_runs,
        )
        req_bytes = encode_request(req)
        
        print(f"\n--- cfg_runs={cfg_runs} (0x{cfg_runs:08X}) ---")
        print(f"Sending: {req_bytes.hex()}")
        
        ser.write(req_bytes)
        time.sleep(0.5)  # Wait for FPGA to process
        
        # Read response and decode numeric fields
        resp_bytes = ser.read(16)
        if len(resp_bytes) == 16:
            response = decode_response(resp_bytes)
            print(
                "Received: "
                f"StepCount={response.step_count} "
                f"SpanningCount={response.spanning_count} "
                f"TotalOccupied={response.total_occupied} "
                f"Status={response.status}"
            )
        else:
            print(f"ERROR: Got {len(resp_bytes)} bytes instead of 16")
        
        time.sleep(0.5)  # Delay between requests