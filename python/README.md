# Python — Host-side Tooling

Strumenti host per il core di percolazione FPGA: validazione (BFS reference,
modello SW), benchmark via UART, e analisi dei dati (SQLite + plotting).
Il software è **puramente di servizio**: il lavoro vero è nell'FPGA.

## Struttura

```
python/
├── compare_three.py              Three-way validation (BFS / SW / HW)
├── try.py                        Quick hardware smoke test
├── bench_sweep.sh                Sweep automatico runs×steps → SQLite
├── analysis_notebook.ipynb       Analisi esplorativa + plot fisica/engineering
├── generate_tikz_replacements.py Helper per le figure della presentazione
├── output/                       Default output (plot, benchmark.sqlite3)
└── percolation_uart/             Package host
    ├── protocol.py               Pack/unpack messaggi UART (frame 16 byte)
    ├── transport.py              Link seriale (termios Linux, zero dipendenze)
    ├── client.py                 API ad alto livello (PercolationClient)
    ├── algorithms.py             BFS reference + algoritmo diretto FPGA
    ├── benchmark.py              Benchmark e sweep
    └── analysis/                 CLI + ispezione SQLite e plotting
```

## Install

```bash
cd python
pip install -e .        # installa il package e l'entry point `percolation-analyze`
```

Dipendenze: `numpy`, `matplotlib` (vedi `requirements.txt` /
`requirements-analysis.txt`).

## Workflow tipico

```bash
# 1) Three-way comparison: BFS reference vs SW FPGA model vs HW FPGA
python compare_three.py --runs 1000 --points 20 --output output/three_way.png

# 2) Quick hardware test (richiede FPGA collegata via UART)
python try.py

# 3) Benchmark sweep (raccoglie dati in output/benchmark.sqlite3)
./bench_sweep.sh

# 4) Analisi: starter plots dal DB
percolation-analyze --db output/benchmark.sqlite3 --latest --plot-dir output/analysis

# 5) Analisi FPGA engineering (pipeline, throughput, determinismo)
percolation-analyze --fpga-plot output/analysis
```

## Package `percolation_uart`

| Modulo | Scopo |
|--------|-------|
| `protocol` | Pack/unpack messaggi UART (frame 16 byte) |
| `transport` | Link seriale (Linux termios) |
| `client` | API ad alto livello (`PercolationClient`) |
| `algorithms` | BFS reference + algoritmo diretto FPGA |
| `benchmark` | Benchmark e sweep verso SQLite |
| `analysis` | CLI, ispezione SQLite e plotting (data, stats, plots) |

```python
from percolation_uart.client import PercolationClient

with PercolationClient(port="/dev/ttyUSB0") as client:
    response = client.run_from_probability(0.6, seed=0x12345678, steps_per_run=64, cfg_runs=16)
    print(response)
    # PercolationResponse(step_count=16, spanning_count=8, total_occupied=39314, spanning_occupied=57344)
```

## Analisi e grafici

`percolation-analyze` genera due gruppi di plot:

- **Starter plots** (da `--plot-dir`): dashboard, occupancy bias, spanning
  probability, core latency, front density, cluster mass, latency decomposition.
- **FPGA engineering plots** (da `--fpga-plot`, usa `benchmark-2.sqlite3`):
  `breakdown_fit.png`, `determinism_cv.png`, `latency_vs_batch.png`,
  `pipeline_efficiency.png`, `throughput_contour.png`, `throughput_invariance.png`.

I plot **di fisica** (finite-size scaling, threshold bootstrap, cluster mass)
sono generati dal notebook `analysis_notebook.ipynb` in
`output/notebook_analysis/`.

### Output prodotti

In `output/analysis/`:

- `spanning_probability.png` — transizione di fase
- `occupancy_bias.png` — accuratezza RNG
- `latency_vs_batch.png` — speedup Amdahl
- `pipeline_efficiency.png` — utilizzo pipeline
- `breakdown_fit.png` — decomposizione costi
- `finite_size_scaling.png` — scaling collapse (esponente DP ν = 1.096)
- `threshold_bootstrap.png` — stima p_c con bootstrap
- `determinism_cv.png`, `throughput_invariance.png`, `throughput_contour.png`,
  `cluster_mass_curves.png` — determinismo e throughput

> Nota: non tutti i plot generati sono usati nella presentazione finale. La
> lista completa dei plot da mostrare è in `PRESENTATION_OUTLINE.md`.

## Documentazione correlata

- `FPGA_BENCHMARK_ANALYSIS.md` — Modelli teorici (pipeline, Amdahl, decomposizione costi)
- `PRESENTATION_OUTLINE.md` — Scaletta e plot da mostrare
- `percolation_uart/README.md` — Dettagli package e API
- `../project/percolation_core/UART_PROTOCOL.md` — Protocollo UART binario
