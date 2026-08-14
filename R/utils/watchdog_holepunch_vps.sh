#!/bin/bash
# VPS version of the watchdog for R/16_gee_adm1_holepunched.R.
# Two progress signals are tracked separately:
#   - n_done: count of completed COUNTRY-level output files (*_adm1holed.csv
#     directly in OUT_DIR) -- this is what determines when we're finished
#     (target: TOTAL countries).
#   - n_activity: count of ALL files anywhere under OUT_DIR, including the
#     _part_cache/ subdirectory where individual YEARS get checkpointed
#     while working through an intractably complex single ADM1 row (e.g.
#     Australia's mainland, 8 part-chunks x 22 years). Using only n_done for
#     staleness detection would make the watchdog blind to real progress
#     happening one year at a time inside a single row -- it could kill a
#     process that's actually working, just slowly, on a country with
#     several such rows.
# Resume-safe at both levels: countries already written are skipped, and
# years already cached for a given row are skipped too.

cd "/root/GIS_RegionalFavoritism" || exit 1

OUT_DIR="data/processed/ntl/adm1_holepunched_by_country"
LOG="/root/holepunch_watchdog.log"
STALE_MIN=20
TOTAL=147

echo "$(date) watchdog started" >> "$LOG"

while true; do
  n_done=$(ls "$OUT_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ')
  echo "$(date) files done: $n_done / $TOTAL" >> "$LOG"

  if [ "$n_done" -ge "$TOTAL" ]; then
    echo "$(date) all countries done, exiting watchdog" >> "$LOG"
    break
  fi

  pkill -f "16_gee_adm1_holepunched.R" 2>/dev/null
  sleep 2
  nohup Rscript R/16_gee_adm1_holepunched.R > /root/holepunch_gee_watched.log 2>&1 &
  RPID=$!
  echo "$(date) launched Rscript PID $RPID" >> "$LOG"

  last_activity=$(find "$OUT_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
  stale_checks=0
  max_stale_checks=$((STALE_MIN * 2))  # checking every 30s

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
    echo "$(date) countries: $cur_done, activity(files incl. part-cache): $cur_activity, stale_checks: $stale_checks" >> "$LOG"
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
