# Percolation Core

Questo e` il data-plane MVP per il progetto di site percolation.

## Stato attuale

- Il core lavora in single-clock e usa un generatore RNG dedicato per riempire la griglia.
- La connettivita` e il test di spanning sono ancora basati su BFS flood-fill.
- `Done` indica che la batch richiesta e` terminata.
- `BfsStepCount` e` cumulativo su tutte le run della richiesta, non per singola run.

## File chiave

- `percolation_core.vhd`: core principale, configurazione, generazione griglia e statistiche.
- `percolation_core_tb.vhd`: testbench standalone del core.
- `percolation_uart_top.vhd`: wrapper sottile UART + core.
- `percolation_uart_top_tb.vhd`: testbench end-to-end del wrapper UART.
- `UART_PROTOCOL_V2.md`: contratto request/response del control-plane.
- `percolation_core_schema.md`: schema e note di progetto.

## Direzione di evoluzione

La parte di connettivita` e` il pezzo da migliorare per primo: il baseline BFS funziona come MVP, ma la separazione logica va tenuta aperta per una futura implementazione Hoshen-Kopelman o Union-Find.

## Doc collegate

- [README radice](../../README.md)
- [Strategia e stato del progetto](../strategia_implementazione_fpga.md)
- [UART binary scaffold](../uart_message_bin/README.md)
- [Python tools](../../python/README.md)