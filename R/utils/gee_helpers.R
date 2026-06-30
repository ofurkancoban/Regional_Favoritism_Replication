# R/utils/gee_helpers.R
# Purpose: helper functions for Google Earth Engine access via reticulate.
# Requires: reticulate, earthengine-api Python package, authenticated GEE account.
# GEE project: ee-turkey-research

gee_initialize <- function(project = "ee-turkey-research") {
  reticulate::py_run_string(paste0(
    "import ee; ee.Initialize(project='", project, "')"
  ))
  message("GEE initialized with project: ", project)
}

gee_hello <- function() {
  result <- reticulate::py_eval("ee.String('Hello GEE').getInfo()")
  message(result)
  invisible(result)
}

# Convert an sf object to a GEE FeatureCollection via GeoJSON.
sf_to_ee_fc <- function(sf_obj) {
  ee <- reticulate::import("ee")
  geojson_str <- sf::st_as_text(sf::st_geometry(sf_obj))
  # Use temporary file to pass GeoJSON without truncation
  tmp <- tempfile(fileext = ".geojson")
  sf::st_write(sf_obj, tmp, driver = "GeoJSON", quiet = TRUE)
  fc <- ee$FeatureCollection(tmp)
  unlink(tmp)
  fc
}

# Zonal mean for an ee.Image over a FeatureCollection; returns local data.frame.
zonal_mean <- function(image, fc, scale = 1000, max_pixels = 1e9) {
  ee <- reticulate::import("ee")
  result <- image$reduceRegions(
    collection = fc,
    reducer    = ee$Reducer$mean(),
    scale      = as.integer(scale)
  )
  # getInfo() for small FeatureCollections (<=5000 features)
  features <- result$getInfo()[["features"]]
  df <- do.call(rbind, lapply(features, function(f) {
    props <- f[["properties"]]
    as.data.frame(props, stringsAsFactors = FALSE)
  }))
  df
}
