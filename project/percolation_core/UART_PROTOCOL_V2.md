# Percolation UART Protocol v2.0 (Optimized)

## Overview
Compact binary protocol with hybrid UART + button control for debug.
- **Request:** 12 bytes (3 words)
- **Response:** 12 bytes (3 words)
- **Baud rate:** 115200 (configurable)
- **Control:** Auto-init/run on UART + optional button override

---

## Request Format (12 bytes)

| Word | Bytes | Field | Type | Range | Purpose |
|------|-------|-------|------|-------|---------|
| 0 | 0–3 | `CfgP` | uint32 | Fixed-point 0.0–1.0 | Occupation probability |
| 1 | 4–7 | `CfgSeed` | uint32 | Any | RNG seed |
| 2 | 8–11 | `GridSize[7:0]` + `CfgRuns[23:0]` | uint8 + uint24 | Grid: 8–128; Runs: 1–16777215 | Grid dimension + run count |

### Byte Layout (Word 2):
```
Byte 11 (MSB):  GridSize[7:0]    (0x08 = 8×8 grid)
Byte 10:        CfgRuns[23:16]
Byte 9:         CfgRuns[15:8]
Byte 8 (LSB):   CfgRuns[7:0]
```

### Example Request (8×8 grid, 16 runs, P=0.6, Seed=0x12345678):
```
Word 0 (CfgP):     0x9999999A    (approx 0.6 in fixed-point)
Word 1 (CfgSeed):  0x12345678
Word 2 (Grid+Runs): 0x08000010   (GridSize=8, CfgRuns=16)

Bytes (HEX):  99 99 99 9A | 12 34 56 78 | 08 00 00 10
```

---

## Response Format (12 bytes)

| Word | Bytes | Field | Purpose |
|------|-------|-------|---------|
| 0 | 0–3 | `StepCount` | Total steps executed in current run |
| 1 | 4–7 | `SpanningCount` | Number of spanning clusters found |
| 2 | 8–11 | `TotalOccupied` | Total occupied sites across all runs |

### Example Response:
```
Word 0 (StepCount):    0x000A5C7F   (steps)
Word 1 (SpanningCount): 0x00000003   (3 spanning clusters)
Word 2 (TotalOccupied): 0x0000AB12   (occupied sites total)

Bytes (HEX):  00 0A 5C 7F | 00 00 00 03 | 00 00 AB 12
```

---

## Control & Operation

### Automatic Control (UART)
- On **each valid UART message received**:
  1. Load configuration (CfgP, CfgSeed, GridSize, CfgRuns)
  2. Assert `CfgInit` for 1 cycle (reset percolation core)
  3. Assert `RunEn` for 1 cycle (start execution)
  4. Capture response from core outputs
  5. Transmit 12-byte response via UART

### Manual Control (Button Debug)
- **BTN0 (btn_init_i):** When pressed (active low), trigger `CfgInit`
- **BTN1 (btn_run_i):** When pressed (active low), trigger `RunEn`
- Synchronizers (double-flip-flop) prevent metastability
- Buttons **do not override** UART, just add independent pulses

---

## Timing

### UART Transmission Times @ 115200 baud
- **Request:** 12 bytes × 10 bits/byte ÷ 115200 baud ≈ **1.04 ms**
- **Response:** 12 bytes × 10 bits/byte ÷ 115200 baud ≈ **1.04 ms**
- **Total per request** ≈ **2.08 ms** (UART-dominated)

### Computation (typical 8×8 grid, 16 runs)
- RNG warmup: ~16 µs
- Per run (BFS): ~5–10 µs
- Total computation: ~80–160 µs
- **Overhead:** ~2 ms (UART link)

### For faster operation:
- Increase baud rate to 1 Mbps: ~100 µs per message
- Or batch multiple tests in hardware

---

## Advantages over v1.0

| Aspect | v1.0 (24-byte req) | v2.0 (12-byte req) | Improvement |
|--------|---|---|---|
| Request bytes | 24 | 12 | **50% shorter** |
| Response bytes | 20 | 12 | **40% shorter** |
| UART time per req. | 3.8 ms | 2.08 ms | **45% faster** |
| Message complexity | Word-aligned, 6 words | Packed, 3 words | **Simpler** |
| Control bits | Explicit (4B) | None (auto) | **Cleaner** |
| Debug capability | None | Buttons (BTN0/1) | **Added** |

---

## Backward Compatibility

- **Not backward compatible** with v1.0
- Update all Python test harnesses to use 12-byte messages
- Update `percolation_uart_top_tb.vhd` to new format

---

## Implementation Notes

### In `percolation_uart_top.vhd`:
- `REQ_BYTES` generic = 12
- `RSP_BYTES` generic = 12
- `btn_init_i`, `btn_run_i` ports (active low, default '1')
- Unpacking: `GridSize <= word[31:24]`, `CfgRuns <= word[23:0]` (from word 2)
- Response: Only `StepCount`, `SpanningCount`, `TotalOccupied`

### Button Synchronization:
```vhdl
btn_init_sync1 <= btn_init_i;      -- Stage 1
btn_init_sync2 <= btn_init_sync1;  -- Stage 2 (synchronized)

if btn_init_sync2 = '0' then
    core_cfg_init_s <= '1';  -- Pulse on detection
end if;
```

---

## Python Test Harness Example

```python
import serial
import struct

def send_request(ser, cfg_p, cfg_seed, grid_size, num_runs):
    """Send 12-byte request."""
    req = struct.pack('>II', cfg_p, cfg_seed)
    req += struct.pack('>I', (grid_size << 24) | num_runs)
    ser.write(req)

def recv_response(ser):
    """Receive 12-byte response."""
    rsp = ser.read(12)
    step_count, spanning_count, total_occupied = struct.unpack('>III', rsp)
    return step_count, spanning_count, total_occupied

# Example usage
ser = serial.Serial('/dev/ttyUSB0', 115200)
send_request(ser, 0x9999999A, 0x12345678, 8, 16)
steps, spanning, occupied = recv_response(ser)
print(f"Steps: {steps}, Spanning: {spanning}, Occupied: {occupied}")
```
