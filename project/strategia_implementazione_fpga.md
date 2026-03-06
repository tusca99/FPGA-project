# Site Percolation FPGA — Strategia e Implementazione

## 1. Strategia Teorica

### Modello di Percolazione
- **Site percolation 2D**: ogni sito di una griglia quadrata viene occupato con probabilità $p$.
- **Obiettivo**: identificare cluster connessi e determinare se esiste un cluster che attraversa la griglia (spanning cluster).
- **Parametri chiave**:
  - Probabilità di occupazione $p$
  - Dimensione della griglia (es. 64×64, 128×128)
  - Numero di realizzazioni/statistiche

### Estensione: Percolazione Diretta
- Possibilità di selezionare una direzione preferenziale (es. solo destra e basso), equivalente a un processo 1D con evoluzione temporale.
- Permette di esplorare modelli come Domany-Kinzel e processi di propagazione.

## 2. Architettura Hardware

### Moduli Principali
- **UART RX/TX**: ricezione parametri iniziali (config), invio risultati finali/statistiche.
- **LFSR PRNG**: generazione pseudo-casuale per occupazione dei siti.
- **Grid BRAM**: memoria per la griglia occupata.
- **FSM di controllo**: sequenza delle operazioni (ricezione config, generazione griglia, labeling, calcolo statistiche, invio output).
- **Labeling FSM**: implementazione Hoshen-Kopelman per identificazione cluster.
- **Modulo statistiche**: calcolo spanning probability, mean cluster size, largest cluster size.

### Flusso Operativo
1. Ricezione config via UART (p, dimensione griglia, seed, numero runs)
2. Generazione griglia occupata tramite LFSR e confronto con soglia $p$
3. Labeling dei cluster (Hoshen-Kopelman)
4. Calcolo statistiche
5. Invio risultati via UART
6. Ripetizione per raccolta dati statistici

## 3. Configurazione Iniziale

La configurazione viene inviata all'FPGA tramite UART e include:
- Probabilità di occupazione $p$ (rappresentata come soglia per LFSR)
- Dimensione della griglia
- Seed iniziale per LFSR
- Numero di runs/statistiche da effettuare

Esempio di struttura config:
```
p: 0.6
grid_size: 64
seed: 12345
runs: 10000
```

## 4. Output

L'FPGA restituisce via UART:
- Spanning probability (percentuale di runs con cluster che attraversa la griglia)
- Mean cluster size
- Largest cluster size (normalizzato)
- Altri parametri statistici richiesti

Esempio di output:
```
p: 0.6
spanning_prob: 0.48
mean_cluster_size: 12.3
largest_cluster_norm: 0.32
```

## 5. Implementazione VHDL — Linee Guida

- **UART**: già disponibile, va integrato con FSM di controllo.
- **LFSR**: generatore pseudo-casuale, avanzato ad ogni sito; confronto con soglia per occupazione.
- **Grid**: array in BRAM, ogni cella occupata ('1') o vuota ('0').
- **Hoshen-Kopelman**: labeling row-by-row, gestione equivalenze di etichette.
- **Statistiche**: modulo dedicato per calcolo e accumulo dei risultati.
- **Modularità**: struttura i moduli in modo che sia facile aggiungere la logica per percolazione diretta (selezione dei vicini, evoluzione temporale).

## 6. Estensione: Percolazione Diretta

- Prevedi la possibilità di selezionare i vicini solo in certe direzioni (es. destra e basso).
- Per la versione temporale, struttura la griglia come array di righe che evolvono nel tempo.
- Documenta l’interfaccia tra moduli per facilitare l’aggiunta di logica diretta.

## 7. Test e Validazione

- Confronta il threshold di percolazione con il valore analitico noto (~0.5927 per 2D).
- Usa Python o altro software per analisi e confronto dei risultati.
- Prepara testbench VHDL per ogni modulo.

---

## 8. Schema a Blocchi

```
+------------------+     +------------------+     +--------------------+
|  UART RX         | --> |  Control FSM     | --> |  UART TX           |
|  (receive config)|     |  - seed LFSR     |     |  (send results)    |
+------------------+     |  - fill grid     |     +--------------------+
                        |  - run labeling  |
                        |  - count stats   |
                        +------------------+
                                 |
                        +------------------+
                        |  Grid in BRAM    |
                        |  + Labeling FSM  |
                        +------------------+
```

---

## 9. Note Finali

- La versione base (2D isotropa) è scientificamente valida e facilmente estendibile.
- La modularità permette di aggiungere la percolazione diretta o modelli come Domany-Kinzel.
- Documenta bene le interfacce e le regole di occupazione per facilitare future estensioni.

---

Per domande o approfondimenti, puoi contattarmi o usare questo documento come base per discussioni tecniche.
