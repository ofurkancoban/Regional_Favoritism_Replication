# R/22_gee_export_dmsp_raster_submit.R
# Purpose: Submit GEE Export.image.toDrive tasks for the RAW DMSP-OLS
# stable_lights annual composites (1992-2013), full global extent, native
# resolution, no simplification, no zonal aggregation. This is raw pixel
# data -- one export task per year. GEE automatically shards each export
# into multiple GeoTIFF files if a single file would exceed its internal
# size limit, so no manual chunking is required.
#
# Rationale: matches the years/band already used as the canonical source
# for R/07_gee_dmsp_global.R (stable_lights, mean across satellites per
# year) so the downloaded rasters are a drop-in raw-data replacement for
# any future local terra::zonal()/terra::extract() pipeline -- eliminates
# the per-region synchronous GEE network round trip that is the current
# bottleneck for large/complex geometries (grid cells, hole-punched ADM1).
#
# One-shot: submits all tasks and exits. Does not monitor or restart.
# Run R/23_gee_monitor_dmsp_raster.R afterwards to track progress.
# Run R/24_gee_download_dmsp_raster.R whenever you want to pull completed
# rasters from Drive to local disk.

library(reticulate)
library(data.table)

source("R/utils/gee_helpers.R")
gee_initialize()
ee <- reticulate::import("ee")

years        <- 1992:2013
scale_m      <- 1000L  # DMSP-OLS native resolution ~1 km, matches R/07 scale_m
drive_folder <- "GEE_DMSP_Raw_Global"
task_log     <- "data/processed/ntl/dmsp_raster_task_log.csv"
dir.create("data/processed/ntl", showWarnings = FALSE, recursive = TRUE)

if (file.exists(task_log)) {
  tlog      <- data.table::fread(task_log)
  submitted <- tlog[status == "submitted", year]
  cat(sprintf("Already submitted: %d years\n", uniqueN(submitted)))
} else {
  tlog      <- data.table::data.table(year = integer(), task_id = character(),
                                       description = character(), status = character())
  submitted <- integer()
}

remaining <- years[!years %in% submitted]
cat(sprintf("%d years remaining: %s\n\n", length(remaining), paste(remaining, collapse = ",")))

submit_year <- function(yr) {
  desc <- sprintf("dmsp_stable_%d", yr)

  reticulate::py_run_string(sprintf("
import ee

_dmsp   = ee.ImageCollection('NOAA/DMSP-OLS/NIGHTTIME_LIGHTS').select('stable_lights')
_yr     = %d
_img    = _dmsp.filterDate(str(_yr) + '-01-01', str(_yr) + '-12-31').mean()
_region = ee.Geometry.Rectangle([-180, -65, 180, 75], 'EPSG:4326', False)

_task = ee.batch.Export.image.toDrive(
    image=_img,
    description='%s',
    folder='%s',
    fileNamePrefix='%s',
    region=_region,
    scale=%d,
    crs='EPSG:4326',
    maxPixels=1e13,
    fileFormat='GeoTIFF'
)
_task.start()
_task_id = _task.id
", yr, desc, drive_folder, desc, scale_m))

  list(status = "submitted", task_id = reticulate::py$`_task_id`, description = desc)
}

for (yr in remaining) {
  res <- tryCatch(submit_year(yr),
                   error = function(e) list(status = paste0("error:", conditionMessage(e)),
                                             task_id = NA, description = NA))
  cat(sprintf("%d  %s  task_id=%s\n", yr, res$status, res$task_id))
  tlog <- rbind(tlog, data.table::data.table(
    year        = yr,
    task_id     = if (!is.null(res$task_id) && !is.na(res$task_id)) res$task_id else NA_character_,
    description = if (!is.null(res$description)) res$description else NA_character_,
    status      = res$status
  ))
  data.table::fwrite(tlog, task_log)
}

cat("\n--- Submission summary ---\n")
print(tlog[, .N, by = status][order(-N)])
cat(sprintf("\nTask log: %s\n", task_log))
cat("Run R/23_gee_monitor_dmsp_raster.R to track progress in the console.\n")
cat("Run R/24_gee_download_dmsp_raster.R whenever you want to pull results to local disk.\n")
