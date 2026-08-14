#!/bin/bash
# Watchdog for R/16_gee_adm1_holepunched.R: the extraction intermittently
# hangs on individual GEE requests for reasons unrelated to geometry
# complexity (observed on both very dense and simple polygons across
# different runs). Since the script is resume-safe (skips already-cached
# countries), this watchdog kills and relaunches it whenever no new output
# file has appeared for STALE_MIN minutes, until all 147 countries are done.

cd "/Users/ofurkancoban/Desktop/Data Projects/GIS_RegionalFavoritism" || exit 1

OUT_DIR="data/processed/ntl/adm1_holepunched_by_country"
LOG="/tmp/holepunch_watchdog.log"
STALE_MIN=4
TOTAL=147

echo "$(date) watchdog started" >> "$LOG"

while true; do
  n_done=$(ls "$OUT_DIR" 2>/dev/null | wc -l | tr -d ' ')
  echo "$(date) files done: $n_done / $TOTAL" >> "$LOG"

  if [ "$n_done" -ge "$TOTAL" ]; then
    echo "$(date) all countries done, exiting watchdog" >> "$LOG"
    break
  fi

  # (Re)launch the extraction script
  pkill -f "16_gee_adm1_holepunched.R" 2>/dev/null
  sleep 2
  nohup Rscript R/16_gee_adm1_holepunched.R > /tmp/holepunch_gee_watched.log 2>&1 &
  RPID=$!
  echo "$(date) launched Rscript PID $RPID" >> "$LOG"

  last_n=$(ls "$OUT_DIR" 2>/dev/null | wc -l | tr -d ' ')
  stale_checks=0
  max_stale_checks=$((STALE_MIN * 2))  # checking every 30s

  while kill -0 "$RPID" 2>/dev/null; do
    sleep 30
    cur_n=$(ls "$OUT_DIR" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$cur_n" -gt "$last_n" ]; then
      last_n=$cur_n
      stale_checks=0
    else
      stale_checks=$((stale_checks + 1))
    fi
    echo "$(date) files: $cur_n, stale_checks: $stale_checks" >> "$LOG"
    if [ "$cur_n" -ge "$TOTAL" ]; then
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
