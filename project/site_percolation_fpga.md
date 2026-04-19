# Site Percolation on FPGA — Project Overview

## Can it be done in a month by two people?

Yes, absolutely — and it's a well-scoped project for two people in a month. Here is an honest assessment.

---

## Why Percolation Is a Great Fit for FPGA

Compared to the Ising model, site percolation has a key advantage: **there's no iterative dynamics**. You just:

1. Randomly occupy sites with probability *p*
2. Run a connectivity algorithm to find spanning clusters
3. Output results via UART
4. Repeat for statistics

This makes the logic cleaner and the FSM simpler. The "physics" is in the *statistics you collect*, not in a time evolution loop.

---

## Meaningful Results You Can Extract

These are scientifically significant and feasible to measure:

- **Percolation threshold** — for a 2D square lattice it's known analytically (~0.5927), so you can *verify* your hardware gives the right answer. This is a great validation benchmark.
- **Spanning probability vs p** — sweep *p* from 0 to 1 and plot the S-curve. The sharpness of the transition grows with grid size, demonstrating finite-size scaling.
- **Mean cluster size** — diverges near the critical point.
- **Largest cluster size** — normalized by N, this is the order parameter.

The FPGA's value here is **speed**: you can run thousands of independent realizations much faster than a CPU doing the same in software, which gives you better statistics near the critical point where many samples are needed.

---

## Architecture

```
+------------------+     +------------------+     +--------------------+
|  UART RX         | --> |  Control FSM     | --> |  UART TX           |
|  (receive p,     |     |  - seed LFSR     |     |  (send results:    |
|   grid size,     |     |  - fill grid     |     |   P_span, <s>, etc)|
|   # of runs)     |     |  - run labeling  |     +--------------------+
+------------------+     |  - count stats   |
                         +------------------+
                                  |
                         +------------------+
                         |  Grid in BRAM    |
                         |  + Union-Find    |
                        |  or row-wise HK FSM  |
                         +------------------+
```

### The Main Algorithmic Challenge: Connectivity

The core challenge is the connectivity check. Two approaches are available:

- **Hoshen-Kopelman algorithm** — a single-pass labeling algorithm, very suitable for hardware implementation row by row. This is probably the best choice.
- **Approccio globale** — simpler to understand but requires a stack or queue in BRAM, trickier in VHDL.

Hoshen-Kopelman is the classic choice for hardware percolation and there is academic literature on FPGA implementations you can reference.

---

## Division of Work Between Two People

| Person A | Person B |
|----------|----------|
| UART RX/TX modules + PC interface | LFSR random site generation + grid filling |
| Control FSM + parameter handling | Hoshen-Kopelman labeling FSM |
| Python analysis script | Statistics extraction (cluster sizes, spanning check) |
| Integration & testing | Testbenches & simulation |

There is enough modularity that you can work mostly in parallel after agreeing on interfaces in week 1.

---

## Realistic Monthly Plan

| Week | Goal |
|------|------|
| 1 | UART RX+TX working, agree on data protocol, LFSR generating grid, testbenches |
| 2 | Hoshen-Kopelman FSM in simulation, grid BRAM, spanning cluster detection |
| 3 | Full integration on hardware, UART-controlled parameter sweep |
| 4 | Statistical runs, Python analysis, plots, finite-size scaling, report |

---

## Honest Caveats

- **Hoshen-Kopelman complexity** — the label equivalence resolution step has some subtlety. Budget a few extra days if you haven't done graph algorithms in VHDL before.
- **Statistics near the critical point** — you'll want many thousands of runs per *p* value for smooth curves. Make sure your UART throughput and run time support this. At even modest clock speeds (e.g. 50 MHz) each run should complete in microseconds, so this is generally fine.
- **Grid size** — limited by BRAM. A 64×64 or 128×128 grid is very comfortable on Artix-7.

---

## Summary

Overall: **very doable, well-scoped, and produces results you can compare against known analytical/numerical values** — which is exactly what you want for an evaluation project.

---

## Appendix - Random Number Generator

Since FPGAs have no built-in randomness, you need to implement a pseudo-random number generator (PRNG) in hardware. The standard approach for FPGA work is a Linear Feedback Shift Register (LFSR).

### How an LFSR works
It's a shift register where the input bit is computed as an XOR of certain "tap" positions. With the right tap selection (maximal-length configuration), an n-bit LFSR cycles through all 2ⁿ−1 non-zero states before repeating. A 32-bit LFSR gives you a period of over 4 billion values — more than enough.

```
process(clk)
begin
    if rising_edge(clk) then
        lfsr <= lfsr(30 downto 0) & (lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0));
    end if;
end process;
```

The tap positions (31, 21, 1, 0) are chosen to guarantee maximal length. These are well-documented in tables for all common register widths.

---

### How you use it for percolation


For each site, you compare the LFSR output against a threshold that represents your occupation probability p:
```
loccupied <= '1' when (lfsr < p_threshold) else '0';
```

Where p_threshold is a fixed-point representation of p scaled to the LFSR's range. For example, with a 16-bit LFSR, p = 0.5 corresponds to a threshold of 32768.

---

### Practical considerations for your project
The main issue to be aware of is correlation. A single LFSR feeding sites one by one sequentially is fine — the sequential outputs are uncorrelated enough for percolation statistics. However if you ever want to fill multiple sites in parallel per clock cycle, you can't just take adjacent bits from the same LFSR as they are strongly correlated. Solutions include using multiple LFSRs with different seeds, or using a more sophisticated construction like a Tausworthe combined generator.\
For a first implementation, a single LFSR filling the grid sequentially is perfectly adequate and keeps things simple. You advance the LFSR once per site per clock cycle, which means filling a 64×64 grid takes just 4096 clock cycles — at 100 MHz that's about 40 microseconds per realization, so you can easily do tens of thousands of runs per second.\
Seeding is the other thing to think about. An LFSR always produces the same sequence from the same seed, so for reproducibility that's fine, but for independent realizations you need different seeds between runs. A simple approach is to use your UART input to supply an initial seed, or to increment the seed by a fixed offset between runs.