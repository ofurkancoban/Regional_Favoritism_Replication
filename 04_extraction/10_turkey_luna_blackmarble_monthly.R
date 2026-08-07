# 04_extraction/10_turkey_luna_blackmarble_monthly.R
# Monthly VIIRS Black Marble (VNP46A3) for Turkey's 81 ADM1 provinces,
# downloaded via the `luna` package (NASA CMR search + Earthdata Login
# session) instead of blackmarbler's own httr downloader.
#
# Rationale: blackmarbler's download step (04_extraction/09_turkey_
# blackmarbler_monthly.R) took 300-600s per month against the same NASA
# LAADS server this session, sometimes timing out entirely. A quick manual
# test with luna::getNASA() downloaded the same tiles in ~19s. This script
# keeps blackmarbler only for what it does well -- converting a downloaded
# h5 tile into a properly-scaled, quality-filtered SpatRaster via its
# internal file_to_raster() -- and replaces just the download step with
# luna.
#
# Auth: luna::earthdataLogin() returns a session object holding a live
# httr handle (curl connection state) -- confirmed 2026-08-20 that
# saveRDS()/readRDS() silently corrupts this (every request then fails
# with HTTP 401, even though the credentials themselves are valid), since
# R's serialization cannot preserve the underlying C-level connection.
# The login must therefore happen fresh in the same process that uses it.
# The user sets EARTHDATA_USER / EARTHDATA_PASSWORD in their own shell
# before running this script (not entered by Claude, per this project's
# credential-handling policy):
#   export EARTHDATA_USER=...
#   export EARTHDATA_PASSWORD=...
#   Rscript 04_extraction/10_turkey_luna_blackmarble_monthly.R
#
# Window: 2022-02 to 2024-02 (12 months before/after 6 Feb 2023
# Kahramanmaras earthquake).
# Band: NearNadir_Composite_Snow_Free (blackmarbler's VNP46A3 default,
# matches 09_turkey_blackmarbler_monthly.R's convention exactly, so the
# two panels are directly comparable / can be spliced together for months
# where one source succeeded and the other didn't).
#
# Output: data/processed/ntl/turkey_luna_blackmarble_monthly_adm1.csv
#   Columns: region_id, NAME_1, year, month, viirs_ntl

library(sf)
library(terra)
library(exactextractr)
library(data.table)
library(luna)

edl_user <- Sys.getenv("EARTHDATA_USER")
edl_pass <- Sys.getenv("EARTHDATA_PASSWORD")
if (nchar(edl_user) == 0 || nchar(edl_pass) == 0) {
  stop(paste0(
    "Set EARTHDATA_USER and EARTHDATA_PASSWORD in your shell before running ",
    "this script (see comment above for the exact commands)."
  ))
}
auth <- luna::earthdataLogin(edl_user, edl_pass)
cat("Earthdata session created.\n")

# Same tile-grid caching fix as 00_utils/blackmarble_catalog.R's
# patch_blackmarble_tile_cache(), applied here to file_to_raster() instead
# of bm_raster_i() since that's the internal function this script calls
# directly -- without it, every single h5->raster conversion re-fetches
# the tile-grid geojson from GitHub.
tile_cache_file <- "data/raw/blackmarbletiles_cache.geojson"
if (!file.exists(tile_cache_file)) {
  dir.create(dirname(tile_cache_file), showWarnings = FALSE, recursive = TRUE)
  sf::write_sf(
    sf::read_sf("https://raw.githubusercontent.com/worldbank/blackmarbler/main/data/blackmarbletiles.geojson"),
    tile_cache_file
  )
}
ns <- asNamespace("blackmarbler")
f_orig <- ns$file_to_raster
src <- deparse(f_orig)
src <- sub(
  'read_sf\\("https://raw\\.githubusercontent\\.com/worldbank/blackmarbler/main/data/blackmarbletiles\\.geojson"\\)',
  sprintf('read_sf(%s)', deparse(tile_cache_file)),
  src
)
f_patched <- eval(parse(text = src), envir = environment(f_orig))
environment(f_patched) <- environment(f_orig)
unlockBinding("file_to_raster", ns)
assign("file_to_raster", f_patched, envir = ns)
lockBinding("file_to_raster", ns)

cat("=== Load Turkey ADM1 (GADM 4.1) ===\n")
adm1 <- sf::st_read("data/raw/gadm_4.1/turkey/gadm41_TUR_1.json", quiet = TRUE)
adm1 <- adm1[, c("GID_1", "NAME_1")]
data.table::setnames(adm1, "GID_1", "region_id")
adm1 <- sf::st_transform(adm1, 4326)
cat(sprintf("Provinces: %d\n", nrow(adm1)))

# Turkey bounding box, generous margin (aoi = latmin, latmax, lonmin, lonmax
# per luna::getNASA()'s convention).
aoi <- c(35.5, 42.5, 25.0, 45.0)

months <- seq(as.Date("2022-02-01"), as.Date("2024-02-01"), by = "month")
cat(sprintf("Months to process: %d (%s to %s)\n",
    length(months), format(months[1], "%Y-%m"), format(months[length(months)], "%Y-%m")))

h5_dir <- "data/raw/blackmarble_luna_h5"
dir.create(h5_dir, showWarnings = FALSE, recursive = TRUE)
out_dir <- "data/processed/ntl/turkey_luna_by_month"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

for (m in months) {
  m <- as.Date(m, origin = "1970-01-01")
  ym <- format(m, "%Y-%m")
  out_file <- file.path(out_dir, paste0(ym, ".csv"))
  if (file.exists(out_file)) { cat(sprintf("[%s] cached, skipping\n", ym)); next }

  start_d <- format(m, "%Y-%m-%d")
  end_d   <- format(seq(m, by = "month", length.out = 2)[2] - 1, "%Y-%m-%d")

  t0 <- Sys.time()
  h5_files <- tryCatch(
    luna::getNASA(product = "VNP46A3", start_date = start_d, end_date = end_d,
                  aoi = aoi, download = TRUE, path = h5_dir, server = "LAADS",
                  auth = auth, verbose = FALSE),
    error = function(e) { cat(sprintf("[%s] download FAILED: %s\n", ym, conditionMessage(e))); NULL }
  )
  if (is.null(h5_files) || length(h5_files) == 0) next

  # Keep only this month's own tiles (day-of-year in the filename) -- luna
  # returns the closest available granule per tile if the exact month is
  # missing, which could otherwise silently pull in an adjacent month.
  doy_wanted <- format(m, "%Y%j")
  h5_files <- h5_files[grepl(paste0("A", doy_wanted), h5_files)]
  if (length(h5_files) == 0) { cat(sprintf("[%s] no exact-month tiles returned\n", ym)); next }

  rasters <- lapply(h5_files, function(fp) {
    tryCatch(
      blackmarbler:::file_to_raster(fp, variable = "NearNadir_Composite_Snow_Free", quality_flag_rm = 2),
      error = function(e) { cat(sprintf("[%s] %s FAILED: %s\n", ym, basename(fp), conditionMessage(e))); NULL }
    )
  })
  rasters <- rasters[!sapply(rasters, is.null)]
  if (length(rasters) == 0) { cat(sprintf("[%s] no rasters produced\n", ym)); next }

  mosaic <- if (length(rasters) == 1) rasters[[1]] else do.call(terra::mosaic, c(rasters, fun = "mean"))

  vals <- exactextractr::exact_extract(mosaic, adm1, fun = "mean", progress = FALSE)
  dt <- data.table::data.table(
    region_id = adm1$region_id, NAME_1 = adm1$NAME_1,
    year = as.integer(format(m, "%Y")), month = as.integer(format(m, "%m")),
    viirs_ntl = vals
  )

  tmp_file <- paste0(out_file, ".tmp")
  data.table::fwrite(dt, tmp_file)
  file.rename(tmp_file, out_file)

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  cat(sprintf("[%s] rows=%d tiles=%d (%.1fs)\n", ym, nrow(dt), length(h5_files), elapsed))

  unlink(h5_files)
  rm(rasters, mosaic); gc(full = FALSE)
}

csv_files <- file.path(out_dir, paste0(format(months, "%Y-%m"), ".csv"))
if (all(file.exists(csv_files))) {
  panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
  data.table::fwrite(panel, "data/processed/ntl/turkey_luna_blackmarble_monthly_adm1.csv")
  cat(sprintf("\nPanel saved: %d rows, %d provinces, %d months\n",
      nrow(panel), data.table::uniqueN(panel$region_id), length(csv_files)))
} else {
  cat(sprintf("\nNot all months done (%d/%d) -- panel assembly skipped.\n",
      sum(file.exists(csv_files)), length(csv_files)))
}
