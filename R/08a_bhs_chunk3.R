# R/08a_bhs_chunk3.R -- submit BHS features 21-30 individually to GEE VIIRS

library(reticulate)
library(sf)
library(data.table)

source("R/utils/gee_helpers.R")
gee_initialize()
ee <- reticulate::import("ee")

bhs    <- sf::st_read("data/raw/gadm_4.1/global/geoboundaries/BHS_ADM2.geojson", quiet = TRUE)
id_col <- "shapeID"
years  <- 2012:2024
tlog   <- data.table::fread("data/processed/ntl/viirs_task_log.csv")

for (i in 21:30) {
  f   <- sf::st_transform(bhs[i, ], 4326)
  tmp <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  sf::st_write(f, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")
  mb    <- round(nchar(gjson) / 1e6, 2)
  cat(sprintf("feat %d: %.2f MB -- ", i, mb))

  reticulate::py_run_string(paste0(
    "import json, ee\n",
    "_fc = ee.FeatureCollection(json.loads('",
    gsub("'", "\\'", gjson, fixed = TRUE), "'))"
  ))

  desc <- sprintf("viirs_BHS_3f%02d", i)

  reticulate::py_run_string(sprintf("
import ee
_vc1 = ee.ImageCollection('NOAA/VIIRS/DNB/MONTHLY_V1/VCMCFG').select('avg_rad')
_vc2 = ee.ImageCollection('NOAA/VIIRS/DNB/MONTHLY_V1/VCMSLCFG').select('avg_rad')
_yrs = [%s]
_id  = '%s'

def _f(yr):
    yr  = ee.Number(yr).toInt()
    col = ee.ImageCollection(ee.Algorithms.If(
        yr.lte(2013),
        _vc1.filter(ee.Filter.calendarRange(yr, yr, 'year')),
        _vc2.filter(ee.Filter.calendarRange(yr, yr, 'year'))
    ))
    r = col.mean().reduceRegions(collection=_fc, reducer=ee.Reducer.mean(), scale=500)
    return r.map(lambda f: f.set({'year': yr, 'iso3': 'BHS', 'adm_level': 'ADM2', 'region_id': f.get(_id)}))

_all  = ee.FeatureCollection(ee.List(_yrs).map(_f)).flatten()
_task = ee.batch.Export.table.toDrive(
    collection=_all, description='%s', folder='GEE_VIIRS_Global',
    fileNamePrefix='%s', fileFormat='CSV',
    selectors=['region_id','iso3','adm_level','year','mean']
)
_task.start()
_tid = _task.id
", paste(years, collapse = ","), id_col, desc, desc))

  tid <- reticulate::py$`_tid`
  tlog <- rbind(tlog, data.table::data.table(
    iso3 = "BHS", task_id = tid, description = desc, status = "submitted"
  ))
  data.table::fwrite(tlog, "data/processed/ntl/viirs_task_log.csv")
  cat(sprintf("submitted (%s)\n", desc))
}
cat("Done. Total submitted:", tlog[status == "submitted", .N], "\n")
