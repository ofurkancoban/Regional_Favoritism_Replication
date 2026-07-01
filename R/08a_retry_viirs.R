# R/08a_retry_viirs.R
# Purpose: retry VIIRS countries that failed due to payload size.
# Uses adaptive chunk sizing (no simplification).

library(reticulate)
library(sf)
library(data.table)

source("R/utils/gee_helpers.R")
gee_initialize()
ee <- reticulate::import("ee")

gb_dir       <- "data/raw/gadm_4.1/global/geoboundaries"
task_log     <- "data/processed/ntl/viirs_task_log.csv"
drive_folder <- "GEE_VIIRS_Global"
years        <- 2012:2024

tlog   <- data.table::fread(task_log)
failed <- tlog[grepl("error|chunk_too_large|pending_retry|still_too_large", status) & !iso3 %in% c("HKG", "XNC"), iso3]
cat("Retrying:", paste(failed, collapse = ", "), "\n\n")

submit_viirs_chunk <- function(iso3, sf_chunk, chunk_idx, id_col, adm_level) {
  sf_sub <- sf::st_transform(sf_chunk[, c(id_col, "geometry")], 4326)
  tmp    <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")
  if (nchar(gjson) / 1e6 > 8) return(list(status = "still_too_large", task_id = NA))

  reticulate::py_run_string(paste0(
    "import json, ee\n",
    "_fc = ee.FeatureCollection(json.loads('",
    gsub("'", "\\'", gjson, fixed = TRUE), "'))"
  ))

  desc <- sprintf("viirs_%s_%s", iso3, chunk_idx)

  reticulate::py_run_string(sprintf("
import ee
_vc1 = ee.ImageCollection('NOAA/VIIRS/DNB/MONTHLY_V1/VCMCFG').select('avg_rad')
_vc2 = ee.ImageCollection('NOAA/VIIRS/DNB/MONTHLY_V1/VCMSLCFG').select('avg_rad')
_yrs = [%s]
_iso3 = '%s'; _id = '%s'; _adm = '%s'

def _f(yr):
    yr  = ee.Number(yr).toInt()
    col = ee.ImageCollection(ee.Algorithms.If(
        yr.lte(2013),
        _vc1.filter(ee.Filter.calendarRange(yr, yr, 'year')),
        _vc2.filter(ee.Filter.calendarRange(yr, yr, 'year'))
    ))
    r = col.mean().reduceRegions(collection=_fc, reducer=ee.Reducer.mean(), scale=500)
    return r.map(lambda f: f.set({'year': yr, 'iso3': _iso3, 'adm_level': _adm, 'region_id': f.get(_id)}))

_all  = ee.FeatureCollection(ee.List(_yrs).map(_f)).flatten()
_task = ee.batch.Export.table.toDrive(
    collection=_all, description='%s', folder='%s',
    fileNamePrefix='%s', fileFormat='CSV',
    selectors=['region_id','iso3','adm_level','year','mean']
)
_task.start()
_tid = _task.id
", paste(years, collapse = ","), iso3, id_col, adm_level, desc, drive_folder, desc))

  list(status = "submitted", task_id = reticulate::py$`_tid`, description = desc)
}

for (iso3 in failed) {
  adm2_f <- file.path(gb_dir, paste0(iso3, "_ADM2.geojson"))
  adm1_f <- file.path(gb_dir, paste0(iso3, "_ADM1.geojson"))
  geo_f  <- if (file.exists(adm2_f)) adm2_f else if (file.exists(adm1_f)) adm1_f else {
    cat(iso3, "no_file\n"); next
  }
  sf_obj <- tryCatch(sf::st_read(geo_f, quiet = TRUE), error = function(e) NULL)
  if (is.null(sf_obj)) next

  id_col    <- if ("GID_2"   %in% names(sf_obj)) "GID_2"   else
               if ("GID_1"   %in% names(sf_obj)) "GID_1"   else
               if ("shapeID" %in% names(sf_obj)) "shapeID" else names(sf_obj)[1]
  adm_level <- if (grepl("ADM2", geo_f)) "ADM2" else "ADM1"
  n_feat    <- nrow(sf_obj)

  # Find smallest chunk size that fits under 9 MB
  eff_chunk <- 1L
  for (try_size in c(50L, 20L, 10L, 5L, 2L, 1L)) {
    test  <- sf::st_transform(sf_obj[1:min(try_size, n_feat), c(id_col, "geometry")], 4326)
    tmp_t <- tempfile(fileext = ".geojson")
    sf::st_write(test, tmp_t, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
    mb <- file.size(tmp_t) / 1e6; unlink(tmp_t)
    if (mb <= 8) { eff_chunk <- try_size; break }
  }

  n_chunks <- ceiling(n_feat / eff_chunk)
  cat(sprintf("%-6s  %d features -> %d chunks (size=%d)\n", iso3, n_feat, n_chunks, eff_chunk))

  # Submit with per-chunk size check: if chunk too large, split recursively down to 1
  submit_with_check <- function(sf_slice, chunk_label) {
    sf_sub <- sf::st_transform(sf_slice[, c(id_col, "geometry")], 4326)
    tmp    <- tempfile(fileext = ".geojson")
    sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
    mb <- file.size(tmp) / 1e6; unlink(tmp)

    if (mb <= 8) {
      res <- tryCatch(
        submit_viirs_chunk(iso3, sf_slice, chunk_label, id_col, adm_level),
        error = function(e) list(status = paste0("error:", conditionMessage(e)), task_id = NA)
      )
      cat(sprintf("    [%s] %d feat %.1fMB: %s\n", chunk_label, nrow(sf_slice), mb, res$status))
      tlog <<- rbind(tlog, data.table::data.table(
        iso3        = iso3,
        task_id     = if (!is.null(res$task_id) && !is.na(res$task_id)) res$task_id else NA_character_,
        description = if (!is.null(res$description)) res$description else NA_character_,
        status      = res$status
      ))
      data.table::fwrite(tlog, task_log)
    } else if (nrow(sf_slice) == 1) {
      cat(sprintf("    [%s] single feature %.1fMB: skipped (geometry too large)\n", chunk_label, mb))
    } else {
      # Split in half and recurse
      mid <- floor(nrow(sf_slice) / 2)
      submit_with_check(sf_slice[1:mid, ],          paste0(chunk_label, "a"))
      submit_with_check(sf_slice[(mid+1):nrow(sf_slice), ], paste0(chunk_label, "b"))
    }
  }

  global_ci <- 1L
  for (ci in seq_len(n_chunks)) {
    idx <- ((ci - 1) * eff_chunk + 1):min(ci * eff_chunk, n_feat)
    cat(sprintf("  chunk %02d/%02d (%d feat):\n", ci, n_chunks, length(idx)))
    submit_with_check(sf_obj[idx, ], global_ci)
    global_ci <- global_ci + 1L
  }
}

cat("\nDone. Submitted tasks:", tlog[status == "submitted", .N], "\n")
