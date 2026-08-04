# 04_extraction/07_viirs_blackmarble_wget_monthly.R
# Monthly VIIRS nighttime lights via NASA Black Marble VNP46A3, using a
# wget-based download instead of blackmarbler's own httr2 downloader.
#
# Background: blackmarbler's built-in download (used by
# 04_extraction/07_viirs_blackmarble_monthly.R) goes through a bearer-
# token API path that was server-throttled to a crawl (a single country's
# tiles took 5+ minutes and sometimes never finished, confirmed
# 2026-08-19). A plain `wget -m` mirror against the same LAADS DAAC
# archive, using a proper Earthdata Login (EDL) bearer token (generated
# via Earthdata profile -> Generate Token, with the required EULA
# accepted under profile -> EULAs -> Accept New EULAs), is dramatically
# faster (~1.7MB/s single-stream, ~3.2MB/s with 4 parallel streams,
# confirmed 2026-08-19) -- same server, same account, different endpoint
# behavior.
#
# Disk constraint: one month's full global VNP46A3 tile set is ~540
# files / ~12GB; storing all 176 months at once (~2.2TB) does not fit on
# the 476GB external drive. So each month's tiles are downloaded,
# immediately extracted via blackmarbler::bm_extract() (which detects
# the already-downloaded local files and skips its own slow download
# step entirely), then deleted before moving to the next month.
#
# Output: data/processed/ntl/viirs_blackmarble_adm2_panel.csv

library(sf)
library(data.table)
library(blackmarbler)

source("00_utils/blackmarble_catalog.R")
patch_blackmarble_tile_cache()

cat("=== Load GADM 3.6 (ADM2, ADM1 fallback) for PLAD countries ===\n")
plad  <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

sf::sf_use_s2(FALSE)
adm2 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
sf::st_geometry(adm2) <- "geometry"
adm2 <- adm2[adm2$GID_0 %in% iso3s, c("GID_0", "GID_2", "geometry")]
data.table::setnames(adm2, c("GID_0", "GID_2"), c("iso3", "region_id"))
adm2$adm_level <- "ADM2"

adm1 <- sf::st_read("data/raw/gadm_3.6/gadm36_level1_only.gpkg", quiet = TRUE)
sf::st_geometry(adm1) <- "geometry"
adm1 <- adm1[adm1$GID_0 %in% iso3s, c("GID_0", "GID_1", "geometry")]
data.table::setnames(adm1, c("GID_0", "GID_1"), c("iso3", "region_id"))
adm1$adm_level <- "ADM1"

has_adm2 <- unique(adm2$iso3)
adm1_fallback <- adm1[!adm1$iso3 %in% has_adm2, ]

regions <- rbind(adm2[, c("region_id", "iso3", "adm_level")],
                  adm1_fallback[, c("region_id", "iso3", "adm_level")])
regions <- sf::st_transform(regions, 4326)
cat(sprintf("Regions: %d | ADM2: %d | ADM1-fallback: %d | countries: %d\n",
    nrow(regions), sum(regions$adm_level == "ADM2"), sum(regions$adm_level == "ADM1"),
    data.table::uniqueN(regions$iso3)))

token <- Sys.getenv("EDL_TOKEN")
if (nchar(token) == 0) stop("Set EDL_TOKEN environment variable to your Earthdata bearer token.")

months <- blackmarble_months()

# Optional MONTH_START_IDX/MONTH_END_IDX (1-based, inclusive) let this
# same script be split across multiple machines running in parallel --
# e.g. a faster machine takes a larger index range. Output filenames are
# just YYYY-MM.csv regardless of which machine produced them, so the
# per-machine CSV folders can be merged afterward with a plain file copy
# before the final panel-assembly step. Confirmed 2026-08-19.
start_idx <- as.integer(Sys.getenv("MONTH_START_IDX", "1"))
end_idx   <- as.integer(Sys.getenv("MONTH_END_IDX", as.character(length(months))))
months <- months[start_idx:end_idx]

cat(sprintf("Months to process: %d (%s to %s) [indices %d-%d of full range]\n",
    length(months), format(months[1], "%Y-%m"), format(months[length(months)], "%Y-%m"),
    start_idx, end_idx))

out_dir <- "data/processed/ntl/viirs_blackmarble_by_month"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Downloads one month's ~540 global tiles using N_PARALLEL concurrent
# curl connections (default 15, matching the concurrency the user found
# fastest manually) instead of a single wget mirror stream. Each file is
# fetched with `curl -C -` (resume) so a killed/interrupted run picks up
# exactly where it left off -- files already complete are skipped
# entirely (curl -C - on a fully-downloaded file is a no-op success).
# Confirmed 2026-08-19.
download_month_parallel <- function(year, doy, token, out_dir, n_parallel = 15) {
  base_url <- sprintf("https://ladsweb.modaps.eosdis.nasa.gov/archive/allData/5200/VNP46A3/%s/%s/", year, doy)
  # --max-time bounds the whole request (connect + transfer) -- without it
  # a stalled LADS DAAC response hangs system2() indefinitely, since R has
  # no default socket timeout of its own. Confirmed 2026-08-19: all 3 VPS
  # sat at ~4% CPU with zero progress for 25+ minutes with no crash, no
  # error -- a silent hang on this exact call, not a slow-but-working state.
  listing <- tryCatch(
    paste(system2("curl", c("-s", "--max-time", "60", "-H", shQuote(paste("Authorization: Bearer", token)), shQuote(base_url)), stdout = TRUE), collapse = ""),
    error = function(e) ""
  )
  files <- unique(regmatches(listing, gregexpr("VNP46A3\\.[^\"]+\\.h5", listing))[[1]])
  if (length(files) == 0) return(FALSE)

  dest_dir <- file.path(out_dir, "VNP46A3", year, doy)
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)

  url_list_file <- tempfile()
  lines <- sprintf(
    "url = \"%s%s\"\noutput = \"%s\"",
    base_url, files, file.path(dest_dir, files)
  )
  writeLines(lines, url_list_file)

  status <- system2("curl", c(
    "--silent", "--fail", "--retry", "3", "--retry-delay", "3", "-C", "-",
    "--max-time", "300", "--connect-timeout", "30",
    "-H", shQuote(paste("Authorization: Bearer", token)),
    "--parallel", "--parallel-max", as.character(n_parallel),
    "-K", url_list_file
  ))
  unlink(url_list_file)
  identical(status, 0L)
}

for (m in months) {
  ym <- format(as.Date(m, origin = "1970-01-01"), "%Y-%m")
  out_file <- file.path(out_dir, paste0(ym, ".csv"))
  if (file.exists(out_file)) { cat(sprintf("[%s] cached, skipping\n", ym)); next }

  # Per-month wall-clock watchdog: blackmarbler::bm_extract()'s own httr
  # calls have no bound (download_method="httr" defaults to httr_timeout
  # =60 PER FILE, but retries/redirects/DNS stalls inside it are not
  # covered), so a single hung batch call can freeze the whole run
  # indefinitely with no crash and no log line -- confirmed 2026-08-19:
  # all 3 VPS sat at 2-4% CPU with zero progress for 25+ minutes, one of
  # them already past the download step (555/555 tiles present) and stuck
  # purely inside extraction. setTimeLimit(transient=TRUE) throws a
  # catchable error once elapsed wall-clock time is exceeded for this
  # iteration; the tryCatch below logs it and moves on to the next month
  # rather than blocking the run forever.
  setTimeLimit(elapsed = 900, transient = TRUE)
  month_ok <- tryCatch({

  year <- format(as.Date(m, origin = "1970-01-01"), "%Y")
  doy  <- sprintf("%03d", as.integer(format(as.Date(m, origin = "1970-01-01"), "%j")))

  t0 <- Sys.time()
  # 30-parallel measured slower than 15-parallel (1.5MB/s vs 2.8MB/s,
  # confirmed 2026-08-19) -- the server has a total-bandwidth or per-
  # account connection cap, so more connections beyond ~15 just divides
  # the same pie into smaller slices. 15 is the sweet spot found so far.
  dl_ok <- download_month_parallel(year, doy, token, blackmarble_h5_dir, n_parallel = 8)
  if (!dl_ok) { cat(sprintf("[%s] download FAILED\n", ym)); next }
  dl_elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)

  # bm_extract()'s internal download_h5_files() checks file.exists() per
  # expected tile filename and skips ones already present -- since we
  # just wget'd the full global set, every tile it needs is already
  # local, so this call does no network I/O and just reads+extracts.
  #
  # A single whole-region bm_extract() call (all 174 countries at once)
  # OOM-killed the VPS twice in a row here -- confirmed 2026-08-19,
  # memory climbed steadily to ~9GB RSS (78%+ of the VPS's 11GB) over
  # ~70 minutes before being killed, same failure mode seen earlier this
  # session with the non-wget Black Marble script. Looping per country
  # keeps peak memory bounded, matching the fix already applied to the
  # local Mac driver (04_extraction/07_viirs_blackmarble_monthly.R).
  # EXTRACT_MODE="whole" does one bm_extract() call for all 174 countries
  # at once -- much faster (no repeated tile-list fetch / h5 reopen per
  # country) but memory-hungry (~9GB RSS observed), so it's only safe on
  # a machine with plenty of headroom (e.g. this project's 16GB Mac, not
  # the 11GB shared VPS instances, which OOM-crashed on this path twice).
  # Default stays "per_country" for VPS safety. Confirmed 2026-08-19.
  t1 <- Sys.time()
  extract_mode <- Sys.getenv("EXTRACT_MODE", "per_country")
  any_failed <- FALSE

  if (extract_mode == "whole") {
    ext <- tryCatch(
      blackmarbler::bm_extract(
        roi_sf           = regions,
        product_id       = "VNP46A3",
        date             = paste0(ym, "-01"),
        bearer           = token,
        aggregation_fun  = "mean",
        add_n_pixels     = TRUE,
        quality_flag_rm  = 2,
        h5_dir           = blackmarble_h5_dir,
        download_method  = "httr",
        quiet            = TRUE
      ),
      error = function(e) {
        cat(sprintf("[%s] whole-region extract FAILED: %s\n", ym, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(ext)) {
      any_failed <- TRUE
      dt <- data.table::data.table()
    } else {
      dt <- data.table::as.data.table(sf::st_drop_geometry(ext))
      dt <- dt[, .(region_id, iso3, adm_level,
                   year = as.integer(format(as.Date(m, origin = "1970-01-01"), "%Y")),
                   month = as.integer(format(as.Date(m, origin = "1970-01-01"), "%m")),
                   viirs_ntl = ntl_mean, n_pixels, n_non_na_pixels)]
    }
  } else {
    # Batching countries (instead of one bm_extract() call per country)
    # cuts most of the per-call overhead that made the pure per-country
    # loop extremely slow -- each bm_extract() call independently
    # re-fetches blackmarbler's tile-grid geojson from GitHub and
    # re-opens h5 tiles from scratch, so 174 single-country calls paid
    # that cost 174 times (~80+ minutes observed for one month on a VPS,
    # confirmed 2026-08-19). A batch size of ~20 countries per call cuts
    # the call count roughly 20x while still keeping each call's region
    # set small enough to bound memory well below the ~9GB level that
    # OOM-killed the all-174-at-once approach.
    batch_size <- as.integer(Sys.getenv("EXTRACT_BATCH_SIZE", "20"))
    country_list <- sort(unique(regions$iso3))
    batches <- split(country_list, ceiling(seq_along(country_list) / batch_size))
    batch_dt_list <- vector("list", length(batches))
    for (i in seq_along(batches)) {
      reg_b <- regions[regions$iso3 %in% batches[[i]], ]
      ext_b <- tryCatch(
        blackmarbler::bm_extract(
          roi_sf           = reg_b,
          product_id       = "VNP46A3",
          date             = paste0(ym, "-01"),
          bearer           = token,
          aggregation_fun  = "mean",
          add_n_pixels     = TRUE,
          quality_flag_rm  = 2,
          h5_dir           = blackmarble_h5_dir,
          download_method  = "httr",
          quiet            = TRUE
        ),
        error = function(e) {
          cat(sprintf("[%s] batch %d/%d (%s) FAILED: %s\n", ym, i, length(batches),
              paste(batches[[i]], collapse = ","), conditionMessage(e)))
          NULL
        }
      )
      if (is.null(ext_b)) { any_failed <- TRUE; next }
      dt_b <- data.table::as.data.table(sf::st_drop_geometry(ext_b))
      batch_dt_list[[i]] <- dt_b[, .(region_id, iso3, adm_level,
                   year = as.integer(format(as.Date(m, origin = "1970-01-01"), "%Y")),
                   month = as.integer(format(as.Date(m, origin = "1970-01-01"), "%m")),
                   viirs_ntl = ntl_mean, n_pixels, n_non_na_pixels)]
      gc(full = FALSE)
    }
    dt <- data.table::rbindlist(batch_dt_list, fill = TRUE)
  }

  # Delete this month's raw tiles regardless of extraction outcome -- the
  # disk can't hold more than a few months' worth at once.
  unlink(file.path(blackmarble_h5_dir, "VNP46A3", year, doy), recursive = TRUE)

  if (nrow(dt) == 0) {
    cat(sprintf("[%s] FAILED: no countries extracted\n", ym))
    next
  }

  tmp_file <- paste0(out_file, ".tmp")
  data.table::fwrite(dt, tmp_file)
  file.rename(tmp_file, out_file)

  extract_elapsed <- round(as.numeric(difftime(Sys.time(), t1, units = "secs")), 1)
  cat(sprintf("[%s] rows=%d countries=%d/%d (download %.1fs, extract %.1fs, mode=%s)%s\n", ym, nrow(dt),
      data.table::uniqueN(dt$iso3), data.table::uniqueN(regions$iso3), dl_elapsed, extract_elapsed, extract_mode,
      if (any_failed) " -- some countries failed, see log" else ""))

  rm(dt); gc(full = TRUE)
  TRUE
  }, error = function(e) {
    cat(sprintf("[%s] ABORTED: %s\n", ym, conditionMessage(e)))
    FALSE
  })
  setTimeLimit(elapsed = Inf, transient = FALSE)
}

csv_files <- file.path(out_dir, paste0(format(months, "%Y-%m"), ".csv"))
if (all(file.exists(csv_files))) {
  cat("\nAll months present -- assembling panel...\n")
  panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
  data.table::fwrite(panel, "data/processed/ntl/viirs_blackmarble_adm2_panel.csv")
  cat(sprintf("Panel saved: %d rows, %d regions, %d months\n",
      nrow(panel), data.table::uniqueN(panel$region_id), length(csv_files)))
} else {
  missing <- length(csv_files) - sum(file.exists(csv_files))
  cat(sprintf("\nNot all months done yet (%d missing) -- panel assembly skipped.\n", missing))
}
