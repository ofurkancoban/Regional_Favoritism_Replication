# 00_utils/local_ntl_extraction.R
# Shared local (non-GEE) nighttime-lights zonal-extraction engine.
#
# Replaces every remaining Google Earth Engine `reduceRegions()` zonal-mean
# step in this project (ADM2, ADM1 full-area, ADM1 hole-punched, VIIRS ADM2)
# with a single reusable local pipeline built on the same architecture
# validated for the grid-cell extraction (04_extraction/04_dmsp_grid_cells.R):
#
#   - year-outer-loop: each year's raster is opened and decoded exactly once
#     (terra::extract() was benchmarked at 19-26+ minutes for a single call
#     against a small polygon set because it rasterizes the ENTIRE raster
#     extent regardless of how few polygons are requested -- exactextractr's
#     exact_extract() reads only each polygon's own bounding-box window,
#     ~100x faster for the same operation)
#   - `majority_rule` summary function: keeps only pixels whose
#     coverage_fraction >= 0.5 and takes a plain mean, approximating
#     terra::extract(exact=FALSE)'s cell-center-in-polygon rule -- this is
#     what GEE's own reduceRegions(mean()) reducer effectively did (pixel
#     sampling, not sub-pixel area-weighting), so using exactextractr's own
#     area-weighted default here would silently change methodology.
#     Empirically validated against terra's true cell-center output: max
#     abs difference ~0.0007 on a 20-cell test subset.
#   - per-year resume-cache: each year's zonal-mean CSV is written once and
#     skipped on re-run; the full panel is assembled once every year exists.
#
# Multi-satellite years (DMSP only): when a year's raster catalog resolves
# to more than one file (e.g. two overlapping DMSP-OLS satellites), the
# rasters are pixel-wise averaged (terra::app(mean, na.rm=TRUE)) BEFORE
# extraction -- identical to the canonical GEE approach of averaging the
# ImageCollection with .mean() across satellite images within a calendar
# year (HR 2014 p.998 uses the same NOAA-composited annual mean).

library(terra)
library(sf)
library(data.table)
library(exactextractr)

#' Approximates terra::extract(exact=FALSE)'s cell-center-in-polygon rule.
majority_rule <- function(values, coverage_fraction) {
  keep <- coverage_fraction >= 0.5
  if (!any(keep)) return(NA_real_)
  mean(values[keep], na.rm = TRUE)
}

#' Extract a zonal-mean NTL panel locally, year by year, resume-safe.
#'
#' @param polygons   sf object with the zonal units (ADM2, ADM1, grid cells...).
#' @param id_col     name of the unique-ID column in `polygons` to carry through.
#' @param extra_cols additional columns from `polygons` to carry through (e.g. country code).
#' @param years      integer vector of years to process.
#' @param year_files function(year) -> character vector of raster file path(s)
#'                    for that year (length > 1 triggers pixel-wise averaging).
#' @param value_col  name to give the extracted zonal-mean column in the output.
#' @param out_dir    directory for per-year cache CSVs + assembled panel.
#' @param panel_name file name (within out_dir's parent) for the assembled panel.
#' @param log_msg    logging function (default: flushed cat, safe for redirected logs).
#' @return           invisible(NULL); writes files as a side effect.
extract_ntl_panel <- function(polygons, id_col, extra_cols = character(0),
                               years, year_files, value_col,
                               out_dir, panel_name,
                               log_msg = function(...) { cat(...); flush.console() }) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  keep_cols <- c(id_col, extra_cols)
  polygons <- polygons[, keep_cols]

  for (yr in years) {
    out_file <- file.path(out_dir, paste0(yr, ".csv"))
    if (file.exists(out_file)) {
      log_msg(sprintf("[%s] cached, skipping\n", yr))
      next
    }

    files <- year_files(yr)
    if (length(files) == 0 || !all(file.exists(files))) {
      log_msg(sprintf("[%s] MISSING raw file(s): %s -- skipping\n", yr,
          paste(files[!file.exists(files)], collapse = ", ")))
      next
    }

    t0 <- Sys.time()
    rasters <- lapply(files, terra::rast)
    img <- if (length(rasters) == 1) rasters[[1]] else terra::app(terra::rast(rasters), mean, na.rm = TRUE)

    ex <- exactextractr::exact_extract(img, polygons, fun = majority_rule, progress = FALSE)
    dt <- data.table::as.data.table(sf::st_drop_geometry(polygons))
    dt[, year := as.integer(yr)]
    dt[[value_col]] <- ex
    dt <- dt[!is.na(get(value_col))]

    tmp_file <- paste0(out_file, ".tmp")
    data.table::fwrite(dt, tmp_file)
    file.rename(tmp_file, out_file)

    elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
    log_msg(sprintf("[%s] sats=%d rows=%d (%.1fs)\n", yr, length(files), nrow(dt), elapsed))

    rm(rasters, img, ex, dt)
    terra::tmpFiles(remove = TRUE)
    gc(full = TRUE)
  }

  csv_files <- file.path(out_dir, paste0(years, ".csv"))
  if (all(file.exists(csv_files))) {
    log_msg("\nAll years present -- assembling panel...\n")
    panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
    data.table::fwrite(panel, panel_name)
    log_msg(sprintf("Panel saved: %s (%d rows, %d %s, %d years)\n",
        panel_name, nrow(panel), data.table::uniqueN(panel[[id_col]]), id_col,
        data.table::uniqueN(panel$year)))
  } else {
    missing <- years[!file.exists(csv_files)]
    log_msg(sprintf("\nNot all years done yet (missing: %s) -- panel assembly skipped.\n",
        paste(missing, collapse = ",")))
  }
  invisible(NULL)
}
