#!/bin/bash
# Attaches to an ALREADY-RUNNING R/21_gee_grid_cells.R <res> process without
# killing it first (unlike watchdog_grid_vps.sh, which always kills+relaunches
# on start). Only kills and relaunches if the running process goes stale or
# is not found at all. Otherwise identical supervision logic.
#
# Usage: bash watchdog_grid_attach.sh <resolution_km> <total_countries>

RES_KM="$1"
TOTAL="$2"
if [ -z "$RES_KM" ] || [ -z "$TOTAL" ]; then
  echo "Usage: bash watchdog_grid_attach.sh <resolution_km> <total_countries>"
  exit 1
fi

cd "/root/GIS_RegionalFavoritism" || exit 1

OUT_DIR="data/processed/ntl/grid_${RES_KM}km_by_country"
LOG="/root/grid_${RES_KM}km_watchdog.log"
STALE_MIN=20

echo "$(date) watchdog attached (no immediate kill) for ${RES_KM}km grid" >> "$LOG"

while true; do
  n_done=$(ls "$OUT_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ')
  echo "$(date) files done: $n_done / $TOTAL" >> "$LOG"

  if [ "$n_done" -ge "$TOTAL" ]; then
    echo "$(date) all countries done, exiting watchdog" >> "$LOG"
    break
  fi

  RPID=$(pgrep -f "21_gee_grid_cells.R.*$RES_KM" | head -1)
  if [ -z "$RPID" ]; then
    echo "$(date) no running process found, launching fresh" >> "$LOG"
    nohup Rscript R/21_gee_grid_cells.R "$RES_KM" > "/root/grid_${RES_KM}km_gee_watched.log" 2>&1 &
    RPID=$!
    echo "$(date) launched Rscript PID $RPID" >> "$LOG"
  else
    echo "$(date) attached to existing PID $RPID" >> "$LOG"
  fi

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
