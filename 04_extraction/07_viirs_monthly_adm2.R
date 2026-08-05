# 04_extraction/07_viirs_monthly_adm2.R
# Monthly VIIRS nighttime lights, ADM2 (GADM 3.6, matching the rest of the
# core replication), 2012-01 onward. Replaces the annual EOG/Payne
# Institute VIIRS composite (04_extraction/05_viirs_adm2.R, GADM 4.1) as
# this project's VIIRS source -- monthly frequency is required for any
# future event-study / crisis-premium extension in the spirit of Bora
# (2025), which an annual-only series cannot support at all.
#
# Data source: World Bank "Light Every Night" AWS Open Data bucket
# (s3://globalnightlight, public, no auth) -- classic EOG-style monthly
# VIIRS composites (stray-light-corrected average radiance) as
# Cloud-Optimized GeoTIFFs. Chosen over NASA's own Black Marble (VNP46A3)
# after an empirical speed test found LAADS DAAC's tile-by-tile download
# server-throttled to the point that a full historical backfill would
# take multiple days-to-weeks; the same monthly extraction against this
# COG bucket via GDAL's /vsicurl/ (partial byte-range reads, no full-file
# download) takes seconds per month. See 00_utils/viirs_monthly_catalog.R
# for the full trade-off note. Confirmed 2026-08-18.
#
# Output: data/processed/ntl/viirs_monthly_adm2_panel.csv
#   Columns: region_id, iso3, adm_level, year, month, viirs_ntl

library(sf)
library(terra)
library(exactextractr)
library(data.table)

source("00_utils/viirs_monthly_catalog.R")

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
cat(sprintf("Regions: %d | ADM2: %d | ADM1-fallback: %d | countries: %d\n",
    nrow(regions), sum(regions$adm_level == "ADM2"), sum(regions$adm_level == "ADM1"),
    data.table::uniqueN(regions$iso3)))

months <- viirs_monthly_months()
cat(sprintf("Months to process: %d (%s to %s)\n", length(months), months[1], months[length(months)]))

out_dir <- "data/processed/ntl/viirs_monthly_by_month"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Redirected to the external drive -- the internal disk only has ~17GB
# free, too tight for 1-4GB monthly COG downloads even with per-month
# cleanup. Confirmed 2026-08-18.
raw_dir <- "/Volumes/Intenso/GIS/viirs_monthly_cog_tmp"
dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)

for (ym in months) {
  out_file <- file.path(out_dir, paste0(ym, ".csv"))
  if (file.exists(out_file)) { cat(sprintf("[%s] cached, skipping\n", ym)); next }

  t0 <- Sys.time()
  key <- get_viirs_monthly_key(ym)
  if (is.na(key)) { cat(sprintf("[%s] no composite found -- skipping\n", ym)); next }

  # Download the full COG locally instead of reading it via /vsicurl/.
  # Remote-range-read zonal extraction against ~46,000 regions (or even
  # just one geographically-dispersed country like the USA, whose Alaska+
  # Hawaii inflate its bounding box to near-global) forces exact_extract()
  # into a separate HTTP request per polygon, since the combined bounding
  # box exceeds its in-memory preload limit -- confirmed empirically: a
  # single-country (USA, 3148 regions) extraction did not finish within
  # 90-120s via vsicurl. A fully local raster has no such limit --
  # exact_extract() reads whatever window it needs directly from disk, no
  # network round-trips, matching this project's proven-fast local-raster
  # pattern used everywhere else (e.g. 00_utils/local_ntl_extraction.R).
  # Confirmed 2026-08-18.
  local_tif <- file.path(raw_dir, basename(key))
  dl_ok <- TRUE
  if (!file.exists(local_tif)) {
    remote_url <- paste0("https://globalnightlight.s3.amazonaws.com/", key)
    tmp_tif <- paste0(local_tif, ".part")
    # Files are ~1-4GB -- utils::download.file()'s default 60s timeout is
    # far too short and its libcurl backend doesn't retry, so shell out to
    # curl directly (retry + resume support, no arbitrary timeout).
    # Confirmed 2026-08-18.
    dl_status <- system2("curl", c(
      "--silent", "--fail", "--retry", "5", "--retry-delay", "5",
      "-C", "-", "-o", shQuote(tmp_tif), shQuote(remote_url)
    ))
    if (!identical(dl_status, 0L)) { dl_ok <- FALSE; cat(sprintf("[%s] download FAILED (curl exit %s)\n", ym, dl_status)) } else { file.rename(tmp_tif, local_tif) }
  }
  if (!dl_ok) next

  r <- tryCatch(terra::rast(local_tif), error = function(e) {
    cat(sprintf("[%s] FAILED to open raster: %s\n", ym, conditionMessage(e))); NULL
  })
  if (is.null(r)) { unlink(local_tif); next }

  ex <- tryCatch(
    exactextractr::exact_extract(r, regions, fun = "mean", progress = FALSE),
    error = function(e) { cat(sprintf("[%s] extract FAILED: %s\n", ym, conditionMessage(e))); NULL }
  )
  if (is.null(ex)) { rm(r); unlink(local_tif); next }

  dt <- data.table::data.table(
    region_id = regions$region_id, iso3 = regions$iso3, adm_level = regions$adm_level,
    viirs_ntl = ex,
    year = as.integer(substr(ym, 1, 4)), month = as.integer(substr(ym, 6, 7)))

  tmp_file <- paste0(out_file, ".tmp")
  data.table::fwrite(dt, tmp_file)
  file.rename(tmp_file, out_file)

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  cat(sprintf("[%s] rows=%d (%.1fs)\n", ym, nrow(dt), elapsed))

  # Delete the raw COG immediately -- keeping all 176 months locally
  # (each ~1-4GB) would exhaust the VPS's 41GB disk long before the
  # backfill finishes. Confirmed 2026-08-18.
  rm(r, dt); unlink(local_tif); terra::tmpFiles(remove = TRUE); gc(full = TRUE)
}

csv_files <- file.path(out_dir, paste0(months, ".csv"))
if (all(file.exists(csv_files))) {
  cat("\nAll months present -- assembling panel...\n")
  panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
  data.table::fwrite(panel, "data/processed/ntl/viirs_monthly_adm2_panel.csv")
  cat(sprintf("Panel saved: %d rows, %d regions, %d months\n",
      nrow(panel), data.table::uniqueN(panel$region_id), length(csv_files)))
} else {
  missing <- sum(!file.exists(csv_files))
  cat(sprintf("\nNot all months done yet (%d missing) -- panel assembly skipped.\n", missing))
}
