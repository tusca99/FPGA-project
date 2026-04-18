# Copilot Instructions for FPGA Project

## Architettura e Componenti Principali

- Il progetto è organizzato in due aree principali:
  - `project/uart_message_bin/`: stack UART binario a messaggi fissi per benchmark e integrazione con core applicativi
  - `project/percolation_core/`: core di site percolation da validare prima dell’integrazione UART
- Il `percolation_core` è da considerare un MVP di lavoro, non il punto finale dell’architettura:
  - separare quanto prima la generazione casuale in un modulo LFSR dedicato
  - tenere la connettività come blocco separato, partendo da BFS/flood fill e lasciando aperta l’evoluzione verso Hoshen-Kopelman / Union-Find
  - prevedere un top o wrapper sottile che colleghi configurazione, start/stop, UART e statistiche senza contenere logica algoritmica pesante
- Il top module di benchmark è `project/uart_message_bin/uart_msg_loopback_top.vhd`, che integra:
  - Generatore di baud rate (`baud_gen.vhd`)
  - Trasmettitore UART (`uart_tx.vhd`)
  - Ricevitore UART (`uart_rx.vhd`)
  - Wrapper binari a lunghezza fissa (`uart_msg_rx.vhd`, `uart_msg_tx.vhd`)
  - Loopback di benchmark con misura latenza (`uart_msg_loopback_tb.vhd`)
- Il core applicativo da discutere e validare prima dell’integrazione è `project/percolation_core/percolation_core.vhd`.
- I testbench disponibili coprono il loopback binario e il core percolation (`uart_msg_loopback_tb.vhd`, `percolation_core_tb.vhd`).

## Flusso di lavoro tipico

- **Build e sintesi:**  
  - Non sono presenti script di build automatici; la sintesi e l’implementazione vanno fatte tramite Vivado (GUI o TCL).
  - I vincoli di pin sono definiti in `costraint/pins.xdc` (adattato per Arty A7).
- **Simulazione:**  
  - Usa i testbench VHDL (`*_tb.vhd`) per simulare i moduli in Vivado o ModelSim.
  - I testbench generano clock, reset e stimoli e verificano sia la trasmissione UART sia il comportamento del core percolation.
  - Dopo un primo refactor funzionale, aggiungere quanto prima un controllo Python end-to-end via UART per validare protocollo, statistiche e benchmark prima di rifinire l’architettura interna.
- **Debug:**  
  - Prima validare `percolation_core` da solo, poi integrarlo con UART binaria.
  - Per benchmark UART usare messaggi a lunghezza fissa e confrontare il tempo baseline UART con il tempo totale del core.

## Convenzioni e pattern

- **Reset attivo basso** (`Rst = '0'`) in tutti i moduli.
- **Parametri di clock e baud rate** passati come `generic` nei moduli.
- **Sincronizzazione dei segnali di input** (pulsante, RX) tramite doppio flip-flop.
- **Gestione edge detection** per pulsanti e segnali asincroni.
- **Benchmark UART**: mantenere lunghezza messaggio, clock e baud rate costanti per sottrarre il baseline UART dal tempo del core.
- **Anti byte-loss (UART-controlled designs)**:
  - RX: `uart_rx` genera `rx_valid` “stirato`; catturare il byte su fronte di salita (edge-detect) e inserirlo nel wrapper del messaggio.
  - TX: accodare le risposte e trasmettere solo quando `tx_busy='0'`.
- **Testbench**: clock a 100 MHz, sequenze di reset e stimoli ben definite; per `percolation_core` fare prima validazione standalone e poi validazione via Python su UART appena esiste un flusso minimo end-to-end funzionante.
- **Separazione funzionale**: LFSR, connettività e wrapper/top devono restare separati per facilitare lavoro parallelo, sostituzione dell’algoritmo di connettività e benchmark puliti.

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
  - `STEP <n>` → risposta: `OK\n` (accoda `n` step nel core applicativo)
  - `METRICS` → risposta: `STEP 0x... RX_OVR 0x... TX_OVR 0x...\n`
- **Error handling**: comando sconosciuto o argomento non parsabile → `ERR\n`.

## MVP applicativo attuale (100 MHz): `percolation_core.vhd`

- Il progetto sta lavorando in single-clock a **100 MHz** (Arty A7): evitare multi-clock/CDC finché non necessario.
- Il data-plane attuale da validare è il **site percolation core** in `project/percolation_core/percolation_core.vhd`.
- Il control-plane finale sarà UART binaria a messaggi fissi per benchmark e controllo del core.
- L’obiettivo pratico attuale e` arrivare a una pipeline minima ma verificabile: generazione casuale separata, connettività funzionante, top sottile, test Python via UART e benchmark statistiche.
- Il prossimo file da introdurre dovrà essere un top applicativo sottile, per esempio `project/percolation_core/percolation_uart_top.vhd`, con responsabilità limitata a:
  - ricezione configurazione via UART
  - caricamento seed e parametri
  - start/stop/step del core
  - lettura e inoltro delle statistiche
  - nessuna logica algoritmica di griglia o connettività

**Mappa registri (via `RD/WR`, indice = 5 LSB dell’addr)**
- Config:
  - `10`: `vel0` (signed16 in `[15:0]`)
  - `11`: `vel1` (signed16 in `[15:0]`)
  - `13`: `init_pos0` (signed16 in `[15:0]`)
  - `14`: `init_pos1` (signed16 in `[15:0]`)
- Stato (read-back):
  - `2`: `step_count`
  - `5`: `pending_steps`
  - `6`: `pos0` (sign-extended)
  - `7`: `pos1` (sign-extended)
  - `8`: `dist2 = (pos1-pos0)^2`

Nota: alcune entry di stato (es. `2,5,6,7,8`) vengono sovrascritte continuamente dal core.

## Pattern consigliati per estensioni (Percolation / UART benchmark)

- **Regfile come API stabile**: mappare parametri e risultati in registri (lettura/scrittura via `RD/WR`).
- **Telemetria scalare prima, stream dopo**: iniziare con contatori/energie/acceptance rate; evitare dump massivi via UART.
- **Separazione control-plane / data-plane**:
  - Control-plane: wrapper binario UART, parametri fissi, start/stop/step del core.
  - Data-plane: `percolation_core` che aggiorna step, spanning count e statistiche.
- **Separazione per sottoblocchi**: generatore casuale, algoritmo di connettività e top di integrazione devono poter evolvere in modo indipendente.
- **Top applicativo sottile**: il top finale deve limitarsi a legare UART e core, senza ripetere parsing o logica di benchmark già esistenti nei wrapper binari.

## Flusso di validazione consigliato

1. Separare il blocco LFSR dal resto del core e validarlo in modo indipendente.
2. Validare `project/percolation_core/percolation_core.vhd` con il suo testbench standalone, mantenendo BFS come baseline iniziale.
3. Introdurre il top applicativo sottile per legare UART e core, senza aggiungere logica algoritmica nuova.
4. Integrare il core nel top UART binario solo dopo che la semantica dei segnali è chiara.
4. Aggiungere quanto prima un controllo Python via UART per verificare end-to-end funzionamento e statistiche.
5. Misurare il baseline UART con messaggi fissi e sottrarlo dal tempo totale per il benchmark.

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
- `project/percolation_core/percolation_core.vhd`: MVP corrente del core, da rifattorizzare in sottoblocchi riusabili.
- `project/percolation_core/percolation_uart_top.vhd`: futuro wrapper sottile per UART + core applicativo.
- `project/uart_message_bin/uart_msg_loopback_top.vhd`: top di benchmark binario e punto di verifica del baseline UART.

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

## Reference design paper-6 (cartella `project/code-from-paper-6`)

- `project/code-from-paper-6` contiene un **reference design** del paper 6 (Verilog + Vivado IP) con progetto `MD1.xpr`.
- È **fortemente board/device-specific** (target `xc7a200tfbg484-2`, clocking multi-dominio, Ethernet/MDIO e link GTP) e **non è un drop-in** per Arty A7-100T.
- Per l’MVP su Arty A7 si usa UART come control-plane; il reference design va considerato soprattutto come:
  - fonte di idee/pattern (es. organizzazione neighbor boxes, LUT force),
  - confronto architetturale per una futura estensione (eventualmente con board più adatte o riducendo drasticamente I/O).
- Parti realisticamente riusabili (con adattamenti): kernel/idee da `ForceNonBond.v`, `NeighborBox.v`, logica di stepping in `MDmachine.v`.
- Parti non realistiche su Arty A7 (as-is): top `MD.v`, sottosistemi `ETHlink/`, `GTP/`, `mdio/`, IP/clocking dedicati.

## Piano d’azione (stato corrente)

- Completato: UART base verificata e funzionante (TX/RX OK). Il problema osservato in precedenza era byte loss occasionale sotto carico; mitigato con RX FIFO + TX FIFO.
- Completato: stack UART binario a messaggi fissi e loopback benchmark funzionante.
- Completato: i top `uart_msg_loopback_top` e `rng` sintetizzano in tempi brevi; non sono il focus del debug corrente.
- In corso: validazione standalone di `project/percolation_core/percolation_core.vhd` con `percolation_core_tb.vhd`; il sospetto principale e` nel core, non nel wrapper UART.
- Da fare: definire il contratto tra LFSR, connettività e top sottile; introdurre presto un test Python via UART; poi integrare il core nel top UART e misurare il baseline.

---

Aggiorna queste istruzioni se aggiungi nuovi moduli o cambi il flusso di lavoro.