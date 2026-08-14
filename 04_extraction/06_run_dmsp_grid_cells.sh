#!/bin/bash
# 04_extraction/06_run_dmsp_grid_cells.sh
# Runs 04_dmsp_grid_cells.R strictly SEQUENTIALLY, one resolution per
# process, cheapest (fewest cells) first: 400km (~2131 cells), 200km
# (~5933 cells), 100km (~18794 cells), 50km (~65036 cells). Formerly
# R/32_run_sequential_dmsp_local.sh.

set -e
cd "$(dirname "$0")/.."

LOG_DIR="data/processed/ntl"
mkdir -p "$LOG_DIR"

for RES in 400 200 100 50; do
  echo "$(date) Starting ${RES}km..." | tee -a "$LOG_DIR/dmsp_grid_extraction.log"
  Rscript 04_extraction/04_dmsp_grid_cells.R "$RES" >> "$LOG_DIR/dmsp_grid${RES}km_extraction.log" 2>&1
  echo "$(date) ${RES}km done." | tee -a "$LOG_DIR/dmsp_grid_extraction.log"
done
echo "$(date) All resolutions complete." | tee -a "$LOG_DIR/dmsp_grid_extraction.log"
