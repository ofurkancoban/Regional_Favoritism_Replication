#!/bin/bash
# VPS watchdog for R/21_gee_grid_cells.R <resolution_km>.
# Same pattern as watchdog_holepunch_vps.sh: kills and relaunches on
# staleness (year-level part-cache makes restarts cheap), resume-safe at
# the country level (files already written are skipped).
#
# Usage: bash watchdog_grid_vps.sh <resolution_km> <total_countries>

RES_KM="$1"
TOTAL="$2"
if [ -z "$RES_KM" ] || [ -z "$TOTAL" ]; then
  echo "Usage: bash watchdog_grid_vps.sh <resolution_km> <total_countries>"
  exit 1
fi

cd "/root/GIS_RegionalFavoritism" || exit 1

OUT_DIR="data/processed/ntl/grid_${RES_KM}km_by_country"
LOG="/root/grid_${RES_KM}km_watchdog.log"
STALE_MIN=20

echo "$(date) watchdog started for ${RES_KM}km grid" >> "$LOG"

while true; do
  n_done=$(ls "$OUT_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ')
  echo "$(date) files done: $n_done / $TOTAL" >> "$LOG"

  if [ "$n_done" -ge "$TOTAL" ]; then
    echo "$(date) all countries done, exiting watchdog" >> "$LOG"
    break
  fi

  pkill -f "21_gee_grid_cells.R $RES_KM" 2>/dev/null
  sleep 2
  nohup Rscript R/21_gee_grid_cells.R "$RES_KM" > "/root/grid_${RES_KM}km_gee_watched.log" 2>&1 &
  RPID=$!
  echo "$(date) launched Rscript PID $RPID" >> "$LOG"

  last_activity=$(find "$OUT_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
  stale_checks=0
  max_stale_checks=$((STALE_MIN * 2))

  while kill -0 "$RPID" 2>/dev/null; do
    sleep 30
    cur_done=$(ls "$OUT_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ')
    cur_activity=$(find "$OUT_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$cur_activity" -gt "$last_activity" ]; then
      last_activity=$cur_activity
      stale_checks=0
    else
      stale_checks=$((stale_checks + 1))
    fi
    echo "$(date) countries: $cur_done, activity: $cur_activity, stale_checks: $stale_checks" >> "$LOG"
    if [ "$cur_done" -ge "$TOTAL" ]; then
      break
    fi
    if [ "$stale_checks" -ge "$max_stale_checks" ]; then
      echo "$(date) stale for ${STALE_MIN}min, killing PID $RPID" >> "$LOG"
      kill "$RPID" 2>/dev/null
      sleep 2
      break
    fi
  done
done
