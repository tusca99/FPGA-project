# Percolation UART Protocol v2.5 (Compile-time width + timing statistics)

## Overview
Compact binary protocol with hybrid UART + button control for debug.
- **Request:** 16 bytes (4 words)
- **Response:** 32 bytes (8 words)
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
Byte 11 (MSB):  CfgStepsPerRun[15:8] (0x00)
Byte 10:        CfgStepsPerRun[7:0]  (0x40 = 64 rows)
Byte 9:         reserved[15:8]    (0x00)
Byte 8 (LSB):   reserved[7:0]     (0x00)
```

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

## Response Format (32 bytes)

| Word | Bytes | Field | Purpose |
|------|-------|-------|---------|
| 0 | 0–3 | `StepCount` | Number of completed runs in the current batch |
| 1 | 4–7 | `SpanningCount` | Number of spanning clusters found |
| 2 | 8–11 | `TotalOccupied` | Total occupied sites across all runs |
| 3 | 12–15 | `Status` | `0 = OK`, `1 = error/timeout` |
| 4 | 16–19 | `RngInitCycles` | Cycles from init to RNG ready |
| 5 | 20–23 | `CoreRunCycles` | Cycles spent running the frontier/core |
| 6 | 24–27 | `BatchCycles` | Total timing cycles from request to completion |
| 7 | 28–31 | `Reserved` | Set to zero for now |

### Example Response:
```
Word 0 (StepCount):      0x00000010   (16 completed runs)
Word 1 (SpanningCount):  0x00000008   (8 spanning clusters)
Word 2 (TotalOccupied):  0x000001F8   (occupied sites total)
Word 3 (Status):          0x00000000   (0 = OK)
Word 4 (RngInitCycles):   0x00000200   (example)
Word 5 (CoreRunCycles):   0x00001000   (example)
Word 6 (BatchCycles):     0x00001234   (example)
Word 7 (Reserved):        0x00000000   (reserved)

Bytes (HEX):  00 00 00 10 | 00 00 00 08 | 00 00 01 F8 | 00 00 00 00 |
              00 00 02 00 | 00 00 10 00 | 00 00 12 34 | 00 00 00 00
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
- **Response:** 32 bytes × 10 bits/byte ÷ 115200 baud ≈ **2.78 ms**
- **Total per request** ≈ **4.17 ms** (UART-dominated)

### Computation counters
- `RngInitCycles`: one-time RNG setup, from `CfgInit` to RNG ready
- `CoreRunCycles`: total cycles spent in the active frontier/core work
- `BatchCycles`: total cycles from request acceptance to completion snapshot, excluding UART TX
- `Status`: `0` on success, `1` on timeout/error

Use `BatchCycles - (RngInitCycles + CoreRunCycles)` as a rough measure of wrapper/handshake overhead.

### For faster operation:
- Increase baud rate to 1 Mbps: ~100 µs per message
- Or batch multiple tests in hardware

---

## Advantages over v1.0

| Aspect | v1.0 (24-byte req) | v2.4 (16-byte req) | Improvement |
|--------|---|---|---|
| Request bytes | 24 | 16 | **33% shorter** |
| Response bytes | 20 | 16 | **20% shorter** |
| UART time per req. | 3.8 ms | 2.78 ms | **27% faster** |
| Message complexity | Word-aligned, 6 words | Packed, 4 words | **Simpler** |
| Control bits | Explicit (4B) | None (auto) | **Cleaner** |
| Debug capability | None | Buttons (BTN0/1) | **Added** |

---

## Backward Compatibility

- **Not backward compatible** with v1.0 or the previous 12-byte response
- Update all Python test harnesses to use 16-byte responses
- Update `percolation_uart_top_tb.vhd` to new format

---

## Implementation Notes

### In `percolation_uart_top.vhd`:
 - `REQ_BYTES` generic = 16
 - `RSP_BYTES` generic = 32
 - `N_ROWS_G` generic controls the compile-time width of both the bank RNG and the core (default build: 64)
 - `btn_init_i`, `btn_run_i` ports (active low, default '1')
 - Unpacking: `CfgStepsPerRun <= word2[15:0]`, `CfgRuns <= word3`
- Completion is driven by the core `Done` trigger, not by `RunEn`
- `Status` is a 1-bit return code packed in word 3: `0` means success, `1` means error/timeout
- Response: `StepCount`, `SpanningCount`, `TotalOccupied`, `Status`, `RngInitCycles`, `CoreRunCycles`, `BatchCycles`, `Reserved`
- The internal connectivity counter has been removed from the active contract; timing counters are now the main benchmark output

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
    """Receive 32-byte response."""
    rsp = ser.read(32)
    fields = struct.unpack('>IIIIIIII', rsp)
    return fields

# Example usage
ser = serial.Serial('/dev/ttyUSB0', 115200)
send_request(ser, 0x9999999A, 0x12345678, 64, 16)
step_count, spanning, occupied, status, rng_init_cycles, core_run_cycles, batch_cycles, _reserved = recv_response(ser)
print(
    f"Steps: {step_count}, Spanning: {spanning}, Occupied: {occupied}, Status: {status}, "
    f"RNG: {rng_init_cycles}, Core: {core_run_cycles}, Batch: {batch_cycles}"
)
```
