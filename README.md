# FPGA Percolation Project

Acceleratore FPGA di **percolazione diretta** (directed percolation) su Artix-7
A7-100T (`xc7a100tcsg324-1`), clock singolo 100 MHz. Un core RTL valida la
transizione di fase della percolazione diretta (~0.605 per 64×64) tramite sweep
controllati da host via UART.

## Architettura

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│   RNG Bank  │────▶│   Core      │────▶│   Frontier      │
│ (64 Trivium)│     │ (controller)│     │ (reachability)  │
└─────────────┘     └─────────────┘     └─────────────────┘
       │                   │                     │
       │ site_open[0..63]  │ row_bits            │ ChunkOpen
       │ (every cycle)     │ (when frontier      │ (when ChunkValid)
       │                   │  ready)             │
       ▼                   ▼                     ▼
   Random bits         Occupancy row         Reachability mask
   compared to        sent to frontier      computed via prefix
   threshold CfgP                            scan (4 cyc/row E2E)
```

Tre blocchi indipendenti e ben separati: generazione numeri casuali
(RNG bank), calcolo di reachability (frontier) e controllo/comunicazione
(core + UART). Il core consuma righe dalla pipeline quando serve, senza
cicli persi in attesa.

## Key Modules

| File | Ruolo |
|------|-------|
| `project/percolation_core/percolation_core.vhd` | Controller top-level: orchestrazione RNG + frontier, accumulo statistiche |
| `project/percolation_core/percolation_bfs_frontier.vhd` | Engine reachability row-wise (bidirectional associative prefix scan) |
| `project/percolation_core/percolation_uart_top.vhd` | Wrapper UART: request/response 16 byte |
| `project/rng/rng_hybrid_64.vhd` | Bank RNG 64× Trivium, seed AES-CTR |

## Protocol (v3.0)

- **Request (16 byte)**: `[CfgP (4B, UQ32)] [CfgSeed (4B)] [CfgStepsPerRun (4B)] [CfgRuns (4B)]`
- **Response (16 byte)**: `[StepCount (4B)] [SpanningCount (4B)] [TotalOccupied (4B)] [SpanningOccupied (4B)]`
- **Baud rate**: 115200 (nessuna dipendenza host: link termios raw)

Vedi `project/percolation_core/UART_PROTOCOL.md` per il dettaglio completo.

## Build & Simulation

```bash
# Ricrea il progetto Vivado
cd /path/to/FPGA-project
vivado -mode batch -source project/recreate_vivado_project.tcl

# Target opzionali
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

# Analisi benchmark SQLite (starter plots)
percolation-analyze --db python/output/benchmark.sqlite3 --latest --plot-dir python/output/analysis

# Analisi FPGA engineering (pipeline, throughput, determinismo)
percolation-analyze --fpga-plot python/output/analysis
```

Vedi `python/README.md` per il workflow host completo e la catalogazione dei
grafici prodotti.

## Results (stato attuale)

| Risultato | Valore |
|-----------|--------|
| Occupancy bias RNG | < 0.001 |
| Frontiera vs BFS | 1000 test random, match perfetto |
| Soglia DP (64×64) | ~0.6047 ± 0.0002 (letteratura ~0.605) |
| Costo end-to-end frontiera | 4 cicli/riga (3 prefix scan + 1 handshake) |
| Pipeline efficiency | 85–95% dell'ideale |
| Classificazione universalità | Finite-size scaling, esponente DP ν = 1.096 |

### Grafici prodotti

I plot principali sono generati da notebook e CLI in `python/output/`:

- **Fisica della percolazione** (`python/output/analysis/`, `python/output/notebook_analysis/physics/`):
  `spanning_probability.png`, `occupancy_bias.png`, `cluster_mass_curves.png`,
  `finite_size_scaling.png`, `threshold_bootstrap.png`
- **FPGA engineering** (`python/output/analysis/`, `python/output/notebook_analysis/fpga_engineering/`):
  `latency_vs_batch.png`, `pipeline_efficiency.png`, `breakdown_fit.png`,
  `determinism_cv.png`, `throughput_invariance.png`, `throughput_contour.png`
- **Sweep cross-check** (`python/output/notebook_analysis/sweep_comparison/`):
  `sweep_comparison.png`

## Documentation

- `project/percolation_core/README.md` — Dettagli del core e backend di connectivity
- `project/percolation_core/percolation_core_schema.md` — Schema concettuale
- `project/percolation_core/bfs_frontier.md` — Algoritmo frontier (prefix scan)
- `project/percolation_core/UART_PROTOCOL.md` — Protocollo UART binario
- `project/rng/RNG.md` — Architettura RNG (Trivium + AES-CTR)
- `project/uart_message_bin/README.md` — Wrapper UART binari
- `python/README.md` — Strumenti Python host-side
- `python/FPGA_BENCHMARK_ANALYSIS.md` — Modelli teorici delle analisi di benchmark
- `python/PRESENTATION_OUTLINE.md` — Scaletta per la presentazione

## Status

- ✅ RNG verificato: occupancy coincide con p (bias < 0.001)
- ✅ Algoritmo frontier: prefix scan validato contro BFS (1000 test random)
- ✅ Soglia: ~0.6047 per percolazione diretta su 64×64 (atteso ~0.605)
- ✅ Timing: prefix scan rispetta 100 MHz a N=64
- ✅ UART end-to-end: request/response 16 byte funzionanti
- ✅ Benchmark caratterizzato: Amdahl, pipeline efficiency, throughput, determinismo
- ⚠️  Per N≥128 serve una versione pipelined (vedi `bfs_frontier.md`)
