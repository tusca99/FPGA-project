# Percolation UART Protocol v3.0

## Overview

Compact binary protocol with UART request/response.
- **Request:** 16 bytes (4 words)
- **Response:** 16 bytes (4 words)
- **Baud rate:** 115200 (configurable)
- **Control:** Auto-init/run on UART message receipt

---

## Request Format (16 bytes)

| Word | Bytes | Field | Type | Range | Purpose |
|------|-------|-------|------|-------|---------|
| 0 | 0–3 | `CfgP` | uint32 | Fixed-point 0.0–1.0 (UQ32) | Occupation probability |
| 1 | 4–7 | `CfgSeed` | uint32 | Any | RNG seed |
| 2 | 8–11 | `CfgStepsPerRun` | uint32 | 1–65535 | Rows per run (lower 16 bits used) |
| 3 | 12–15 | `CfgRuns` | uint32 | 1–4294967295 | Batch size |

**Note:** `CfgStepsPerRun` travels as a full 32-bit big-endian word. The core uses only the lower 16 bits. For 64 steps, encode as `00 00 00 40`.

**Grid shape:**
- Width: fixed at compile-time by `N_ROWS_G` (default 64)
- Height: `CfgStepsPerRun` (runtime)

### Example Request (64×64, 16 runs, P=0.6, Seed=0x12345678)

```
Word 0 (CfgP):     0x9999999A    (approx 0.6 in UQ32)
Word 1 (CfgSeed):  0x12345678
Word 2 (Steps):    0x00000040   (64 steps)
Word 3 (CfgRuns):  0x00000010   (16 runs)

Bytes (HEX):  99 99 99 9A | 12 34 56 78 | 00 00 00 40 | 00 00 00 10
```

---

## Response Format (16 bytes)

| Word | Bytes | Field | Purpose |
|------|-------|-------|---------|
| 0 | 0–3 | `StepCount` | Completed runs in batch |
| 1 | 4–7 | `SpanningCount` | Runs with spanning cluster |
| 2 | 8–11 | `TotalOccupied` | Total occupied sites across all runs |
| 3 | 12–15 | `SpanningOccupied` | Total reachable sites in spanning runs |

### Example Response

```
Word 0 (StepCount):       0x00000010   (16 runs)
Word 1 (SpanningCount):   0x00000008   (8 spanning)
Word 2 (TotalOccupied):   0x00009992   (occupied sites)
Word 3 (SpanningOccupied):0x0000E000   (reachable in spanning runs)

Bytes (HEX):  00 00 00 10 | 00 00 00 08 | 00 00 99 92 | 00 00 E0 00
```

---

## Control & Operation

### Automatic Control (UART)

On each valid UART message received:
1. Load configuration (`CfgP`, `CfgSeed`, `CfgStepsPerRun`, `CfgRuns`)
2. Assert `CfgInit` for 1 cycle
3. Assert `RunEn` while waiting for `Done`
4. Capture response from core outputs when run count completes
5. Transmit 16-byte response via UART

### State Machine (percolation_uart_top.vhd)

```
IDLE ──req_valid──▶ WAIT_CLEAR ──done='0'──▶ RUN_WAIT ──done='1'──▶ TX_PULSE ──▶ TX_WAIT ──▶ IDLE
```

---

## Timing

### UART Transmission @ 115200 baud
- **Request:** 16 bytes × 10 bits/byte ÷ 115200 ≈ **1.39 ms**
- **Response:** 16 bytes × 10 bits/byte ÷ 115200 ≈ **1.39 ms**
- **Total per request** ≈ **2.78 ms** (UART-dominated)

### Computation Time
- Per run (64×64): ~259 cycles @ 100 MHz = **2.59 µs** (4 cyc/row × 64 + 3)
- Batch of 16 runs: ~16 × 259 + RNG warmup ≈ **~5700 cycles = 57 µs**
- UART wire time still dominates single-request wall time at 115200 baud

### For Faster Operation
- Increase baud rate to 1 Mbps: ~100 µs per message
- Batch multiple tests in hardware (increase `CfgRuns`)

---

## Doc Links

- [Core README](README.md) — Core module documentation
- [Core Schema](percolation_core_schema.md) — Architecture overview
- [Python Tools](../../python/README.md) — Host-side client and validation
