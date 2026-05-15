#!/usr/bin/env bash
set -euo pipefail

DB=python/output/benchmark.sqlite3
PORT=/dev/ttyUSB1
P=0.60

runs_list=(1 4 16 64 256 1024 4096 16384)
steps_list=(64 128 256 512 768 1024 2048)

for steps in "${steps_list[@]}"; do
  for runs in "${runs_list[@]}"; do
    python -m percolation_uart.benchmark \
      --hardware-only \
      --port "$PORT" \
      --runs "$runs" \
      --repeats 5 \
      --points 2 \
      --pmin "$P" --pmax "$P" \
      --steps "$steps" \
      --sqlite "$DB" \
      --settle 0.01 \
      --width 170
  done
done