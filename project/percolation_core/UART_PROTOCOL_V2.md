# Percolation UART Protocol v3.0 (Simplified: no timing counters)

## Overview
Compact binary protocol with hybrid UART + button control for debug.
- **Request:** 16 bytes (4 words)
- **Response:** 16 bytes (4 words)
- **Baud rate:** 115200 (configurable)
- **Control:** Auto-init/run on UART + optional button override

---

## Request Format (16 bytes)

| Word | Bytes | Field | Type | Range | Purpose |
|------|-------|-------|------|-------|---------|
| 0 | 0–3 | `CfgP` | uint32 | Fixed-point 0.0–1.0 | Occupation probability |
| 1 | 4–7 | `CfgSeed` | uint32 | Any | RNG seed |
| 2 | 8–11 | `CfgStepsPerRun[15:0]` | uint16 | Rows: 1–128 | Steps / rows per run |
| 3 | 12–15 | `CfgRuns` | uint32 | Runs: 1–4294967295 | Batch size |

### Byte Layout (Word 2):
```
Byte 11 (MSB):  reserved[31:24]      (0x00)
Byte 10:        reserved[23:16]      (0x00)
Byte 9:         reserved[15:8]       (0x00)
Byte 8 (LSB):   CfgStepsPerRun[7:0]  (0x40 = 64 rows)
```

In the current RTL, word 2 is still transmitted as a full 32-bit big-endian word.
Only the lower 16 bits are consumed by `percolation_uart_top.vhd`, so the wire
encoding for 64 steps is `00 00 00 40`, which becomes `0x00000040` at the word
level and `0x0040` after the top-level truncation.

The row width is compile-time fixed by the top-level generic `N_ROWS_G` (default build: 64). UART only carries the variable part: how many rows/steps to process.

### Example Request (64-wide build, 64 steps, 16 runs, P=0.6, Seed=0x12345678):
```
Word 0 (CfgP):     0x9999999A    (approx 0.6 in fixed-point)
Word 1 (CfgSeed):  0x12345678
Word 2 (Steps):    0x00000040   (CfgStepsPerRun=64)
Word 3 (CfgRuns):  0x00000010   (CfgRuns=16)

Bytes (HEX):  99 99 99 9A | 12 34 56 78 | 00 00 00 40 | 00 00 00 10
```

---

## Response Format (16 bytes)

| Word | Bytes | Field | Purpose |
|------|-------|-------|---------|
| 0 | 0–3 | `StepCount` | Number of completed runs in the current batch |
| 1 | 4–7 | `SpanningCount` | Number of spanning clusters found |
| 2 | 8–11 | `TotalOccupied` | Total occupied sites across all runs |
| 3 | 12–15 | `Status` | `0 = OK`, `1 = error/timeout` |

### Example Response:
```
Word 0 (StepCount):      0x00000010   (16 completed runs)
Word 1 (SpanningCount):  0x00000008   (8 spanning clusters)
Word 2 (TotalOccupied):  0x000001F8   (occupied sites total)
Word 3 (Status):          0x00000000   (0 = OK)

Bytes (HEX):  00 00 00 10 | 00 00 00 08 | 00 00 01 F8 | 00 00 00 00
```

---

## Control & Operation

### Automatic Control (UART)
- On **each valid UART message received**:
    1. Load configuration (CfgP, CfgSeed, CfgStepsPerRun, CfgRuns)
  2. Assert `CfgInit` for 1 cycle (reset percolation core)
  3. Assert `RunEn` while waiting for the core completion trigger (`Done`) (start execution and keep it running)
    4. Capture response from core outputs when the requested run count completes
    5. Transmit 16-byte response via UART

- A timeout safety net is present in the wrapper; if the core does not finish in time, the current snapshot is transmitted for debug instead of stalling forever.

### Manual Control (Button Debug)
- **BTN0 (btn_init_i):** When pressed (active low), trigger `CfgInit`
- **BTN1 (btn_run_i):** When pressed (active low), trigger `RunEn`
- Synchronizers (double-flip-flop) prevent metastability
- Buttons **do not override** UART, just add independent pulses

---

## Timing

### UART Transmission Times @ 115200 baud
- **Request:** 16 bytes × 10 bits/byte ÷ 115200 baud ≈ **1.39 ms**
- **Response:** 16 bytes × 10 bits/byte ÷ 115200 baud ≈ **1.39 ms**
- **Total per request** ≈ **2.78 ms** (UART-dominated)

### Computation measurement
For precise timing, use Python wall-clock measurement or simulation waveform analysis. RTL counters removed to avoid gate complexity.

### For faster operation:
- Increase baud rate to 1 Mbps: ~100 µs per message
- Or batch multiple tests in hardware

---

## Evolution

| Aspect | v2.x (32-byte resp) | v3.0 (16-byte resp) | Improvement |
|--------|---|---|---|
| Response bytes | 32 | 16 | **50% smaller** |
| UART time per resp. | 2.78 ms | 1.39 ms | **50% faster** |
| Total UART latency | 4.17 ms | 2.78 ms | **33% faster** |
| Timing measurement | RTL counters (unreliable) | Python/sim (reliable) | **Better** |
| Complexity | Complex gates (per-phase) | Removed (cleaner) | **Simpler** |

---

## Backward Compatibility

- **Not backward compatible** with v2.x (reduced response size)
- Update all Python test harnesses to expect 16-byte responses
- Update `percolation_uart_top_tb.vhd` to new format

---

## Implementation Notes

### In `percolation_uart_top.vhd`:
 - `REQ_BYTES` generic = 16
 - `RSP_BYTES` generic = 16
 - `N_ROWS_G` generic controls the compile-time width of both the bank RNG and the core (default build: 64)
 - `btn_init_i`, `btn_run_i` ports (active low, default '1')
- Unpacking: `CfgStepsPerRun <= word2[15:0]`, `CfgRuns <= word3[31:0]`
- Completion is driven by the core `Done` trigger, not by `RunEn`
- `Status` is a 1-bit return code in word 3: `0` means success, `1` means error/timeout
- Response: `StepCount`, `SpanningCount`, `TotalOccupied`, `Status`
- Timing measurement delegated to Python/simulation (RTL counters removed for simplicity)

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

def send_request(ser, cfg_p, cfg_seed, steps_per_run, num_runs):
    """Send 16-byte request."""
    req = struct.pack('>II', cfg_p, cfg_seed)
    req += struct.pack('>I', steps_per_run)
    req += struct.pack('>I', num_runs)
    ser.write(req)

def recv_response(ser):
    """Receive 16-byte response."""
    rsp = ser.read(16)
    fields = struct.unpack('>IIII', rsp)
    return fields

# Example usage
ser = serial.Serial('/dev/ttyUSB0', 115200)
send_request(ser, 0x9999999A, 0x12345678, 64, 16)
step_count, spanning, occupied, status = recv_response(ser)
print(
    f"Steps: {step_count}, Spanning: {spanning}, Occupied: {occupied}, Status: {status}"
)
```
