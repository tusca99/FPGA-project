# AES-128 + Trivium Hybrid RNG

## Overview

Hardware RNG for the percolation core. Parameterized by `N_ROWS_G` at compile time (default 64).
Generates `N_ROWS_G` pseudo-random 32-bit values per clock cycle — one per column.

**Architecture**: AES-128 CTR for seeding + `N_ROWS_G` independent Trivium stream ciphers for generation.

## Block Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                      AES-128 CTR Core                        │
│  At init:                                                    │
│  Generate 2 × N_ROWS_G consecutive 128-bit blocks          │
│  Block 2i   → Key_i  (bits 79:0)   for Trivium_i            │
│  Block 2i+1 → IV_i   (bits 79:0)   for Trivium_i            │
│  i = 0 .. N_ROWS_G - 1                                       │
└─────────────────────────┬────────────────────────────────────┘
                          │ 64 × (80-bit Key + 80-bit IV)
                          ▼
┌──────────────────────────────────────────────────────────────┐
│              N_ROWS_G × Trivium Cores  (unrolled ×32)        │
│                                                              │
│   Trivium_0  ──► 32 bits/cycle  →  Row 0,  all columns      │
│   Trivium_1  ──► 32 bits/cycle  →  Row 1,  all columns      │
│   ...                                                        │
│   Trivium_{N_ROWS_G-1} ──► 32 bits/cycle  →  Row N_ROWS_G-1 │
│                                                              │
│   Full row generated in 1 cycle                             │
└─────────────────────────┬────────────────────────────────────┘
                          │ N_ROWS_G × 32-bit words per cycle
                          ▼
┌──────────────────────────────────────────────────────────────┐
│                  N_ROWS_G × Threshold Comparators            │
│                                                              │
│  word_i  vs  threshold (CfgP, UQ32)  →  site_open bit       │
│  Result: N_ROWS_G-bit vector per cycle                       │
└──────────────────────────────────────────────────────────────┘
```

## Seeding Procedure

Each Trivium instance requires 80 bits of Key and 80 bits of IV.
Two AES-CTR blocks per generator provide full entropy:

```
For generator i (i = 0 .. N_ROWS_G-1):
  Key_i = AES_CTR(master_key, counter = 2i  )[79:0]
  IV_i  = AES_CTR(master_key, counter = 2i+1)[79:0]
```

**Master key derivation** from `CfgSeed`:
```vhdl
key(31:0)   = seed
key(63:32)  = ~seed
key(95:64)  = seed xor 0x9E3779B9
key(127:96) = seed + 0x243F6A88
```

### Seeding Timing

| Phase | Duration | Notes |
|-------|----------|-------|
| AES block generation | 2 × N_ROWS_G AES calls | Sequential init phase |
| Trivium warm-up | 1152 cycles | Output gated; discard all bits |
| Normal operation | Until reset | 32 bits/cycle per generator |

## Trivium Core — Unrolled ×32

Trivium stream cipher from eSTREAM portfolio. Internal state: 288 bits across three shift registers.
Unrolled by 32: computes 32 feedback iterations combinationally per clock cycle.

### Key Properties

| Property | Value |
|----------|-------|
| Internal state | 288 flip-flops per instance |
| Key size | 80 bits |
| IV size | 80 bits |
| Output period | ≥ 2¹⁴⁴ |
| Warm-up cycles | 1152 (mandatory) |

## Correlation Analysis

- **Spatial (between rows)**: Each Trivium has distinct AES-derived Key+IV → statistically independent
- **Spatial (within row)**: Consecutive 32-bit words from same Trivium have zero exploitable autocorrelation
- **Temporal (across steps)**: Keystream period ≥ 2¹⁴⁴, no repetition at realistic depths
- **Seed correlation**: AES-CTR sequential seeds are jointly independent by PRP security proof

## Resource Estimate — Artix-7 (N_ROWS_G = 64)

| Resource | 64 × Trivium | AES-128 | Total | xc7a100t Budget |
|----------|--------------|---------|-------|-----------------|
| Flip-Flops | ~18,500 | ~400 | ~18,900 | 126,800 ✓ |
| LUTs | ~13,000 | ~1,000 | ~14,000 | 101,400 ✓ |

## Interface

```vhdl
entity rng_hybrid_64 is
    generic (N_ROWS_G : positive := 64);
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        master_key : in  std_logic_vector(127 downto 0);
        run_tag    : in  std_logic_vector(31 downto 0);
        threshold  : in  std_logic_vector(31 downto 0); -- UQ32
        words_out  : out word_array_t(0 to N_ROWS_G-1);
        valid_mask : out std_logic_vector(N_ROWS_G-1 downto 0);
        site_open  : out flag_array_t(0 to N_ROWS_G-1);
        all_valid  : out std_logic;
        busy       : out std_logic
    );
end entity;
```

## MVP Policy

- Single init seeding at reset (no runtime reseed)
- Sufficient for simulations below 1M iterations
- Future: re-enable AES-CTR re-keying without changing row bank

## References

- De Cannière, Preneel — *Trivium* (eSTREAM, 2005)
- NIST SP 800-22 — Statistical Test Suite
- NIST FIPS 197 — AES

## Doc Links

- [Core README](../percolation_core/README.md) — How the core uses the RNG
- [Core Schema](../percolation_core/percolation_core_schema.md) — Data flow
- [BFS Frontier](../percolation_core/bfs_frontier.md) — Reachability engine
