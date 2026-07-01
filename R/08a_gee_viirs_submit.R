# R/08a_gee_viirs_submit.R
# Purpose: Submit GEE Export.table.toDrive tasks for VIIRS avg_rad (2012-2024).
# Two collections: VCMCFG (2012-2013), VCMSLCFG (2014-2024), band avg_rad.
# One task per country (chunked for large countries).
# Resume-safe via task log.

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
scale_m      <- 500L   # VIIRS native ~500 m
chunk_size   <- 300L

no_adm2 <- if (file.exists("data/raw/gadm_4.1/global/no_adm2_countries.txt"))
  readLines("data/raw/gadm_4.1/global/no_adm2_countries.txt") else character(0)

plad  <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

if (file.exists(task_log)) {
  tlog      <- data.table::fread(task_log)
  submitted <- tlog[status == "submitted", iso3]
  cat(sprintf("Already submitted: %d countries\n", uniqueN(submitted)))
} else {
  tlog      <- data.table::data.table(iso3 = character(), task_id = character(),
                                       description = character(), status = character())
  submitted <- character()
}

remaining <- iso3s[!iso3s %in% submitted]
cat(sprintf("%d countries remaining.\n\n", length(remaining)))

submit_chunk <- function(iso3, sf_chunk, chunk_idx, id_col, adm_level) {
  sf_sub <- sf_chunk[, c(id_col, "geometry")]
  sf_sub <- sf::st_transform(sf_sub, 4326)
  tmp    <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")

  if (nchar(gjson) / 1e6 > 9) return(list(status = "chunk_too_large", task_id = NA))

  reticulate::py_run_string(paste0(
    "import json, ee\n",
    "_fc = ee.FeatureCollection(json.loads('",
    gsub("'", "\\'", gjson, fixed = TRUE), "'))"
  ))

  desc <- if (chunk_idx == 1 && ceiling(nrow(sf_chunk) / chunk_size) <= 1) {
    paste0("viirs_", iso3)
  } else {
    sprintf("viirs_%s_%03d", iso3, chunk_idx)
  }

  reticulate::py_run_string(sprintf("
import ee

# VIIRS: VCMCFG for 2012-2013, VCMSLCFG for 2014+
_vcmcfg    = ee.ImageCollection('NOAA/VIIRS/DNB/MONTHLY_V1/VCMCFG').select('avg_rad')
_vcmslcfg  = ee.ImageCollection('NOAA/VIIRS/DNB/MONTHLY_V1/VCMSLCFG').select('avg_rad')
_years     = [%s]
_iso3      = '%s'
_id_col    = '%s'
_adm_level = '%s'

def _viirs_annual(yr):
    yr     = ee.Number(yr).toInt()
    yr_str = ee.Number(yr).format('%%d')
    col    = ee.ImageCollection(
        ee.Algorithms.If(
            yr.lte(2013),
            _vcmcfg.filter(ee.Filter.calendarRange(yr, yr, 'year')),
            _vcmslcfg.filter(ee.Filter.calendarRange(yr, yr, 'year'))
        )
    )
    img = col.mean()
    reduced = img.reduceRegions(collection=_fc, reducer=ee.Reducer.mean(), scale=500)
    return reduced.map(lambda f: f.set({
        'year': yr, 'iso3': _iso3, 'adm_level': _adm_level,
        'region_id': f.get(_id_col)
    }))

_all  = ee.FeatureCollection(ee.List(_years).map(_viirs_annual)).flatten()
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

for (iso3 in remaining) {
  adm2_f <- file.path(gb_dir, paste0(iso3, "_ADM2.geojson"))
  adm1_f <- file.path(gb_dir, paste0(iso3, "_ADM1.geojson"))
  geo_f  <- if (!iso3 %in% no_adm2 && file.exists(adm2_f)) adm2_f else
            if (file.exists(adm1_f)) adm1_f else {
              tlog <- rbind(tlog, data.table::data.table(iso3=iso3, task_id=NA_character_,
                            description=NA_character_, status="no_file"))
              data.table::fwrite(tlog, task_log)
              cat(sprintf("%-6s  no_file\n", iso3)); next
            }

  sf_obj <- tryCatch(sf::st_read(geo_f, quiet = TRUE), error = function(e) NULL)
  if (is.null(sf_obj)) { cat(iso3, "read_error\n"); next }

  id_col    <- if ("GID_2"   %in% names(sf_obj)) "GID_2"   else
               if ("GID_1"   %in% names(sf_obj)) "GID_1"   else
               if ("shapeID" %in% names(sf_obj)) "shapeID" else names(sf_obj)[1]
  adm_level <- if (grepl("ADM2", geo_f)) "ADM2" else "ADM1"
  n_feat    <- nrow(sf_obj)

  # Auto-tune chunk size
  eff_chunk <- chunk_size
  for (try_size in c(300L, 100L, 50L, 20L, 10L, 5L, 1L)) {
    test <- sf_obj[1:min(try_size, n_feat), c(id_col, "geometry")]
    test <- sf::st_transform(test, 4326)
    tmp_t <- tempfile(fileext = ".geojson")
    sf::st_write(test, tmp_t, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
    mb <- file.size(tmp_t) / 1e6
    unlink(tmp_t)
    if (mb <= 9) { eff_chunk <- try_size; break }
  }

  n_chunks <- ceiling(n_feat / eff_chunk)
  cat(sprintf("%-6s  %d features -> %d chunks\n", iso3, n_feat, n_chunks))

  for (ci in seq_len(n_chunks)) {
    idx   <- ((ci - 1) * eff_chunk + 1):min(ci * eff_chunk, n_feat)
    res   <- tryCatch(submit_chunk(iso3, sf_obj[idx, ], ci, id_col, adm_level),
                      error = function(e) list(status = paste0("error:", conditionMessage(e)),
                                               task_id = NA, description = NA))
    cat(sprintf("  chunk %02d/%02d: %s\n", ci, n_chunks, res$status))
    new_rows[[length(new_rows) + 1]] <- data.table::data.table(
      iso3        = iso3,
      task_id     = if (!is.null(res$task_id) && !is.na(res$task_id)) res$task_id else NA_character_,
      description = if (!is.null(res$description)) res$description else NA_character_,
      status      = res$status
    )
  }

  tlog <- rbind(tlog, data.table::rbindlist(new_rows[sapply(new_rows, function(x) x$iso3 == iso3)], fill = TRUE))
  data.table::fwrite(tlog, task_log)
  new_rows <- new_rows[!sapply(new_rows, function(x) x$iso3 == iso3)]
}

cat("\n--- Submission summary ---\n")
print(tlog[, .N, by = status][order(-N)])
cat(sprintf("\nTask log: %s\n", task_log))
cat("Run 08b_gee_viirs_download.R to monitor and download.\n")
