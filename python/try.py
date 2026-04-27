from percolation_uart.protocol import encode_request, PercolationRequest
import struct
import time
import serial

# Test with manual serial to see raw bytes
test_runs = [1, 10, 100, 255]

with serial.Serial(port="/dev/ttyUSB1", baudrate=9600, timeout=2.0) as ser:
    for cfg_runs in test_runs:
        # Flush any pending data
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        time.sleep(0.1)
        
        # Build and send request
        req = PercolationRequest.from_probability(
            probability=0.9,
            cfg_seed=0x12345678,
            steps_per_run=100,
            cfg_runs=cfg_runs,
        )
        req_bytes = encode_request(req)
        
        print(f"\n--- cfg_runs={cfg_runs} (0x{cfg_runs:08X}) ---")
        print(f"Sending: {req_bytes.hex()}")
        
        ser.write(req_bytes)
        time.sleep(0.5)  # Wait for FPGA to process
        
        # Read response
        resp_bytes = ser.read(16)
        if len(resp_bytes) == 16:
            print(f"Received: {resp_bytes.hex()}")
            words = struct.unpack('>IIII', resp_bytes)
            print(f"  StepCount=0x{words[0]:08X} ({words[0]})")
            print(f"  SpanningCount=0x{words[1]:08X}")
            print(f"  TotalOccupied=0x{words[2]:08X}")
        else:
            print(f"ERROR: Got {len(resp_bytes)} bytes instead of 16: {resp_bytes.hex()}")
        
        time.sleep(0.5)  # Delay between requests