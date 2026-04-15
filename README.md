# FPGA Project

Repository FPGA per validare il core di site percolation e il control-plane UART binario a messaggi fissi.

## Struttura

- [project/percolation_core/README.md](project/percolation_core/README.md): core di percolation, testbench standalone e roadmap della connettivita`
- [project/uart_message_bin/README.md](project/uart_message_bin/README.md): wrapper UART binari, top di loopback e testbench
- [project/constraint/](project/constraint/): vincoli di pin, incluso `pins.xdc` per il mapping delle porte fisiche della board, ad esempio UART
- [project/strategia_implementazione_fpga.md](project/strategia_implementazione_fpga.md): panoramica generale e stato del progetto
- `Papers/`: materiale di riferimento

## Flusso consigliato

Il progetto Vivado va ricreato quando necessario, invece di modificare a mano i file generati.

Lo script di ricostruzione vive in [project/recreate_vivado_project.tcl](project/recreate_vivado_project.tcl) e prende i sorgenti direttamente dalle cartelle della repo.

Comando principale:

```bash
cd /path/to/FPGA-project
vivado -mode batch -source project/recreate_vivado_project.tcl
```

Modalita` opzionali se vuoi cambiare il focus senza toccare i file a mano:

```bash
cd /path/to/FPGA-project
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs percolation
```

```bash
cd /path/to/FPGA-project
vivado -mode batch -source project/recreate_vivado_project.tcl -tclargs loopback
```

Il progetto viene creato in `project/.vivado/FPGA-project/FPGA-project.xpr`.

Per aprirlo in GUI:

```bash
vivado project/.vivado/FPGA-project/FPGA-project.xpr
```

Se vuoi rilanciare la simulazione dopo una ricostruzione, apri il progetto salvato e usa il top di simulazione corrispondente al modo scelto: `uart_msg_loopback_tb` per il loopback, `percolation_core_tb` per il core.

## File generati da ignorare

Questi artefatti sono generati da Vivado e non vanno versionati:

- `project/FPGA-project.cache/`
- `project/FPGA-project.hw/`
- `project/FPGA-project.ip_user_files/`
- `project/FPGA-project.sim/`
- `project/FPGA-project.runs/`
- `project/.vivado/`

## Note operative

- Il README di `project/uart_message_bin/` resta dedicato solo al sottosistema UART binario.
- Prima validare `percolation_core` standalone, poi integrarlo dietro il top UART.
- Se Vivado segnala problemi di simulazione, il primo check da fare e` che il progetto sia stato creato da [project/recreate_vivado_project.tcl](project/recreate_vivado_project.tcl) e non da un progetto in-memory temporaneo.

## Strumenti Python

Per il client UART, il riferimento Python puro e i benchmark, vedi [python/README.md](python/README.md).
Se vuoi il bootstrap rapido per un collega, usa [python/bootstrap.sh](python/bootstrap.sh).
Per il contratto request/response del core vedi [project/percolation_core/UART_PROTOCOL_V2.md](project/percolation_core/UART_PROTOCOL_V2.md).