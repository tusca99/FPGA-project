# Percolation Core

Questo e` il data-plane MVP per il progetto di site percolation.

## Stato attuale

- Il core lavora in single-clock e usa un generatore RNG dedicato per riempire la griglia.
- La direzione di connettivita` target e` Hoshen-Kopelman / Union-Find row-wise; la BFS resta solo come baseline storica di confronto.
- `Done` indica che la batch richiesta e` terminata.
- `BfsStepCount` e` cumulativo su tutte le run della richiesta, non per singola run.
- Statistiche derivate come la media delle celle occupate vanno calcolate lato host dai contatori grezzi.
- `uart_msg_loopback_top` e il percorso RNG sintetizzano gia` in tempi brevi; il debug corrente e` concentrato su `percolation_core.vhd`.
- Se un nuovo problema appare, partire dal testbench standalone del core prima di riaprire il wrapper UART.

## File chiave

- `percolation_core.vhd`: core principale, configurazione, generazione griglia e statistiche.
- `hk_row_wise.md`: documento di progetto per il modulo HK row-wise.
- `percolation_core_tb.vhd`: testbench standalone del core.
- `percolation_uart_top.vhd`: wrapper sottile UART + core.
- `percolation_uart_top_tb.vhd`: testbench end-to-end del wrapper UART.
- `UART_PROTOCOL_V2.md`: contratto request/response del control-plane.
- `percolation_core_schema.md`: schema e note di progetto.

## Direzione di evoluzione

La parte di connettivita` va portata verso Hoshen-Kopelman / Union-Find row-wise: il modulo deve restare sintetizzabile, streaming, e leggibile per riga, senza BFS globale o code sulla griglia intera.

## Doc collegate

- [README radice](../../README.md)
- [Strategia e stato del progetto](../strategia_implementazione_fpga.md)
- [UART binary scaffold](../uart_message_bin/README.md)
- [Python tools](../../python/README.md)