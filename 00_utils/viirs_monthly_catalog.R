# 00_utils/viirs_monthly_catalog.R
# Shared helpers for monthly VIIRS nighttime lights via the World Bank
# "Light Every Night" AWS Open Data bucket (Cloud-Optimized GeoTIFF, one
# global mosaic per month, accessed via GDAL's /vsicurl/ so only the byte
# ranges needed for each polygon are fetched -- no full-file download).
#
# Chosen over NASA's own Black Marble (VNP46A3, via LAADS DAAC) after an
# empirical speed test: LAADS DAAC's tile-by-tile HTTP download (even with
# 12-way parallel curl) was server-throttled at roughly 1 country-month
# per several minutes -- a full global monthly extraction would have taken
# multiple days per month, ~170 months = infeasible. The same zonal
# extraction via this COG bucket takes seconds per month (raster metadata
# open ~3s, then each polygon's zonal mean is a fast partial-byte-range
# read). Trade-off: this is the classic EOG-style monthly VIIRS composite
# (stray-light corrected average radiance, "vcm-slcorr"/"ecm-slcorr"
# variable naming differs slightly across processing-version eras), not
# Black Marble's BRDF/near-nadir-corrected product -- Bora (2025) found
# both angle-correction and no-angle-correction VIIRS specifications give
# consistent results, so this is not expected to be a substantive
# limitation for this project's purposes. Confirmed 2026-08-18.
#
# Source: https://registry.opendata.aws/wb-light-every-night/
# Bucket: s3://globalnightlight (us-east-1), public, no auth needed.

library(data.table)

viirs_monthly_months <- function(end_ym = format(Sys.Date(), "%Y-%m")) {
  format(seq(as.Date("2012-01-01"), as.Date(paste0(end_ym, "-01")), by = "month"), "%Y-%m")
}

#' List the exact S3 key for a given month's stray-light-corrected average
#' radiance COG. Folder-name suffixes (_rp2, _ops) and variable-name
#' conventions (vcm-slcorr vs. ecm-slcorr) both vary across processing
#' eras, so this is resolved dynamically per month rather than guessed.
#' Tries the "npp" (Suomi-NPP) series first, falling back to "j01"
#' (NOAA-20) for months where npp composites aren't available.
get_viirs_monthly_key <- function(ym) {
  ym_compact <- gsub("-", "", ym)
  for (sensor in c("npp", "j01")) {
    prefix <- sprintf("composites/%s_%s", sensor, ym_compact)
    url <- sprintf("https://globalnightlight.s3.amazonaws.com/?list-type=2&prefix=%s", prefix)
    xml <- tryCatch(paste(readLines(url, warn = FALSE), collapse = ""), error = function(e) "")
    keys <- regmatches(xml, gregexpr("(?<=<Key>)[^<]+(?=</Key>)", xml, perl = TRUE))[[1]]
    key <- keys[grepl("slcorr.*avg_rade9\\.tif$", keys)]
    if (length(key) >= 1) return(key[1])
  }
  NA_character_
}

viirs_monthly_vsicurl <- function(key) {
  paste0("/vsicurl/https://globalnightlight.s3.amazonaws.com/", key)
}
