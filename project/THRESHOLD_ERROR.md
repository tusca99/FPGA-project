# Threshold Error: Sharp Spanning Transition

## Issue
RNG threshold comparison produces **anomalous spanning behavior** at certain probability values.

## Test Results (256 runs, 64×64 grid)

| p (occupancy) | Expected spanning | Actual spanning | Error |
|---|---|---|---|
| 0.1 | <1% | 0% | ✓ Correct |
| 0.2 | <1% | 0% | ✓ Correct |
| 0.3 | <2% | 14% (37/256) | ✗ **FALSE POSITIVES** |
| 0.5 | 0% (below critical) | 100% (256/256) | ✗ **ALL SPANNING** |
| 0.6 | 60% (critical) | 100% (256/256) | ≈ High but biased |

## Problem Pattern
- **p ≤ 0.2**: Correct (0% spanning below critical)
- **p = 0.3-0.6**: Broken (spanning detects even when threshold not met)
- **Sharp transition** between 0.2→0.3 suggests bit-width or comparison logic issue

## Root Cause Suspect
Likely **RNG threshold comparison** in `rng_hybrid_64.vhd` or connectivity frontier:
- Sites marked "open" when should be "closed"
- Frontier spanning detected false positives
- Comparison `site_random < threshold` inverted or bit-sized incorrectly

## Next Debug Steps
1. Run standalone RNG testbench with p=0.1 to p=0.6
2. Verify `site_open` output rate matches expected occupancy
3. Check threshold comparison logic in RNG (UQ32 format)
4. Trace frontier connectivity with debug p values

## Files Affected
- `percolation_core/percolation_core.vhd` (RNG instantiation)
- `rng/zz_rng_hybrid_64.vhd` (threshold logic)
- `percolation_core/percolation_bfs_frontier.vhd` (spanning detection)
