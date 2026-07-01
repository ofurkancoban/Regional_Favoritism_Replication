# R/07a_retry_large.R
# Purpose: retry failed countries by chunking FeatureCollection into batches of 300.
# Fixes the 10MB GEE payload limit for large countries (AUS, BRA, CHN, IND, etc.)

library(reticulate)
library(sf)
library(data.table)

source("R/utils/gee_helpers.R")
gee_initialize()
ee <- reticulate::import("ee")

gb_dir       <- "data/raw/gadm_4.1/global/geoboundaries"
task_log     <- "data/processed/ntl/dmsp_task_log.csv"
drive_folder <- "GEE_DMSP_Global"
years        <- 1992:2013
scale_m      <- 1000L
chunk_size   <- 300L

no_adm2 <- if (file.exists("data/raw/gadm_4.1/global/no_adm2_countries.txt"))
  readLines("data/raw/gadm_4.1/global/no_adm2_countries.txt") else character(0)

tlog    <- data.table::fread(task_log)
failed  <- tlog[grepl("error", status), iso3]
cat("Retrying", length(failed), "countries with chunking:", paste(failed, collapse = ", "), "\n\n")

submit_chunk <- function(iso3, sf_chunk, chunk_idx, id_col, adm_level) {
  sf_sub <- sf_chunk[, c(id_col, "geometry")]
  sf_sub <- sf::st_transform(sf_sub, 4326)
  tmp    <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")

  mb <- round(nchar(gjson) / 1e6, 2)
  if (mb > 9) return(list(status = "chunk_too_large", task_id = NA))

  reticulate::py_run_string(paste0(
    "import json, ee\n",
    "_fc = ee.FeatureCollection(json.loads('",
    gsub("'", "\\'", gjson, fixed = TRUE), "'))"
  ))
  fc <- reticulate::py$`_fc`

  desc <- sprintf("dmsp_%s_%03d", iso3, chunk_idx)

  reticulate::py_run_string(sprintf("
import ee
_dmsp = ee.ImageCollection('NOAA/DMSP-OLS/NIGHTTIME_LIGHTS').select('avg_vis')
_years = [%s]
_iso3  = '%s'
_id_col = '%s'
_adm_level = '%s'

def _process_year(yr):
    yr = ee.Number(yr).toInt()
    img = _dmsp.filter(ee.Filter.calendarRange(yr, yr, 'year')).mean()
    reduced = img.reduceRegions(collection=_fc, reducer=ee.Reducer.mean(), scale=1000)
    return reduced.map(lambda f: f.set({
        'year': yr, 'iso3': _iso3, 'adm_level': _adm_level,
        'region_id': f.get(_id_col)
    }))

_all  = ee.FeatureCollection(ee.List(_years).map(_process_year)).flatten()
_task = ee.batch.Export.table.toDrive(
    collection=_all, description='%s', folder='%s',
    fileNamePrefix='%s', fileFormat='CSV',
    selectors=['region_id','iso3','adm_level','year','mean']
)
_task.start()
_task_id = _task.id
", paste(years, collapse = ","), iso3, id_col, adm_level, desc, drive_folder, desc))

  list(status = "submitted", task_id = reticulate::py$`_task_id`, description = desc)
}

new_rows <- list()

for (iso3 in failed) {
  adm2_f <- file.path(gb_dir, paste0(iso3, "_ADM2.geojson"))
  adm1_f <- file.path(gb_dir, paste0(iso3, "_ADM1.geojson"))
  geo_f  <- if (!iso3 %in% no_adm2 && file.exists(adm2_f)) adm2_f else
            if (file.exists(adm1_f)) adm1_f else { cat(iso3, "no_file\n"); next }

  sf_obj <- tryCatch(sf::st_read(geo_f, quiet = TRUE), error = function(e) NULL)
  if (is.null(sf_obj)) { cat(iso3, "read_error\n"); next }

  id_col    <- if ("GID_2" %in% names(sf_obj)) "GID_2" else
               if ("GID_1" %in% names(sf_obj)) "GID_1" else
               if ("shapeID" %in% names(sf_obj)) "shapeID" else names(sf_obj)[1]
  adm_level <- if (grepl("ADM2", geo_f)) "ADM2" else "ADM1"

  n_feat <- nrow(sf_obj)

  # Auto-tune chunk size: try 300, then halve until chunks fit under 9 MB
  effective_chunk <- chunk_size
  for (try_size in c(300L, 100L, 50L, 20L, 10L, 5L, 1L)) {
    test_idx   <- 1:min(try_size, n_feat)
    test_chunk <- sf_obj[test_idx, c(id_col, "geometry")]
    test_chunk <- sf::st_transform(test_chunk, 4326)
    tmp_t <- tempfile(fileext = ".geojson")
    sf::st_write(test_chunk, tmp_t, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
    mb_t  <- round(file.size(tmp_t) / 1e6, 2)
    unlink(tmp_t)
    if (mb_t <= 9) { effective_chunk <- try_size; break }
  }

  n_chunks <- ceiling(n_feat / effective_chunk)
  cat(sprintf("%-6s  %d features -> %d chunks (chunk_size=%d)\n", iso3, n_feat, n_chunks, effective_chunk))

  for (ci in seq_len(n_chunks)) {
    idx   <- ((ci - 1) * effective_chunk + 1):min(ci * effective_chunk, n_feat)
    chunk <- sf_obj[idx, ]
    res   <- tryCatch(submit_chunk(iso3, chunk, ci, id_col, adm_level),
                      error = function(e) list(status = paste0("error:", conditionMessage(e)), task_id = NA))
    cat(sprintf("  chunk %02d/%02d: %s\n", ci, n_chunks, res$status))
    new_rows[[length(new_rows) + 1]] <- data.table::data.table(
      iso3        = iso3,
      task_id     = if (!is.na(res$task_id)) res$task_id else NA_character_,
      description = if (!is.null(res$description)) res$description else NA_character_,
      status      = res$status
    )
  }
  # Mark original error row as replaced
  tlog[iso3 == iso3 & grepl("error", status), status := "replaced"]
}

# Append new chunk rows to log
tlog <- rbind(tlog, data.table::rbindlist(new_rows, fill = TRUE))
data.table::fwrite(tlog, task_log)
cat("\nTask log updated:", task_log, "\n")
cat("Submitted tasks:", tlog[status == "submitted", .N], "\n")
cat("Now run 07b_gee_dmsp_download.R to monitor and download.\n")
