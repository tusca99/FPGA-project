# Percolation Core

Questo e` il data-plane MVP per il progetto di site percolation.

## Stato attuale

- Il core lavora in single-clock e usa un generatore RNG dedicato per riempire la griglia.
- La direzione di connettivita` ha due varianti tenute separate: frontier row-wise a due righe come base principale e HK row-wise ridotto come alternativa per cluster statistics.
- La variante frontier e` piu` adatta se la chiusura orizzontale della riga viene implementata come dilatazione bitmask a 7 stage fissi, non come catena combinatoria da 128 celle.
- Il backend principale non materializza tutta la griglia: mantiene solo riga corrente e riga precedente.
- La forma runtime del problema e` una striscia a larghezza fissa `N_ROWS_G` e altezza richiesta da `CfgStepsPerRun`.
- La larghezza del campo `CfgStepsPerRun` si controlla dal top con il generic `CFG_STEPS_BITS_G` (default 32).
- `Done` indica che la batch richiesta e` terminata.
- `ConnStepCount` e` cumulativo su tutte le run della richiesta, non per singola run.
- Statistiche derivate come la media delle celle occupate vanno calcolate lato host dai contatori grezzi.
- `uart_msg_loopback_top` e il percorso RNG sintetizzano gia` in tempi brevi; il debug corrente e` concentrato su `percolation_core.vhd`.
- Se un nuovo problema appare, partire dal testbench standalone del core prima di riaprire il wrapper UART.

## File chiave

- `percolation_core.vhd`: core principale, configurazione, generazione griglia e statistiche.
- `bfs_frontier.md`: documento di progetto per il backend frontier row-wise / wavefront a due righe.
- `hk_row_wise.md`: documento di progetto per il modulo HK row-wise ridotto.
- `percolation_core_tb.vhd`: testbench standalone del core.
- `percolation_uart_top.vhd`: wrapper sottile UART + core.
- `percolation_uart_top_tb.vhd`: testbench end-to-end del wrapper UART.
- `UART_PROTOCOL_V2.md`: contratto request/response del control-plane.
- `percolation_core_schema.md`: schema e note di progetto.

## Direzione di evoluzione

La parte di connettivita` ha due strade documentate:

- Frontier row-wise / wavefront a due righe per reachability e percolazione semplice
- HK row-wise ridotto per statistiche di cluster e label di componente

In entrambi i casi il modulo deve restare sintetizzabile, streaming e con interfaccia stabile verso il core applicativo.

Limite importante del path attuale:

- `CfgStepsPerRun` estende solo l'altezza della run, non la larghezza
- il core mantiene la larghezza fissa `N_ROWS_G`
- per un caso quadrato, imposta `CfgStepsPerRun = N_ROWS_G`

Per la frontier row-wise, il compromesso migliore su FPGA e` evitare sia il loop cella-per-cella completamente combinatorio sia una queue globale. Una dilatazione bitmask a pochi stage o una piccola pipeline danno la stessa semantica con timing piu` facile da chiudere.

## Doc collegate

- [README radice](../../README.md)
- [Strategia e stato del progetto](../strategia_implementazione_fpga.md)
- [UART binary scaffold](../uart_message_bin/README.md)
- [Python tools](../../python/README.md)