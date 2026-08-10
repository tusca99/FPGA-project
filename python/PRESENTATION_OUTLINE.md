# FPGA Percolation Project — Presentazione

## Outline / Scaletta

Pubblico: professori di microcontrollori/FPGA, background HEP/CERN.
Zero conoscenza di percolazione → serve introduzione teorica chiara.
Focus su **FPGA engineering** (architettura, pipeline, timing), Python è secondario.

---

### 1. Introduzione — Cos'è la percolazione (5 min)
- **Idea fisica**: un fluido filtra attraverso un mezzo poroso. Siti aperti (pori) vs chiusi.
- **Modello**: griglia 2D, ogni sito è aperto con probabilità p, chiuso con probabilità 1-p.
- **Domanda**: esiste un percorso continuo da top a bottom? → *spanning cluster*
- **Transizione di fase**: esiste un p_c critico — sotto p_c solo cluster locali, sopra p_c emerge un cluster spanning.
- **Percolazione diretta (DP)**: il fluido si muove solo verso il basso (downward). Classe di universalità diversa dalla percolazione standard (isotropa).
- **Perché su FPGA**: simulazione Monte Carlo massiva — servono tante run indipendenti per stimare p_c con precisione. FPGA = parallelismo massiccio a basso consumo.

### 2. Architettura del Sistema (5 min)
- **Diagramma a blocchi**:
  ```
  RNG Bank (64× Trivium) → Core Controller → Frontier Engine → UART
  ```
- **Flusso**: RNG genera 64 bit/cycle → Core streama righe alla Frontier → Frontier calcola reachability → Core accumula statistiche → UART spedisce risultato
- **Separazione netta**: generazione numeri casuali, calcolo di reachability, controllo, comunicazione — ognuno indipendente

### 3. RNG Bank — Generazione Numeri Casuali (4 min)
- **64 Trivium stream cipher in parallelo**: uno per colonna della griglia
- **AES-CTR seeding**: 128 blocchi × 12 cicli = 1536 cicli di warmup (una tantum)
- **Produzione**: 64 bit casuali per ciclo di clock — un'intera riga della griglia in 1 ciclo
- **Confronto con threshold**: ogni bit confrontato con CfgP (fixed-point UQ32) → flag site_open

### 4. Frontier Engine — Algoritmo di Reachability (6 min)
- **Problema**: data una griglia di open/closed, determinare se c'è un percorso top→bottom
- **Soluzione row-wise**:
  - Row 0: seed = open (tutti i siti aperti in prima riga sono punti di partenza)
  - Row N: seed = open AND previous_reach (propagazione verticale — solo se c'è un sito aperto *sotto* uno raggiungibile)
  - **Chiusura orizzontale**: iterative ±1 neighbor expansion — un sito aperto diventa raggiungibile se il vicino sinistro o destro lo è
- **Implementazione VHDL**: bidirectional associative prefix scan
  - Pipeline a 3 stadi (RUN_READY → RUN_COMPUTE → RUN_SAVE)
  - Esattezza: converge allo stesso risultato del BFS (1000 test random)
  - Costo end-to-end: ~4 × steps cicli per run (3 frontier + 1 handshake registrato; es: 64 righe → ~259 cicli)
- **Perché non BFS classico**: BFS su FPGA richiederebbe bufferizzare tutta la griglia in BRAM. Row-wise usa solo 2 righe alla volta.

### 5. Core Controller e Macchina a Stati (3 min)
- **Stati**: IDLE → ARM → RUN → DONE
- **Batch processing**: CfgRuns run eseguite in sequenza senza intervento host
- **Accumulatori**: StepCount, SpanningCount, TotalOccupied, SpanningOccupied (32 bit)
- **Pipeline**: RNG corre continuamente, Core consuma righe quando serve — nessun ciclo perso in attesa

### 6. Protocollo UART (2 min)
- **Request (16 byte)**: CfgP (UQ32) | CfgSeed | CfgStepsPerRun | CfgRuns
- **Response (16 byte)**: StepCount | SpanningCount | TotalOccupied | SpanningOccupied
- **Baud rate**: 115200 (wire time ~2.78 ms per round-trip)
- **Niente pyserial**: implementazione Linux termios raw — zero dipendenze

### 7. Stack Software — Solo l'essenziale (2 min)
- **`percolation_uart` package**: protocol, transport, client, algorithms, benchmark, analysis
- **`compare_three.py`**: confronto BFS (undirected) vs SW FPGA (directed) vs HW FPGA
- **`bench_sweep.sh`**: sweep automatico runs × steps → SQLite
- **Nota**: il software è puramente di servizio — validazione e raccolta dati. Il vero lavoro è nell'FPGA.

### 8. Validazione — Correttezza (4 min)
- **Occupancy bias**: < 0.001 (RNG accurato, generazione uniforme)
- **Three-way comparison**: BFS (undirected) e SW FPGA (directed) concordano con HW FPGA
- **Threshold DP**: ~0.6047 per 64×64 (letteratura: ~0.605)
- **Frontier vs BFS**: 1000 test random, match perfetto

### 9. Risultati — Prestazioni FPGA (5 min)
- **Latency vs Batch (Amdahl)**: overhead UART fisso ~2.78 ms ammortizzato con batch grandi. Speedup segue legge di Amdahl: f_serial ≈ 0.2-0.4
- **Breakdown fit**: separazione costo fisso (UART + host) vs marginale (core). Asintoto ~3 cicli/riga — matcha il modello teorico
- **Pipeline efficiency**: 85-95% dell'ideale. Per-step cost: ~3.5 cicli/step misurati vs 3 ideali
- **Grid-height invariance**: throughput in celle/s costante al variare di steps — la pipeline domina, non la dimensione della griglia
- **Determinismo**: CV < 1% su 5 ripetizioni — FPGA puro è deterministico, il piccolo jitter è solo host/USB

### 10. Risultati — Fisica della Percolazione Diretta (4 min)
- **Finite-size scaling**: collapse delle curve P_span(p, N) per N=64,128,180 usando esponente DP ν=1.096. Tutte le curve collassano su una master curve → conferma classe di universalità DP
- **Threshold bootstrap**: regressione logistica binomiale + 2000 bootstrap campioni → p_c = 0.6047 ± 0.0002 (95% CI)
- **Binder cumulant**: crossing point U=2/3 conferma p_c indipendentemente dalla forma funzionale

### 11. Conclusioni (2 min)
- **Risultato**: acceleratore FPGA per percolazione diretta funzionante, validato, caratterizzato
- **Throughput**: ~10⁶ celle/s a 100 MHz, 10-100× vs software
- **Pipeline**: 3 stadi, 3 cicli/riga, efficiency > 85%
- **Threshold**: p_c = 0.6047 ± 0.0002, consistente con letteratura DP

---

## Slide consigliate (~12-14 slide)

1. **Titolo**: FPGA Percolation Accelerator
2. **Cos'è la percolazione** (griglia, p, spanning, transizione di fase)
3. **Percolazione diretta vs isotropa** (downward, classe DP)
4. **Architettura del Sistema** (diagramma a blocchi)
5. **RNG Bank** (64 Trivium, AES seeding, 64 bit/cycle)
6. **Frontier Engine** (algoritmo row-wise, prefix scan)
7. **Core Controller** (macchina a stati, batch processing)
8. **Protocollo UART** (16-byte frame)
9. **Validazione** (occupancy bias, three-way comparison)
10. **Prestazioni — Latency & Pipeline** (Amdahl, breakdown fit, efficiency)
11. **Prestazioni — Throughput & Determinismo** (grid-height invariance, CV)
12. **Fisica — Finite-Size Scaling** (scaling collapse plot)
13. **Fisica — Threshold Bootstrap** (bootstrap histogram)
14. **Conclusioni** (risultati chiave, numeri)

---

## Plot da mostrare (già generati in `python/output/analysis/`)

- `spanning_probability.png` — transizione di fase
- `occupancy_bias.png` — accuratezza RNG
- `latency_vs_batch.png` — Amdahl speedup
- `pipeline_efficiency.png` — utilizzo pipeline
- `breakdown_fit.png` — decomposizione costi
- `finite_size_scaling.png` — scaling collapse
- `threshold_bootstrap.png` — stima p_c con bootstrap
- `dashboard.png` — panoramica (opzionale, se serve vista d'insieme)
- `pipeline_efficiency.png` — utilizzo pipeline
- `finite_size_scaling.png` — scaling collapse
- `threshold_bootstrap.png` — stima p_c con bootstrap
- `breakdown_fit.png` — decomposizione costi
