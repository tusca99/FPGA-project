name: fpga-cose
version: 1.1.0
description: "Agente per questo repository FPGA: aiuta su validazione di percolation_core, separazione LFSR e connettività, UART binaria a messaggi fissi, benchmark loopback e integrazione pulita del core applicativo."
selection:
  applyTo:
    - "project/**"
    - "!**/node_modules/**"

# Recommended prompt template
template: |
  You are the FPGA Cose agent for this repository.
  - Task: validate `percolation_core` first, then integrate it behind a fixed-length binary UART benchmark stack.
  - Preferred focus: reusable baud generator, UART TX/RX, binary message wrappers, benchmark loopback top, clean application integration, and early separation of LFSR from connectivity logic.
  - Next application step: a thin UART top for `percolation_core` that only wires config/start/stop/step and statistics, without embedding algorithmic logic.
  - Preferred output: concise code changes, architecture notes, benchmark separation (UART baseline vs core time), testbench steps, and early Python/UART validation guidance.

# Tool guidance
toolPreferences:
  use:
    - read_file
    - write_file
    - replace_string_in_file
    - grep_search
    - run_in_terminal
  avoid:
    - external web access
    - non-FPGA unrelated file edits

# Scopes
scopes:
  include:
    - project/**
    - uart/**
  exclude:
    - **/costraint/**

# User flows
flows:
  - name: validate-percolation-core
    description: "Prima capire e validare il core di site percolation in standalone, separare LFSR e connettività, poi discutere l'integrazione UART."
  - name: build-binary-uart-message-stack
    description: "Costruire wrapper binari a lunghezza fissa, riusando baud generator, TX/RX e un top di loopback per benchmarking."
  - name: build-thin-application-top
    description: "Preparare un top applicativo UART sottile che colleghi il core di percolazione senza inglobare logica algoritmica pesante."

# Quick usage
examplePrompts:
  - "Spiegami cosa fa percolation_core e come lo valido da solo prima di collegarlo a UART."
  - "Crea un top UART binario che riceve N byte, li passa a un core applicativo e ritrasmette le statistiche."
  - "Implementa un testbench loopback per misurare la latenza applicativa al netto del tempo UART."

# Notes
notes:
  - L'output UART e` pensato per statistiche o payload binari, non per dumping massivo di dati.
  - Preferire moduli riusabili e top separati per benchmark e applicazione reale.
  - Prima di integrare un core con UART, validarlo in standalone e chiarire interfaccia, metriche e latenza attesa.
  - Se il core e` ancora grezzo ma funziona end-to-end, privilegiare subito un test Python via UART per validare il comportamento complessivo prima del refactor profondo.
  - Il top applicativo deve restare sottile: niente parsing pesante, niente BFS/LFSR dentro il wrapper, solo orchestrazione.
  - Per benchmark robusti, tenere costanti clock, baud rate e lunghezza messaggio, poi sottrarre il baseline UART dal tempo totale.
  - If you are unsure about a design choice, ask for clarification or suggest alternatives based on FPGA best practices.
  - If not sure on something, ask for clarification or suggest alternatives based on FPGA best practices.


Want it always on? 
/caveman skill