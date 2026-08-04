# 04_extraction/07_viirs_blackmarble_monthly.R
# Monthly VIIRS nighttime lights via NASA Black Marble VNP46A3, replacing
# the annual EOG/Payne Institute VIIRS composite (04_extraction/05_viirs_adm2.R)
# as this project's VIIRS source.
#
# Decision (2026-08-18): switched to Black Marble because (a) it provides
# MONTHLY frequency, required for any future event-study / crisis-premium
# extension (Bora 2025's design cannot be replicated at all on an
# annual-only series), and (b) it applies BRDF/view-angle correction and a
# near-nadir composite selection, addressing a known distortion source in
# raw VIIRS composites -- consistent with this project's broader emphasis
# on geometric precision this session (e.g. the geodesic-buffer fix for
# Table IV Col(1)). Uses GADM 3.6 (matching the rest of the core
# replication, unlike the old GADM-4.1-based EOG VIIRS extraction).
#
# Band: NearNadir_Composite_Snow_Free (blackmarbler's own default for
# VNP46A3), matching Bora (2025)'s stated near-nadir preference.
# Quality: quality_flag_rm = 2 drops gap-filled (historically-imputed,
# not actually observed) pixels; flag 1 (poor-quality, <=3 observations
# in the monthly composite) is kept by default -- can be tightened later
# if noise turns out to be a problem.
#
# Output: data/processed/ntl/viirs_blackmarble_adm2_panel.csv
#   Columns: region_id, iso3, adm_level, year, month, viirs_ntl,
#            n_pixels, n_non_na_pixels

library(sf)
library(data.table)
library(blackmarbler)

source("00_utils/blackmarble_catalog.R")

# blackmarbler::download_h5_files()'s internal per-file HTTP retry uses a
# cubic backoff (2 * attempts^3 seconds) for up to 10 attempts -- a single
# transient failure (e.g. a brief internet drop) can therefore block for
# over an hour (sum of sleeps ~4050s) before that one file gives up,
# effectively stalling the whole 176-month backfill on one bad request.
# Confirmed 2026-08-18. Two mitigations were tried and rejected before the
# one now in use (see the per-country loop below, `parallel::mcparallel` +
# hard SIGKILL): (a) a source-level monkey-patch via assignInNamespace()
# had no effect, likely because byte-compilation resolves the internal
# call at build time rather than through the namespace at call time; (b)
# R.utils::withTimeout()'s in-process interrupt fired but escaped the
# tryCatch and crashed the whole Rscript process when the block was
# inside libcurl's C code. Only an OS-level kill of a genuinely separate
# process is reliably immune to both failure modes.

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
regions <- sf::st_transform(regions, 4326)  # bm_extract requires WGS 84
cat(sprintf("Regions: %d | ADM2: %d | ADM1-fallback: %d | countries: %d\n",
    nrow(regions), sum(regions$adm_level == "ADM2"), sum(regions$adm_level == "ADM1"),
    data.table::uniqueN(regions$iso3)))

cat("\n=== Get NASA bearer token ===\n")
token <- get_blackmarble_token()
cat("Token OK.\n")

months <- blackmarble_months()
cat(sprintf("Months to process: %d (%s to %s)\n",
    length(months), format(months[1], "%Y-%m"), format(months[length(months)], "%Y-%m")))

out_dir <- "data/processed/ntl/viirs_blackmarble_by_month"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

for (m in months) {
  ym <- format(as.Date(m, origin = "1970-01-01"), "%Y-%m")
  out_file <- file.path(out_dir, paste0(ym, ".csv"))
  if (file.exists(out_file)) {
    cat(sprintf("[%s] cached, skipping\n", ym)); next
  }

  t0 <- Sys.time()

  # Extracting all 174 countries in one bm_extract() call OOM-killed the R
  # process repeatedly when first tried on a memory-constrained shared VPS
  # (confirmed via dmesg, up to 8GB anon-rss before being killed) -- kept
  # the per-country loop here too even though this Mac has more headroom,
  # since it's a cheap safeguard and keeps peak memory bounded regardless
  # of host. blackmarbler's own download_h5_files() skips re-downloading
  # any tile file already present in h5_dir, so tiles shared across
  # countries within a month are fetched once, not once per country.
  # Confirmed 2026-08-18.
  country_list <- sort(unique(regions$iso3))
  country_dt_list <- vector("list", length(country_list))
  any_failed <- FALSE
  for (i in seq_along(country_list)) {
    cty <- country_list[i]
    reg_c <- regions[regions$iso3 == cty, ]
    # Two earlier timeout mechanisms both failed: (a) R.utils::withTimeout()'s
    # in-process interrupt escaped the tryCatch and crashed the whole
    # Rscript process when the block was inside libcurl's C code; (b)
    # parallel::mcparallel()'s forked subprocess had every single country
    # time out at exactly 45s with zero new downloads -- a classic
    # fork()-after-libcurl-initialization bug (the parent process had
    # already made network calls via httr2/curl before forking, leaving
    # the forked child's inherited curl/SSL state broken/hung). Confirmed
    # 2026-08-18: read_sf() on the same URL that was hanging in every fork
    # returned in 6s when run standalone, proving the fork -- not the
    # network -- was the problem. callr::r_bg() spawns a genuinely
    # separate fresh R process (not a fork), which sidesteps this
    # entirely, at the cost of R startup overhead (~1-2s) per country.
    px <- callr::r_bg(
      function(reg_c, ym, token, blackmarble_h5_dir) {
        blackmarbler::bm_extract(
          roi_sf           = reg_c,
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
      args = list(reg_c = reg_c, ym = ym, token = token, blackmarble_h5_dir = blackmarble_h5_dir),
      package = TRUE
    )
    ok <- px$wait(timeout = 45000)
    if (px$is_alive()) {
      px$kill()
      cat(sprintf("[%s] %s FAILED: timed out after 45s\n", ym, cty))
      ext_c <- NULL
    } else if (px$get_exit_status() != 0) {
      cat(sprintf("[%s] %s FAILED: %s\n", ym, cty, paste(px$read_error_lines(), collapse = " | ")))
      ext_c <- NULL
    } else {
      ext_c <- tryCatch(px$get_result(), error = function(e) NULL)
      if (is.null(ext_c)) cat(sprintf("[%s] %s FAILED: no result\n", ym, cty))
    }
    if (is.null(ext_c)) { any_failed <- TRUE; next }
    dt_c <- data.table::as.data.table(sf::st_drop_geometry(ext_c))
    # ext_c retains our own input columns (region_id, iso3, adm_level) --
    # a GID_0 column is only added by bm_extract() when roi_sf's country
    # column is literally named GID_0, which ours isn't. Confirmed 2026-08-18.
    country_dt_list[[i]] <- dt_c[, .(region_id, iso3, adm_level,
                 year = as.integer(format(as.Date(m, origin = "1970-01-01"), "%Y")),
                 month = as.integer(format(as.Date(m, origin = "1970-01-01"), "%m")),
                 viirs_ntl = ntl_mean, n_pixels, n_non_na_pixels)]
    if (i %% 10 == 0) gc(full = FALSE)
  }
  dt <- data.table::rbindlist(country_dt_list, fill = TRUE)
  if (nrow(dt) == 0) {
    cat(sprintf("[%s] FAILED: no countries extracted\n", ym))
    unlink(list.files(blackmarble_h5_dir, full.names = TRUE))
    next
  }

  tmp_file <- paste0(out_file, ".tmp")
  data.table::fwrite(dt, tmp_file)
  file.rename(tmp_file, out_file)

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  cat(sprintf("[%s] rows=%d countries=%d/%d (%.1fs)%s\n", ym, nrow(dt),
      data.table::uniqueN(dt$iso3), length(country_list), elapsed,
      if (any_failed) " -- some countries failed, see log" else ""))

  # Clean up this month's raw h5 tiles once its panel CSV is safely written --
  # 176 months of global tile caches would far exceed even the external
  # drive's 468GB. Confirmed 2026-08-18.
  rm(country_dt_list, dt); unlink(list.files(blackmarble_h5_dir, full.names = TRUE)); gc(full = TRUE)
}

csv_files <- file.path(out_dir, paste0(format(months, "%Y-%m"), ".csv"))
if (all(file.exists(csv_files))) {
  cat("\nAll months present -- assembling panel...\n")
  panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
  data.table::fwrite(panel, "data/processed/ntl/viirs_blackmarble_adm2_panel.csv")
  cat(sprintf("Panel saved: %d rows, %d regions, %d months\n",
      nrow(panel), data.table::uniqueN(panel$region_id), nrow(csv_files)))
} else {
  missing <- length(csv_files) - sum(file.exists(csv_files))
  cat(sprintf("\nNot all months done yet (%d missing) -- panel assembly skipped.\n", missing))
}
