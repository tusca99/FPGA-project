# AES-128 + Trivium Hybrid RNG for FPGA Percolation Simulation

## Overview

This document describes the hardware RNG architecture currently used by the percolation RTL. The design is parameterized by `N_ROWS` at compile time; in the current build `N_ROWS = 128`, so the bank exposes 128 parallel Trivium lanes and 128 32-bit words per cycle. The goal is to generate a statistically independent 32-bit random word per site per percolation step, with low resource usage and high throughput.

The chosen solution combines:
- **AES-128 in CTR mode** as a cryptographic entropy source for seeding
- **`N_ROWS` independent Trivium stream cipher cores** (one per lane) for high-throughput pseudorandom generation

---

## Architecture

### High-Level Block Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                      AES-128 CTR Core                        │
│                                                              │
│  At init:                                                    │
│  Generate 2 × N_ROWS consecutive 128-bit blocks              │
│  Block 2i   → Key_i  (bits 79:0)   for Trivium_i            │
│  Block 2i+1 → IV_i   (bits 79:0)   for Trivium_i            │
│  i = 0 .. N_ROWS - 1                                         │
└─────────────────────────┬────────────────────────────────────┘
                          │ 64 × (80-bit Key + 80-bit IV)
                          ▼
┌──────────────────────────────────────────────────────────────┐
│              `N_ROWS` × Trivium Cores  (unrolled ×32)        │
│                                                              │
│   Trivium_0  ──► 32 bits/cycle  →  Row 0,  all columns      │
│   Trivium_1  ──► 32 bits/cycle  →  Row 1,  all columns      │
│   ...                                                        │
│   Trivium_{N_ROWS-1} ──► 32 bits/cycle  →  Row N_ROWS-1     │
│                                                              │
│   Full grid filled in ceil(grid_size / N_ROWS) clock cycles │
└─────────────────────────┬────────────────────────────────────┘
                          │ 64 × 32-bit words per cycle
                          ▼
┌──────────────────────────────────────────────────────────────┐
│                  64 × Threshold Comparators                  │
│                                                              │
│  word_i  vs  threshold  →  site_open bit                     │
│  Accumulate 64-bit column result vector per cycle            │
└──────────────────────────────────────────────────────────────┘
```

---

## Seeding Procedure (Option 1 — Two AES Blocks Per Generator)

Each Trivium instance requires exactly **80 bits of Key** and **80 bits of IV**.  
To provide full entropy in both fields, two independent AES-CTR output blocks are consumed per generator:

```
For generator i  (i = 0 .. 63):

  Key_i = AES_CTR(master_key, counter = 2i  )[79:0]
  IV_i  = AES_CTR(master_key, counter = 2i+1)[79:0]
```

This requires **2 × N_ROWS AES evaluations** per initialization. In the current RTL, with `N_ROWS = 128`, that means **256 AES evaluations**.  
The upper 48 bits of each 128-bit AES block are discarded.

### Why Two Blocks?

A single 128-bit AES block can only provide 128 bits of output. Splitting it as `80-bit Key || 48-bit IV` leaves the IV 32 bits short. Zero-padding those 32 bits would reduce IV entropy and introduce a fixed structure into Trivium's initial state. Using two blocks avoids this entirely and gives full 80-bit entropy to both Key and IV.

### Seeding Timing

| Phase             | Duration                        | Notes                          |
|-------------------|---------------------------------|--------------------------------|
| AES block generation | `2 × N_ROWS` AES calls       | AES core reused, sequential init phase |
| Trivium warm-up   | **1152 cycles** (mandatory)     | Output gated; discard all bits |
| Normal operation  | Until reset / next init sequence | 32 bits/cycle per generator    |

> **Critical:** Trivium's internal state is not fully mixed until 1152 clock cycles after key/IV loading. The output enable signal must be held low during this warm-up period.

---

## Trivium Core — Unrolled ×32

Trivium is a stream cipher from the eSTREAM hardware portfolio. Its internal state consists of three shift registers totalling **288 bits**. Unrolling by 32 means computing 32 feedback iterations combinationally per clock cycle to produce a 32-bit output word.

### Internal State Initialization

```
State bits   0 –  79  ← Key   (80 bits)
State bits  80 –  92  ← 0x000 (13 bits, zero-padded)
State bits  93 – 172  ← IV    (80 bits)
State bits 173 – 177  ← 0x00  (5 bits, zero-padded)
State bits 178 – 287  ← 0x000 (110 bits, zero-padded)
```

### Key Properties

| Property              | Value                          |
|-----------------------|--------------------------------|
| Internal state        | 288 flip-flops                 |
| Key size              | 80 bits                        |
| IV size               | 80 bits                        |
| Output period         | ≥ 2¹⁴⁴ (proven lower bound)   |
| Statistical quality   | Passes all NIST SP 800-22 tests |
| Warm-up cycles        | 1152 (must discard output)     |

---

## Correlation Analysis

### Spatial Correlation — Between Rows

Each Trivium instance is seeded with a **distinct AES-derived Key+IV pair**. Since AES output at different counter values is computationally indistinguishable from independent uniform random, the keystreams are **statistically independent**. No inter-row correlation is introduced by the seeding procedure.

### Spatial Correlation — Within a Row (Between Columns)

Within a single Trivium instance, consecutive 32-bit output words are produced by advancing the same nonlinear state. Trivium's nonlinear feedback ensures **zero exploitable autocorrelation** at any lag. Columns j and j+1 within the same row are uncorrelated despite being drawn from the same stream.

### Temporal Correlation — Across Percolation Steps

Site (i, j) at step k consumes Trivium_i output word at position:

```
pos(k, i, j) = k × 64 + j
```

With a keystream period ≥ 2¹⁴⁴, no repetition occurs at any realistic simulation depth. Temporal autocorrelation is negligible.

### Seed Correlation — Between Generators

AES-CTR seeds are generated sequentially:

```
Seed_0 = AES(master_key, 0),  AES(master_key, 1)
Seed_1 = AES(master_key, 2),  AES(master_key, 3)
...
```

These seeds are individually uniform and jointly independent by the pseudorandom permutation security proof of AES in CTR mode. No correlation leaks through the seeding process.

---

## Resource Estimate — Artix-7

### Per Trivium Core (unrolled ×32)

| Resource       | Count         |
|----------------|---------------|
| Flip-Flops     | ~288          |
| LUTs           | ~180 – 220    |

### Full System (64 Trivium + AES)

| Resource       | 64 × Trivium  | AES-128 Core  | Total          | xc7a100t Budget |
|----------------|---------------|---------------|----------------|-----------------|
| Flip-Flops     | ~18,500       | ~400          | ~18,900        | 126,800 ✓       |
| LUTs           | ~13,000       | ~1,000        | ~14,000        | 101,400 ✓       |

Ample margin remains on the xc7a100t for percolation logic (union-find, cluster labeling, output buffering).

### Comparison with Alternative Approaches

| Scheme                  | Bits/site | Grid fill latency | Flip-Flop cost | Fits xc7a100t |
|-------------------------|-----------|-------------------|----------------|---------------|
| 4096 × 32-bit LFSR array | 32 bits  | 1 cycle           | ~131,000       | ✗ (exceeds)  |
| Single Trivium, serial   | 1 bit    | 128 cycles        | ~700           | ✓            |
| **64 Trivium (1/row)**  | **32 bits** | **64 cycles**   | **~18,900**    | **✓**        |

---

## MVP Policy

Runtime reseed is disabled in the current MVP.

- The hybrid RNG performs a single init seeding sequence at reset.
- This is enough for simulations below 1M iterations.
- If a future benchmark needs re-keying, the same AES-CTR seeding path can be re-enabled without changing the row bank.

---

## Implementation Checklist

- [ ] AES-128 CTR core generates `2 × N_ROWS` blocks at init
- [ ] Block `2i` bits `[79:0]` → `Key_i` for Trivium instance i
- [ ] Block `2i+1` bits `[79:0]` → `IV_i` for Trivium instance i
- [ ] Upper 48 bits of each AES block discarded
- [ ] Trivium output enable gated low for 1152 cycles after the init key/IV load
- [ ] 1152-cycle warm-up counter resets at init
- [ ] All `N_ROWS` Trivium instances loaded in parallel from stored seed registers
- [ ] 32-bit output word per Trivium compared against threshold register each cycle
- [ ] No runtime reseed in the current MVP
- [ ] Optional run tag can still be used to diversify the initial seed per simulation run

---

## References

- De Cannière, C., Preneel, B. — *Trivium: A Stream Cipher Construction Inspired by Block Cipher Design Principles* (eSTREAM, 2005)
- NIST SP 800-22 — *A Statistical Test Suite for Random and Pseudorandom Number Generators*
- NIST FIPS 197 — *Advanced Encryption Standard (AES)*
- Daemen, J., Rijmen, V. — *The Design of Rijndael* (AES specification)