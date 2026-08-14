#!/bin/bash
# R/32_run_sequential_dmsp_local.sh
# Runs R/30_local_terra_dmsp_grid.R strictly SEQUENTIALLY, one resolution
# per process, as separate invocations/log files, cheapest (fewest cells)
# first: 400km (~2131 cells), 200km (~5933 cells), 100km (~18794 cells),
# 50km (~65036 cells).

set -e
cd "$(dirname "$0")/.."

LOG_DIR="data/processed/ntl"
mkdir -p "$LOG_DIR"

for RES in 400 200 100 50; do
  echo "$(date) Starting ${RES}km..." | tee -a "$LOG_DIR/sequential_dmsp_local.log"
  Rscript R/30_local_terra_dmsp_grid.R "$RES" >> "$LOG_DIR/grid_${RES}km_dmsp_local.log" 2>&1
  echo "$(date) ${RES}km done." | tee -a "$LOG_DIR/sequential_dmsp_local.log"
done
echo "$(date) All resolutions complete." | tee -a "$LOG_DIR/sequential_dmsp_local.log"
