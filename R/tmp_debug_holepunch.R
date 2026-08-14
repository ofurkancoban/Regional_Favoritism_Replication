suppressWarnings({library(reticulate); library(sf); library(data.table)})
source("R/utils/gee_helpers.R")
sf::sf_use_s2(FALSE)
gee_initialize()
ee <- reticulate::import("ee")
dmsp_col <- ee$ImageCollection("NOAA/DMSP-OLS/NIGHTTIME_LIGHTS")$select("stable_lights")
img <- dmsp_col$filterDate("2000-01-01", "2000-12-31")$mean()
cat("Image OK\n")

holed <- sf::st_read("data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE)
sf_obj <- holed[holed$GID_0 == "AFG", ]
cat("AFG rows:", nrow(sf_obj), "\n")
print(names(sf_obj))

sf_sub <- sf_obj[, c("GID_1", "geometry")]
sf_sub <- sf::st_transform(sf_sub, 4326)
tmp <- tempfile(fileext = ".geojson")
sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")
cat("payload MB:", round(nchar(gjson)/1e6, 2), "\n")

reticulate::py_run_string(paste0(
  "import json, ee\n_fc = ee.FeatureCollection(json.loads('",
  gsub("'", "\\'", gjson, fixed = TRUE), "'))"
))
fc <- reticulate::py$`_fc`
cat("FC created OK\n")

result <- tryCatch(
  img$reduceRegions(collection = fc, reducer = ee$Reducer$mean(), scale = 1000L)$getInfo(),
  error = function(e) { cat("REDUCE ERROR:", conditionMessage(e), "\n"); NULL }
)
if (!is.null(result)) cat("reduceRegions OK, features:", length(result[["features"]]), "\n")
