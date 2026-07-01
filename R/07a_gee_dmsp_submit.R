# R/07a_gee_dmsp_submit.R
# Purpose: Submit GEE Export.table.toDrive tasks for DMSP-OLS (1992-2013).
# One task per country -- all 22 years combined into one FeatureCollection.
# Results go to Google Drive folder "GEE_DMSP_Global".
# Resume-safe: already-submitted countries are skipped via task log.
# Run 07b_gee_dmsp_download.R after tasks complete to fetch CSVs from Drive.

library(reticulate)
library(sf)
library(data.table)

source("R/utils/gee_helpers.R")
gee_initialize()
ee <- reticulate::import("ee")

gb_dir    <- "data/raw/gadm_4.1/global/geoboundaries"
task_log  <- "data/processed/ntl/dmsp_task_log.csv"
drive_folder <- "GEE_DMSP_Global"
years     <- 1992:2013
scale_m   <- 1000L

dir.create("data/processed/ntl", showWarnings = FALSE, recursive = TRUE)

no_adm2 <- if (file.exists("data/raw/gadm_4.1/global/no_adm2_countries.txt"))
  readLines("data/raw/gadm_4.1/global/no_adm2_countries.txt") else character(0)

plad  <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

# Load task log for resume
if (file.exists(task_log)) {
  tlog <- data.table::fread(task_log)
  submitted <- tlog$iso3
  cat(sprintf("Already submitted: %d / %d\n", length(submitted), length(iso3s)))
} else {
  tlog <- data.table::data.table(iso3 = character(), task_id = character(),
                                  description = character(), status = character())
  submitted <- character()
}

remaining <- iso3s[!iso3s %in% submitted]
cat(sprintf("%d countries to submit.\n\n", length(remaining)))

dmsp_col <- ee$ImageCollection("NOAA/DMSP-OLS/NIGHTTIME_LIGHTS")$select("avg_vis")

submit_country <- function(iso3) {
  adm2_f <- file.path(gb_dir, paste0(iso3, "_ADM2.geojson"))
  adm1_f <- file.path(gb_dir, paste0(iso3, "_ADM1.geojson"))
  geo_f  <- if (!iso3 %in% no_adm2 && file.exists(adm2_f)) adm2_f else
            if (file.exists(adm1_f)) adm1_f else return(list(status = "no_file"))

  sf_obj <- tryCatch(sf::st_read(geo_f, quiet = TRUE), error = function(e) NULL)
  if (is.null(sf_obj) || nrow(sf_obj) == 0) return(list(status = "read_error"))

  # Determine ID column
  id_col <- if ("GID_2"     %in% names(sf_obj)) "GID_2"   else
            if ("GID_1"     %in% names(sf_obj)) "GID_1"   else
            if ("shapeID"   %in% names(sf_obj)) "shapeID" else names(sf_obj)[1]
  adm_level <- if (grepl("ADM2", geo_f)) "ADM2" else "ADM1"

  # Build GEE FeatureCollection (no simplification needed for server-side export)
  sf_sub <- sf_obj[, c(id_col, "geometry")]
  sf_sub <- sf::st_transform(sf_sub, 4326)
  tmp    <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")

  reticulate::py_run_string(paste0(
    "import json, ee\n",
    "_fc = ee.FeatureCollection(json.loads('",
    gsub("'", "\\'", gjson, fixed = TRUE),
    "'))"
  ))
  fc <- reticulate::py$`_fc`

  # Map over years: reduceRegions for each year, tag with year + iso3
  reticulate::py_run_string(sprintf("
import ee
_dmsp = ee.ImageCollection('NOAA/DMSP-OLS/NIGHTTIME_LIGHTS').select('avg_vis')
_years = %s
_iso3  = '%s'
_id_col = '%s'
_adm_level = '%s'

def _process_year(yr):
    yr = ee.Number(yr).toInt()
    yr_str = ee.Number(yr).format('%%d')
    img = _dmsp.filter(ee.Filter.calendarRange(yr, yr, 'year')).mean()
    reduced = img.reduceRegions(
        collection = _fc,
        reducer    = ee.Reducer.mean(),
        scale      = 1000
    )
    return reduced.map(lambda f: f.set({
        'year': yr,
        'iso3': _iso3,
        'adm_level': _adm_level,
        'region_id': f.get(_id_col)
    }))

_all = ee.FeatureCollection(ee.List(_years).map(_process_year)).flatten()
", paste0("[", paste(years, collapse = ","), "]"), iso3, id_col, adm_level))

  desc <- paste0("dmsp_", iso3)
  reticulate::py_run_string(sprintf("
_task = ee.batch.Export.table.toDrive(
    collection   = _all,
    description  = '%s',
    folder       = '%s',
    fileNamePrefix = '%s',
    fileFormat   = 'CSV',
    selectors    = ['region_id', 'iso3', 'adm_level', 'year', 'mean']
)
_task.start()
_task_id = _task.id
", desc, drive_folder, desc))

  task_id <- reticulate::py$`_task_id`
  list(status = "submitted", task_id = task_id, description = desc)
}

for (i in seq_along(remaining)) {
  iso3   <- remaining[i]
  n_done <- length(submitted) + i
  pct    <- round(n_done / length(iso3s) * 100)

  result <- tryCatch(submit_country(iso3),
                     error = function(e) list(status = paste0("error:", conditionMessage(e))))

  tlog <- rbind(tlog, data.table::data.table(
    iso3        = iso3,
    task_id     = if (!is.null(result$task_id)) result$task_id else NA_character_,
    description = if (!is.null(result$description)) result$description else NA_character_,
    status      = result$status
  ))
  data.table::fwrite(tlog, task_log)

  cat(sprintf("[%3d%%] [%3d/%3d] %-6s  %s\n", pct, n_done, length(iso3s), iso3, result$status))
}

cat("\n--- Submission summary ---\n")
print(tlog[, .N, by = status])
cat(sprintf("\nTask log saved: %s\n", task_log))
cat("Now run 07b_gee_dmsp_download.R to monitor and download results.\n")
