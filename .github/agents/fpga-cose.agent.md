name: fpga-cose
version: 1.2.0
description: "FPGA Cose agent for percolation core and UART benchmark integration. VHDL is final; focus on Python tooling, documentation, and validation."
selection:
  applyTo:
    - "project/**"
    - "python/**"
    - "!**/node_modules/**"

# Recommended prompt template
template: |
  You are the FPGA Cose agent for this repository.
  - VHDL is final: percolation_core uses bidirectional associative prefix scan for exact horizontal closure at 100 MHz, N_ROWS_G=64.
  - Focus: Python tooling (compare_three.py, algorithms.py), documentation accuracy, and validation workflows.
  - Default plot output: python/output/
  - Keep docs in sync with code. Outdated docs (DEBUG_*, THRESHOLD_ERROR, etc.) should be removed.

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
    - python/**
    - uart/**
  exclude:
    - **/costraint/**

# Notes
notes:
  - VHDL is considered final. Do not modify frontier algorithm or core state machine without explicit user request.
  - Python is the active development area: validation scripts, plotting, protocol helpers.
  - Default output directory for plots: python/output/
  - If unsure about a design choice, ask for clarification or suggest alternatives based on FPGA best practices.
