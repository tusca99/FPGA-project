# Copilot Instructions for UART FPGA Project

## Architettura e Componenti Principali

- Il progetto è organizzato in due macro-directory:
  - `uart/uart_modular/`: implementazione modulare di UART (con `baud_gen`, `uart_tx`, `uart_rx`, testbench)
  - `uart/uart_single/`: implementazione UART monolitica (esempio didattico)
- Il top module principale è `uart_top.vhd`, che integra:
  - Generatore di baud rate (`baud_gen.vhd`)
  - Trasmettitore UART (`uart_tx.vhd`)
  - Ricevitore UART (`uart_rx.vhd`)
  - FIFO RX/TX a byte per non perdere dati (`byte_fifo.vhd`)
  - Parser comandi ASCII newline-terminated (`ascii_cmd_parser.vhd`)
  - Regfile/telemetria base (stub applicativo) e gestione LED come “activity indicator”
- I testbench sono forniti per i moduli principali (`uart_tx_tb.vhd`, `uart_mod_tx_tb.vhd`).

## Flusso di lavoro tipico

- **Build e sintesi:**  
  - Non sono presenti script di build automatici; la sintesi e l’implementazione vanno fatte tramite Vivado (GUI o TCL).
  - I vincoli di pin sono definiti in `costraint/pins.xdc` (adattato per Arty A7).
- **Simulazione:**  
  - Usa i testbench VHDL (`*_tb.vhd`) per simulare i moduli in Vivado o ModelSim.
  - I testbench generano clock, reset e stimoli (es. pressione pulsante) e verificano la trasmissione UART.
- **Debug:**  
 - **Debug:**  
  - Il LED pulsa brevemente quando viene decodificato un comando valido via UART.
  - La demo attuale è “UART command/response” (non più il loop su carattere 'a').

## Convenzioni e pattern

- **Reset attivo basso** (`Rst = '0'`) in tutti i moduli.
- **Parametri di clock e baud rate** passati come `generic` nei moduli.
- **Sincronizzazione dei segnali di input** (pulsante, RX) tramite doppio flip-flop.
- **Gestione edge detection** per pulsanti e segnali asincroni.
- **Pipeline di trasmissione**: usare backpressure tramite `tx_busy` e buffering (FIFO TX) per evitare perdita di byte.
- **Anti byte-loss (UART-controlled designs)**:
  - RX: `uart_rx` genera `rx_valid` “stirato”; catturare il byte su fronte di salita (edge-detect) e inserirlo in FIFO RX.
  - TX: accodare le risposte in FIFO TX e trasmettere solo quando `tx_busy='0'`.
- **Testbench**: clock a 100 MHz, sequenze di reset e stimoli ben definite.

## Protocollo UART ASCII (MVP)

- **Formato comando**: una riga ASCII terminata da `\n` (eventuale `\r` ignorato).
- **Case-insensitive**: i comandi sono accettati in maiuscolo/minuscolo.
- **Numeri**: supportati in decimale (`123`) o esadecimale con prefisso `0x` (`0x1A2B`).
- **Comandi supportati (implementati)**:
  - `PING` → risposta: `PONG\n`
  - `HELP` → risposta: lista comandi
  - `RD <addr>` → risposta: `RD 0xAAAAAAAA 0xVVVVVVVV\n` (addr mascherato su 32 bit; regfile indicizzato sui 5 LSB)
  - `WR <addr> <val>` → risposta: `OK\n`
  - `START` / `STOP` → risposta: `OK\n`
  - `STEP <n>` → risposta: `OK\n` (stub: incrementa il contatore step)
  - `METRICS` → risposta: `STEP 0x... RX_OVR 0x... TX_OVR 0x...\n`
- **Error handling**: comando sconosciuto o argomento non parsabile → `ERR\n`.

## Pattern consigliati per estensioni (MD / Ising / PT)

- **Regfile come API stabile**: mappare parametri e risultati in registri (lettura/scrittura via `RD/WR`).
- **Telemetria scalare prima, stream dopo**: iniziare con contatori/energie/acceptance rate; evitare dump massivi via UART.
- **Separazione control-plane / data-plane**:
  - Control-plane: parser ASCII, regfile, comandi di avvio/stop/step.
  - Data-plane: core applicativo (MD/Ising) che aggiorna registri/metriche.

## Testbench (raccomandazioni)

- Aggiungere TB che testa round-trip “a livello byte” (senza dover simulare ogni bit UART) stimolando FIFO RX e verificando FIFO TX/risposte.
- Includere test negativi: linea troppo lunga, argomenti invalidi, comandi sconosciuti.

## File chiave

- `uart/uart_modular/uart_top.vhd`: top module, punto di partenza per estensioni.
- `uart/uart_modular/baud_gen.vhd`: generatore di baud rate parametrico.
- `uart/uart_modular/uart_tx.vhd` / `uart_rx.vhd`: moduli trasmettitore/ricevitore.
- `uart/uart_modular/byte_fifo.vhd`: FIFO byte per RX/TX (anti byte-loss).
- `uart/uart_modular/ascii_cmd_parser.vhd`: parser comandi ASCII (newline-terminated).
- `uart/uart_modular/uart_tx_tb.vhd`, `uart_mod_tx_tb.vhd`: testbench di riferimento.
- `uart/costraint/pins.xdc`: vincoli di pin per la board Arty A7.

## Esempi di pattern

- **Aggiunta di un nuovo modulo**:  
  - Definire l’entity e l’architecture in VHDL.
  - Instanziare nel top module e collegare segnali tramite port map.
- **Estensione protocollo UART**:  
  - Modificare `uart_tx`/`uart_rx` per supportare frame diversi (es. 9 bit, parità).
- **Debug hardware**:  
  - Usare LED o segnali di output per visualizzare eventi (es. ricezione carattere specifico).

## Analisi e Sperimentazione Paper

- I paper analizzati in `project/useful_papers/` e riassunti in `project/papers.md` possono ispirare estensioni hardware (es. acceleratori MCMC, Ising, Monte Carlo) integrabili tramite UART.
- Documentare ogni nuovo modulo ispirato ai paper, specificando: input/output, parametri configurabili via UART, e pattern di testbench.

## Piano d’azione (stato corrente)

- Completato: UART base verificata e funzionante (TX/RX OK). Il problema osservato in precedenza era byte loss occasionale sotto carico; mitigato con RX FIFO + TX FIFO.
- Completato: RX FIFO + parser ASCII + TX FIFO + integrazione in `uart_top.vhd`.
- In corso: testbench dedicato al round-trip dei comandi (stimolo byte-level, verifica risposte).
- Da fare: scegliere MVP applicativo (Paper 6: MD minimale, o Paper 3: Ising/PT) e sostituire lo stub “metrics/step” con il core.

---

Aggiorna queste istruzioni se aggiungi nuovi moduli o cambi il flusso di lavoro.