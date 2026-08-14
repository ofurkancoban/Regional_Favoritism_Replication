# R/30_local_terra_dmsp_grid.R
# HR 2014 Table IV Col(4)-(7): zonal-mean stable_lights NTL over global
# rectangular grid cells (50/400 km), computed LOCALLY with terra from the
# raw DMSP-OLS GeoTIFFs downloaded in R/28 (no Google Earth Engine).
#
# Matches the canonical GEE methodology (R/07, R/21): per year, average
# across satellites when a year has two overlapping satellites (pixel-wise
# mean), band is the NOAA noise-cleaned "stable_lights" product.
#
# Extraction engine: exactextractr::exact_extract(), NOT terra::extract().
# terra::extract() was benchmarked at 19-26+ MINUTES for a single year's
# extract against the 400km grid (2131 cells) -- profiling (macOS `sample`)
# showed it rasterizes polygons over the ENTIRE raster extent on every call
# regardless of cell count, and retiling the source GeoTIFF (originally
# striped, Block=43201x1) did not fix it, so the bottleneck is terra's own
# extract() algorithm. exactextractr reads only each polygon's own
# bounding-box window and was benchmarked at ~11s for the same operation
# (~100x faster), with zero need to modify the raw raster files.
#
# Cell-inclusion rule: a custom `majority_rule` summary function keeps only
# pixels whose coverage_fraction >= 0.5 (majority of pixel area inside the
# polygon) and takes a plain mean over those -- this approximates terra's
# cell-center-in-polygon rule (exact=FALSE), which was chosen to match the
# canonical GEE pipeline's reduceRegions(mean()) pixel-sampling reducer
# used for Tables II/III, rather than exactextractr's own default (fully
# sub-pixel area-weighted mean, methodologically equivalent to terra's much
# slower exact=TRUE). Empirically validated against terra's true
# cell-center output on a 20-cell subset: max abs diff dropped from ~0.0011
# (area-weighted default) to ~0.0007 (majority_rule), with most cells
# matching to near machine precision -- residual differences are genuine
# sub-pixel boundary cases, negligible at DMSP's ~1km resolution relative
# to 50/400km grid cells.
#
# Architecture: year-outer-loop, one exact_extract() call per year across
# ALL grid cells at once.
#
# Run as two separate invocations, one per resolution (400km first, then
# 50km -- see R/32_run_sequential_dmsp_local.sh), rather than a single
# process handling both.
#
# Usage: Rscript R/30_local_terra_dmsp_grid.R <resolution_km> [year1,year2,...]
# Output: data/processed/ntl/grid_<res>km_dmsp_local_by_year/<year>.csv
#         data/processed/ntl/grid_<res>km_stable_global_panel_local.csv (assembled)

library(terra)
library(sf)
library(data.table)
library(exactextractr)

# Approximates terra::extract(exact=FALSE)'s cell-center-in-polygon rule:
# keep only pixels where >=50% of the pixel's area falls inside the
# polygon, then take a plain (unweighted) mean over those pixels.
majority_rule <- function(values, coverage_fraction) {
  keep <- coverage_fraction >= 0.5
  if (!any(keep)) return(NA_real_)
  mean(values[keep], na.rm = TRUE)
}

# stdout is block-buffered (not line-buffered) when redirected to a file,
# so plain cat() calls can sit unwritten for a long time during a slow
# per-year loop. log_msg() flushes after every message so log files (e.g.
# via `Rscript ... > file.log 2>&1 &`) update in near-real-time.
log_msg <- function(...) { cat(...); flush.console() }

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript R/30_local_terra_dmsp_grid.R <resolution_km> [year1,year2,...]")
RES_KM <- as.integer(args[1])

raw_root <- "data/raw/dmsp_raster_eog_manual"
out_dir  <- sprintf("data/processed/ntl/grid_%dkm_dmsp_local_by_year", RES_KM)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Same year -> satellite(s) catalog as R/28
year_sat <- list(
  "1992" = "F10", "1993" = "F10",
  "1994" = c("F10", "F12"),
  "1995" = "F12", "1996" = "F12",
  "1997" = c("F12", "F14"), "1998" = c("F12", "F14"), "1999" = c("F12", "F14"),
  "2000" = c("F14", "F15"), "2001" = c("F14", "F15"),
  "2002" = c("F14", "F15"), "2003" = c("F14", "F15"),
  "2004" = c("F15", "F16"), "2005" = c("F15", "F16"),
  "2006" = c("F15", "F16"), "2007" = c("F15", "F16"),
  "2008" = "F16", "2009" = "F16",
  "2010" = "F18", "2011" = "F18", "2012" = "F18", "2013" = "F18"
)

version_suffix <- function(sat, yr) {
  ifelse(sat == "F18", ifelse(yr == "2010", "v4d", "v4c"), "v4b")
}
year_file <- function(sat, yr) {
  vs <- version_suffix(sat, yr)
  sprintf("%s/%s/%s%s.%s.global.stable_lights.avg_vis.tif", raw_root, yr, sat, yr, vs)
}

log_msg(sprintf("=== Load %d km grid cells ===\n", RES_KM))
sf::sf_use_s2(FALSE)
grid <- sf::st_read(sprintf("data/processed/grid_cells_%dkm.gpkg", RES_KM), quiet = TRUE)
sf::st_geometry(grid) <- "geometry"
grid <- sf::st_transform(grid, 4326)
log_msg(sprintf("Grid cells: %d | countries: %d\n", nrow(grid), data.table::uniqueN(grid$GID_0)))

grid <- grid[, c("grid_id", "GID_0")]

years <- names(year_sat)
if (length(args) >= 2) {
  requested <- strsplit(args[2], ",")[[1]]
  years <- intersect(years, requested)
}

log_msg(sprintf("Processing %d years (%d km grid): %s\n\n", length(years), RES_KM, paste(years, collapse = ",")))

for (yr in years) {
  out_file <- file.path(out_dir, paste0(yr, ".csv"))
  if (file.exists(out_file)) {
    log_msg(sprintf("[%s] cached, skipping\n", yr))
    next
  }

  sats  <- year_sat[[yr]]
  files <- year_file(sats, yr)
  if (!all(file.exists(files))) {
    log_msg(sprintf("[%s] MISSING raw file(s): %s -- skipping\n", yr,
        paste(files[!file.exists(files)], collapse = ", ")))
    next
  }

  t0 <- Sys.time()
  rasters <- lapply(files, terra::rast)
  img <- if (length(rasters) == 1) rasters[[1]] else terra::app(terra::rast(rasters), mean, na.rm = TRUE)

  ex <- exactextractr::exact_extract(img, grid, fun = majority_rule, progress = FALSE)
  dt <- data.table::data.table(
    grid_id            = grid$grid_id,
    iso3               = grid$GID_0,
    year               = as.integer(yr),
    dmsp_stable_lights = ex
  )
  dt <- dt[!is.na(dmsp_stable_lights)]

  tmp_file <- paste0(out_file, ".tmp")
  data.table::fwrite(dt, tmp_file)
  file.rename(tmp_file, out_file)

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  log_msg(sprintf("[%s] sats=%s rows=%d (%.1fs)\n", yr, paste(sats, collapse = "+"), nrow(dt), elapsed))

  rm(rasters, img, ex, dt)
  terra::tmpFiles(remove = TRUE)
  gc(full = TRUE)
}

# Only assemble the full panel if ALL years are present -- avoids a partial
# panel silently overwriting a complete one when run on a year subset.
all_years <- names(year_sat)
csv_files <- file.path(out_dir, paste0(all_years, ".csv"))
if (all(file.exists(csv_files))) {
  log_msg("\nAll years present -- assembling local DMSP grid panel...\n")
  panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
  out_panel <- sprintf("data/processed/ntl/grid_%dkm_stable_global_panel_local.csv", RES_KM)
  data.table::fwrite(panel, out_panel)
  log_msg(sprintf("Panel saved: %s (%d rows, %d countries, %d years)\n",
      out_panel, nrow(panel), data.table::uniqueN(panel$iso3), data.table::uniqueN(panel$year)))
} else {
  missing <- all_years[!file.exists(csv_files)]
  log_msg(sprintf("\nNot all years done yet (missing: %s) -- panel assembly skipped.\n",
      paste(missing, collapse = ",")))
}
