#!/bin/bash
# 00_utils/blackmarble_parallel_download.sh
# Parallel wget-based download of all VNP46A3 (Black Marble monthly)
# global tile sets, 2012-01 through 2026-08, to the external drive.
# Requires a valid Earthdata Login (EDL) bearer token with the LAADS-
# related EULA accepted (Earthdata profile -> Applications/EULAs).
# Uses wget's mirror mode (-m implies -N, i.e. skip files already present
# and up to date), so this is safe to re-run or resume after interruption.
#
# Usage: TOKEN="..." ./00_utils/blackmarble_parallel_download.sh [N_PARALLEL]

set -euo pipefail

if [ -z "${TOKEN:-}" ]; then
  echo "Set TOKEN env var to your Earthdata bearer token first." >&2
  exit 1
fi

N_PARALLEL="${1:-4}"
OUT_DIR="/Volumes/Intenso/GIS/blackmarble_raw"
mkdir -p "$OUT_DIR"

# Generate YYYY DOY pairs for the 1st of every month, 2012-01 to 2026-08.
python3 -c "
import datetime
d = datetime.date(2012,1,1)
end = datetime.date(2026,8,1)
while d <= end:
    doy = d.timetuple().tm_yday
    print(f'{d.year} {doy:03d}')
    if d.month == 12:
        d = datetime.date(d.year+1,1,1)
    else:
        d = datetime.date(d.year, d.month+1, 1)
" > /tmp/bm_months.txt

echo "Months to fetch: $(wc -l < /tmp/bm_months.txt), parallelism: $N_PARALLEL"

download_month() {
  year="$1"
  doy="$2"
  wget -e robots=off -m -np -R .html,.tmp -nH --cut-dirs=3 \
    "https://ladsweb.modaps.eosdis.nasa.gov/archive/allData/5200/VNP46A3/${year}/${doy}/" \
    --header "Authorization: Bearer ${TOKEN}" \
    -P "$OUT_DIR" \
    -o "$OUT_DIR/wget_${year}_${doy}.log"
}
export -f download_month
export TOKEN OUT_DIR

# xargs -P runs N_PARALLEL wget mirrors concurrently, one per month.
# Each writes to its own YYYY/DDD/ subfolder (via -nH --cut-dirs=3), so
# there's no collision between parallel jobs.
cat /tmp/bm_months.txt | xargs -P "$N_PARALLEL" -L 1 bash -c 'download_month "$@"' _

echo "Done. Check $OUT_DIR for downloaded tiles."
