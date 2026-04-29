# Percolation UART Protocol v3.0 (Simplified: no timing counters)

## Overview
Compact binary protocol with UART request/response. Button ports stay only for board compatibility.
- **Request:** 16 bytes (4 words)
- **Response:** 16 bytes (4 words)
- **Baud rate:** 115200 (configurable)
- **Control:** Auto-init/run on UART

---

## Request Format (16 bytes)

| Word | Bytes | Field | Type | Range | Purpose |
|------|-------|-------|------|-------|---------|
| 0 | 0–3 | `CfgP` | uint32 | Fixed-point 0.0–1.0 | Occupation probability |
| 1 | 4–7 | `CfgSeed` | uint32 | Any | RNG seed |
| 2 | 8–11 | `CfgStepsPerRun` | uint32 | Requested rows, 1–4294967295 | 32-bit on wire, top consumes the low `CFG_STEPS_BITS_G` bits |
| 3 | 12–15 | `CfgRuns` | uint32 | Runs: 1–4294967295 | Batch size |

Word 2 is transmitted as a full 32-bit big-endian word.
`percolation_uart_top.vhd` keeps only the lower 16 bits after unpacking, so the
wire encoding for 64 steps is `00 00 00 40`, which becomes `0x00000040` on the
bus and `0x0040` inside the core wrapper.

The row width is compile-time fixed by the top-level generic `N_ROWS_G` (default build: 64). UART only carries the variable part: how many rows/steps to process.

So the live contract is:

- width: fixed at `N_ROWS_G`
- requested height: `CfgStepsPerRun`
- effective height in RTL: `CfgStepsPerRun` (with a minimum of 1)
- step-field width from the top: `CFG_STEPS_BITS_G` (default 32)

If you ask for more than `N_ROWS_G` rows, the request is not expanded in width. The core keeps the strip width fixed and extends the run in the vertical direction.

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
| 3 | 12–15 | `Status` | `0 = OK`, `1 = error` |

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
    1. Load configuration (`CfgP`, `CfgSeed`, `CfgStepsPerRun`, `CfgRuns`)
    2. Assert `CfgInit` for 1 cycle
    3. Assert `RunEn` while waiting for `Done`
    4. Capture response from core outputs when the requested run count completes
    5. Transmit 16-byte response via UART

### Manual Control (Button Debug)
The slim top keeps button ports for board compatibility, but the default wrapper
does not use them in the UART request/response flow.

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
 - `CFG_STEPS_BITS_G` generic controls the width of `CfgStepsPerRun` from the top (default build: 32)
 - `CfgStepsPerRun` is runtime-configurable and sets the run height directly
 - `btn_init_i`, `btn_run_i` ports kept for board compatibility, but the slim wrapper ignores them
- Unpacking: `CfgStepsPerRun <= word2[CFG_STEPS_BITS_G-1:0]`, `CfgRuns <= word3[31:0]`
- Completion is driven by the core `Done` trigger, not by `RunEn`
- `Status` is a 1-bit return code in word 3: `0` means success, `1` means error
- Response: `StepCount`, `SpanningCount`, `TotalOccupied`, `Status`
- Timing measurement delegated to Python/simulation (RTL counters removed for simplicity)

The default slim wrapper does not implement a timeout path or button override.

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
