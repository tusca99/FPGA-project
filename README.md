# FPGA Percolation Project

Acceleratore FPGA di **percolazione diretta** su Artix-7 A7-100T
(`xc7a100tcsg324-1`), clock singolo 100 MHz. Un core RTL valida la transizione
di fase della percolazione diretta (~0.605 per 64×64) tramite sweep controllati
da host via UART.

## Architettura

```
RNG Bank (64× Trivium) → Core Controller → Frontier Engine → UART
```

Tre blocchi indipendenti: generazione numeri casuali (RNG bank), calcolo di
reachability (frontier, bidirectional associative prefix scan) e
controllo/comunicazione (core + UART). Il core consuma righe dalla pipeline
quando serve, senza cicli persi in attesa.

## Key Modules

| File | Ruolo |
|------|-------|
| `project/percolation_core/percolation_core.vhd` | Controller top-level: orchestrazione RNG + frontier, accumulo statistiche |
| `project/percolation_core/percolation_bfs_frontier.vhd` | Engine reachability row-wise (bidirectional associative prefix scan) |
| `project/percolation_core/percolation_uart_top.vhd` | Wrapper UART: request/response 16 byte |
| `project/rng/rng_hybrid_64.vhd` | Bank RNG 64× Trivium, seed AES-CTR |

## Protocol (v3.0)

- **Request (16 byte)**: `[CfgP (UQ32)] [CfgSeed] [CfgStepsPerRun] [CfgRuns]`
- **Response (16 byte)**: `[StepCount] [SpanningCount] [TotalOccupied] [SpanningOccupied]`
- **Baud rate**: 115200 (link termios raw, zero dipendenze)

Dettaglio completo in `project/percolation_core/UART_PROTOCOL.md`.

## Build & Simulation

```bash
vivado -mode batch -source project/recreate_vivado_project.tcl            # rebuild
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs percolation
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs loopback
```

Progetto creato in `project/.vivado/FPGA-project/FPGA-project.xpr`.

## Validation & Analysis

```bash
# Three-way comparison: BFS reference vs SW FPGA model vs HW FPGA
python python/compare_three.py --runs 1000 --points 20 --output python/output/three_way_comparison.png

# Quick hardware test
python python/try.py

# Analisi benchmark (starter plots + FPGA engineering)
percolation-analyze --db python/output/benchmark.sqlite3 --latest --plot-dir python/output/analysis
percolation-analyze --fpga-plot python/output/analysis
```

Workflow host completo e catalogazione dei grafici in `python/README.md`.

## Results

| Risultato | Valore |
|-----------|--------|
| Occupancy bias RNG | < 0.001 |
| Frontiera vs BFS | 1000 test random, match perfetto |
| Soglia DP (64×64) | ~0.6047 ± 0.0002 (letteratura ~0.605) |
| Costo end-to-end frontiera | 4 cicli/riga (3 prefix scan + 1 handshake) |
| Pipeline efficiency | 85–95% dell'ideale |
| Universalità | Finite-size scaling, esponente DP ν = 1.096 |

## Documentation

- `project/percolation_core/` — Core, schema, algoritmo frontier, protocollo UART
- `project/rng/RNG.md` — Architettura RNG (Trivium + AES-CTR)
- `project/uart_message_bin/README.md` — Wrapper UART binari
- `python/README.md` — Strumenti Python host-side
- `python/FPGA_BENCHMARK_ANALYSIS.md` — Modelli teorici delle analisi di benchmark
- `python/PRESENTATION_OUTLINE.md` — Scaletta per la presentazione

## Status

- ✅ RNG verificato (bias < 0.001), frontier validato contro BFS, soglia ~0.6047
- ✅ Timing 100 MHz a N=64, UART end-to-end funzionante
- ✅ Benchmark caratterizzato: Amdahl, pipeline efficiency, throughput, determinismo
- ⚠️ Per N≥128 serve una versione pipelined (vedi `bfs_frontier.md`)
