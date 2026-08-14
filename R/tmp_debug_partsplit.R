suppressWarnings({library(reticulate); library(sf); library(data.table)})
gee_call <- function(expr) tryCatch(expr, error = function(e) {message("gee_call ERROR: ", conditionMessage(e)); NULL})
source("R/utils/gee_helpers.R")
sf::sf_use_s2(FALSE)
gee_initialize()
ee <- reticulate::import("ee")
dmsp_col <- ee$ImageCollection("NOAA/DMSP-OLS/NIGHTTIME_LIGHTS")$select("stable_lights")
get_year_image <- function(yr) dmsp_col$filterDate(paste0(yr,"-01-01"), paste0(yr,"-12-31"))$mean()
mean_count_reducer <- ee$Reducer$mean()$combine(reducer2 = ee$Reducer$count(), sharedInputs = TRUE)

geojson_of <- function(sf_sub) {
  sf_sub <- sf::st_transform(sf_sub, 4326)
  tmp <- tempfile(fileext = ".geojson")
  sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")
  list(gjson = gjson, mb = round(nchar(gjson)/1e6, 2))
}
fc_from_geojson <- function(gjson) {
  reticulate::py_run_string(paste0("import json, ee\n_fc_up = ee.FeatureCollection(json.loads('",
    gsub("'", "\\'", gjson, fixed = TRUE), "'))"))
  reticulate::py$`_fc_up`
}

holed <- sf::st_read("data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE)
sf::st_geometry(holed) <- "geometry"
geom <- holed[holed$GID_1 == "ARG.1_1", ]

parts <- sf::st_cast(sf::st_geometry(geom), "POLYGON")
cat("n parts:", length(parts), "\n")
vcounts <- sapply(parts, function(p) nrow(sf::st_coordinates(sf::st_sfc(p, crs=4326))))
cat("vcounts range:", range(vcounts), "\n")

part_chunk_budget <- 15000
grp <- integer(length(parts)); g <- 1L; running <- 0L
for (k in seq_along(vcounts)) {
  if (running > 0 && running + vcounts[k] > part_chunk_budget) { g <- g + 1L; running <- 0L }
  grp[k] <- g
  running <- running + vcounts[k]
}
cat("n groups:", length(unique(grp)), "\n")

part_sf <- sf::st_sf(part_id = seq_along(parts), grp = grp, geometry = sf::st_sfc(parts, crs = 4326))
fcs <- lapply(sort(unique(grp))[1], function(gg) {  # just test FIRST chunk group
  obj <- geojson_of(part_sf[part_sf$grp == gg, c("part_id", "geometry")])
  fc_from_geojson(obj$gjson)
})
cat("uploaded 1 chunk for test\n")

img <- get_year_image(2000)
result <- gee_call(img$reduceRegions(collection = fcs[[1]], reducer = mean_count_reducer, scale = 1000L)$getInfo())
cat("result class:", class(result), "\n")
feats <- result[["features"]]
cat("n features:", length(feats), "\n")
cat("first feature properties:\n")
print(feats[[1]][["properties"]])
cat("second feature properties:\n")
print(feats[[2]][["properties"]])

dt <- data.table::rbindlist(lapply(feats, function(f) as.data.frame(f[["properties"]], stringsAsFactors = FALSE)), fill = TRUE)
cat("dt names:", names(dt), "\n")
cat("dt nrow:", nrow(dt), "\n")
print(head(dt))
