suppressWarnings({library(reticulate); library(sf); library(data.table)})
source("R/utils/gee_helpers.R")
sf::sf_use_s2(FALSE)
gee_initialize()
ee <- reticulate::import("ee")
dmsp_col <- ee$ImageCollection("NOAA/DMSP-OLS/NIGHTTIME_LIGHTS")$select("stable_lights")
img <- dmsp_col$filterDate("1992-01-01", "1992-12-31")$mean()

holed <- sf::st_read("data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE)
sf::st_geometry(holed) <- "geometry"
sf_obj <- holed[holed$GID_0 == "ARG", ]
cat("ARG rows:", nrow(sf_obj), "\n")

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
cat("FC created OK at", format(Sys.time()), "\n")

t0 <- Sys.time()
result <- tryCatch(
  img$reduceRegions(collection = fc, reducer = ee$Reducer$mean(), scale = 1000L)$getInfo(),
  error = function(e) { cat("REDUCE ERROR:", conditionMessage(e), "\n"); NULL }
)
cat("Done at", format(Sys.time()), "| elapsed sec:", as.numeric(difftime(Sys.time(), t0, units="secs")), "\n")
if (!is.null(result)) cat("features:", length(result[["features"]]), "\n")
