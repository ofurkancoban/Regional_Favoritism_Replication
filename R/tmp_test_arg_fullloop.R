suppressWarnings({library(reticulate); library(sf); library(data.table)})
source("R/utils/gee_helpers.R")
sf::sf_use_s2(FALSE)
gee_initialize()
ee <- reticulate::import("ee")
dmsp_col <- ee$ImageCollection("NOAA/DMSP-OLS/NIGHTTIME_LIGHTS")$select("stable_lights")

holed <- sf::st_read("data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE)
sf::st_geometry(holed) <- "geometry"
sf_obj <- holed[holed$GID_0 == "ARG", ]

sf_sub <- sf_obj[, c("GID_1", "geometry")]
sf_sub <- sf::st_transform(sf_sub, 4326)
tmp <- tempfile(fileext = ".geojson")
sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")
reticulate::py_run_string(paste0(
  "import json, ee\n_fc = ee.FeatureCollection(json.loads('",
  gsub("'", "\\'", gjson, fixed = TRUE), "'))"
))
fc <- reticulate::py$`_fc`
cat("FC ready\n")

for (yr in 1992:2013) {
  t0 <- Sys.time()
  img <- dmsp_col$filterDate(paste0(yr, "-01-01"), paste0(yr, "-12-31"))$mean()
  result <- tryCatch(
    img$reduceRegions(collection = fc, reducer = ee$Reducer$mean(), scale = 1000L)$getInfo(),
    error = function(e) { cat("ERROR yr", yr, ":", conditionMessage(e), "\n"); NULL }
  )
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("yr %d: %.1fs, features=%s\n", yr, el, if(!is.null(result)) length(result$features) else "NULL"))
}
