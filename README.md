# FPGA Project

Repository FPGA per validare il core di site percolation e il control-plane UART binario a messaggi fissi.

## Struttura

- `project/percolation_core/`: core di percolation e testbench standalone
- `project/uart_message_bin/`: wrapper UART binari, top di loopback e testbench
- `project/constraint/`: vincoli di pin, incluso `pins.xdc` per il mapping delle porte fisiche della board, ad esempio UART
- `Papers/`: materiale di riferimento

## Flusso consigliato

Il progetto Vivado va ricreato quando necessario, invece di modificare a mano i file generati.

Comando principale:

```bash
cd project
vivado -mode batch -source recreate_vivado_project.tcl
```

Modalita` opzionali se vuoi cambiare il focus senza toccare i file a mano:

```bash
cd project
vivado -mode batch -source recreate_vivado_project.tcl -tclargs percolation
```

```bash
cd project
vivado -mode batch -source recreate_vivado_project.tcl -tclargs loopback
```

Il progetto viene creato in `.vivado/FPGA-project/FPGA-project.xpr`.

Per aprirlo in GUI:

```bash
vivado project/.vivado/FPGA-project/FPGA-project.xpr
```

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