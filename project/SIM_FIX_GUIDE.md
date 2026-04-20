# How to Fix and Run Simulations

Questa e` la guida rapida di recovery per Vivado. Per la matrice completa di compilazione, i testbench e i dettagli sulle dipendenze vedi [project/TEST_GUIDE.md](project/TEST_GUIDE.md).

## Quick recovery

1. Fai una copia del TCL corrente se vuoi tenere un backup:
```bash
cd /path/to/FPGA-project
cp project/recreate_vivado_project.tcl project/recreate_vivado_project.tcl.backup
```

2. Ricrea il progetto con lo script canonico:
```bash
VIVADO_MAX_GB=16 project/run_vivado_limited.sh -mode batch -source project/recreate_vivado_project.tcl
```

3. Se Vivado ha cache vecchia, pulisci lo stato generato e riprova:
```bash
rm -rf project/.vivado/FPGA-project/
VIVADO_MAX_GB=16 project/run_vivado_limited.sh -mode batch -source project/recreate_vivado_project.tcl
```

## Why this guide exists

Il TCL attuale scansiona solo i tree attivi e lascia fuori la copia legacy `uart_modular/`. Questo evita duplicate design units come `baud_gen`, `uart_rx` e `uart_tx`.

Se il problema e` la RAM, il wrapper [project/run_vivado_limited.sh](project/run_vivado_limited.sh) impone un cap di processo; alza `VIVADO_MAX_GB` a 18 solo se hai margine.

## Minimal run targets

Quando il progetto e` stato ricreato, gli ingressi abituali sono:

```bash
VIVADO_MAX_GB=18 project/run_vivado_limited.sh -mode batch -source project/recreate_vivado_project.tcl -tclargs loopback
VIVADO_MAX_GB=18 project/run_vivado_limited.sh -mode batch -source project/recreate_vivado_project.tcl -tclargs rng
VIVADO_MAX_GB=18 project/run_vivado_limited.sh -mode batch -source project/recreate_vivado_project.tcl -tclargs percolation
VIVADO_MAX_GB=18 project/run_vivado_limited.sh -mode batch -source project/recreate_vivado_project.tcl -tclargs percolation_uart
```

Per aprire il progetto generato:

```bash
VIVADO_MAX_GB=18 project/run_vivado_limited.sh project/.vivado/FPGA-project/FPGA-project.xpr
```

## Quick checks

Se compare un errore di link o elaborazione, controlla prima:

1. che il TCL usato sia quello corrente;
2. che la cache in `project/.vivado/FPGA-project/` sia stata rimossa;
3. che esistano i sorgenti attivi `project/percolation_core/percolation_core.vhd` e `project/percolation_core/percolation_uart_top.vhd`.

Per il resto dei dettagli usa [project/TEST_GUIDE.md](project/TEST_GUIDE.md).

**Last Updated**: 2026-04-15
