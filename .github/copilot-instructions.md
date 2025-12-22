# Copilot Instructions for UART FPGA Project

## Architettura e Componenti Principali

- Il progetto è organizzato in due macro-directory:
  - `uart/uart_modular/`: implementazione modulare di UART (con `baud_gen`, `uart_tx`, `uart_rx`, testbench)
  - `uart/uart_single/`: implementazione UART monolitica (esempio didattico)
- Il top module principale è `uart_top.vhd`, che integra:
  - Generatore di baud rate (`baud_gen.vhd`)
  - Trasmettitore UART (`uart_tx.vhd`)
  - Ricevitore UART (`uart_rx.vhd`)
  - Gestione pulsante e LED per demo/test
- I testbench sono forniti per i moduli principali (`uart_tx_tb.vhd`, `uart_mod_tx_tb.vhd`).

## Flusso di lavoro tipico

- **Build e sintesi:**  
  - Non sono presenti script di build automatici; la sintesi e l’implementazione vanno fatte tramite Vivado (GUI o TCL).
  - I vincoli di pin sono definiti in `costraint/pins.xdc` (adattato per Arty A7).
- **Simulazione:**  
  - Usa i testbench VHDL (`*_tb.vhd`) per simulare i moduli in Vivado o ModelSim.
  - I testbench generano clock, reset e stimoli (es. pressione pulsante) e verificano la trasmissione UART.
- **Debug:**  
  - Il LED viene acceso per 1 secondo alla ricezione del carattere 'a' via UART.
  - Il pulsante invia il carattere 'a' tramite UART TX.

## Convenzioni e pattern

- **Reset attivo basso** (`Rst = '0'`) in tutti i moduli.
- **Parametri di clock e baud rate** passati come `generic` nei moduli.
- **Sincronizzazione dei segnali di input** (pulsante, RX) tramite doppio flip-flop.
- **Gestione edge detection** per pulsanti e segnali asincroni.
- **Pipeline di trasmissione**: le richieste di TX sono accodate in un latch 1-deep per evitare perdita di eventi.
- **Testbench**: clock a 100 MHz, sequenze di reset e stimoli ben definite.

## File chiave

- `uart/uart_modular/uart_top.vhd`: top module, punto di partenza per estensioni.
- `uart/uart_modular/baud_gen.vhd`: generatore di baud rate parametrico.
- `uart/uart_modular/uart_tx.vhd` / `uart_rx.vhd`: moduli trasmettitore/ricevitore.
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

---

Aggiorna queste istruzioni se aggiungi nuovi moduli o cambi il flusso di lavoro.