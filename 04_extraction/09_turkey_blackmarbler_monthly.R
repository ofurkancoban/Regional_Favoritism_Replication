# 04_extraction/09_turkey_blackmarbler_monthly.R
# Monthly VIIRS Black Marble (VNP46A3, the actual monthly product -- not
# VNP46A2 daily aggregated on GEE) for Turkey's 81 ADM1 provinces only,
# for the Kahramanmaras earthquake crisis-premium window.
#
# Scoped-down variant of 04_extraction/07_viirs_blackmarble_monthly.R:
# same per-region callr::r_bg() + hard-kill pattern (avoids the fork/libcurl
# hang and the cubic-backoff stall documented there), but restricted to a
# single country and a 25-month window instead of 174 countries x 176
# months -- a much smaller download per month (Turkey's tiles only, not
# the full global VNP46A3 grid), so this should complete in minutes on
# this Mac's own bandwidth rather than the VPS/LAADS throughput problems
# seen this session. Lets us cross-validate the GEE-derived VNP46A2-daily-
# aggregated-to-monthly panel (04_extraction/08_turkey_gee_viirs_monthly.R)
# against blackmarbler's own VNP46A3 monthly composite for the same window.
#
# Window: 2022-02 to 2024-02 (12 months before/after 6 Feb 2023).
# Band: NearNadir_Composite_Snow_Free (blackmarbler default, matches
# Bora (2025) and 07_viirs_blackmarble_monthly.R's convention).
#
# Output: data/processed/ntl/turkey_blackmarbler_monthly_adm1.csv
#   Columns: GID_1, year, month, viirs_ntl, n_pixels, n_non_na_pixels

library(sf)
library(data.table)
library(blackmarbler)
library(callr)

source("00_utils/blackmarble_catalog.R")
patch_blackmarble_tile_cache()

cat("=== Load Turkey ADM1 (GADM 4.1) ===\n")
adm1 <- sf::st_read("data/raw/gadm_4.1/turkey/gadm41_TUR_1.json", quiet = TRUE)
adm1 <- adm1[, c("GID_1", "NAME_1")]
data.table::setnames(adm1, "GID_1", "region_id")
adm1 <- sf::st_transform(adm1, 4326)
cat(sprintf("Provinces: %d\n", nrow(adm1)))

cat("\n=== Get NASA bearer token ===\n")
# Prefer a pre-generated EDL_TOKEN (Earthdata profile -> Generate Token) if
# set -- get_blackmarble_token()'s username/password exchange via .netrc
# fails on this account (confirmed 2026-08-19), same reason the wget-based
# pipeline switched to EDL_TOKEN earlier this session.
token <- Sys.getenv("EDL_TOKEN")
if (nchar(token) == 0) token <- get_blackmarble_token()
cat("Token OK.\n")

months <- seq(as.Date("2022-02-01"), as.Date("2024-02-01"), by = "month")
cat(sprintf("Months to process: %d (%s to %s)\n",
    length(months), format(months[1], "%Y-%m"), format(months[length(months)], "%Y-%m")))

out_dir <- "data/processed/ntl/turkey_blackmarbler_by_month"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

for (m in months) {
  m <- as.Date(m, origin = "1970-01-01")
  ym <- format(m, "%Y-%m")
  out_file <- file.path(out_dir, paste0(ym, ".csv"))
  if (file.exists(out_file)) { cat(sprintf("[%s] cached, skipping\n", ym)); next }

  t0 <- Sys.time()
  px <- callr::r_bg(
    function(adm1, ym, token, blackmarble_h5_dir) {
      blackmarbler::bm_extract(
        roi_sf           = adm1,
        product_id       = "VNP46A3",
        date             = paste0(ym, "-01"),
        bearer           = token,
        aggregation_fun  = "mean",
        add_n_pixels     = TRUE,
        quality_flag_rm  = 2,
        h5_dir           = blackmarble_h5_dir,
        download_method  = "httr",
        quiet            = TRUE
      )
    },
    args = list(adm1 = adm1, ym = ym, token = token, blackmarble_h5_dir = blackmarble_h5_dir),
    package = TRUE
  )
  ok <- px$wait(timeout = 600000)
  if (px$is_alive()) {
    px$kill()
    cat(sprintf("[%s] FAILED: timed out after 600s\n", ym))
    next
  }
  if (px$get_exit_status() != 0) {
    cat(sprintf("[%s] FAILED: %s\n", ym, paste(px$read_error_lines(), collapse = " | ")))
    next
  }
  ext <- tryCatch(px$get_result(), error = function(e) NULL)
  if (is.null(ext)) { cat(sprintf("[%s] FAILED: no result\n", ym)); next }

  dt <- data.table::as.data.table(sf::st_drop_geometry(ext))
  dt <- dt[, .(region_id, NAME_1,
               year = as.integer(format(m, "%Y")),
               month = as.integer(format(m, "%m")),
               viirs_ntl = ntl_mean, n_pixels, n_non_na_pixels)]

  tmp_file <- paste0(out_file, ".tmp")
  data.table::fwrite(dt, tmp_file)
  file.rename(tmp_file, out_file)

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  cat(sprintf("[%s] rows=%d (%.1fs)\n", ym, nrow(dt), elapsed))

  unlink(list.files(blackmarble_h5_dir, full.names = TRUE))
  gc(full = TRUE)
}

csv_files <- file.path(out_dir, paste0(format(months, "%Y-%m"), ".csv"))
if (all(file.exists(csv_files))) {
  panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
  data.table::fwrite(panel, "data/processed/ntl/turkey_blackmarbler_monthly_adm1.csv")
  cat(sprintf("\nPanel saved: %d rows, %d provinces, %d months\n",
      nrow(panel), data.table::uniqueN(panel$region_id), length(csv_files)))
} else {
  cat(sprintf("\nNot all months done (%d/%d) -- panel assembly skipped.\n",
      sum(file.exists(csv_files)), length(csv_files)))
}
