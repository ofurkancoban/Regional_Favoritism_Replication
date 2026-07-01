# R/02_gee_ntl_test.R
# Purpose: Task 4.1 and 4.2 - test GEE pipeline with DMSP-OLS and VIIRS for Turkey.
# Requires: authenticated GEE (project ee-turkey-research), Turkey ADM1 shapefile.

library(reticulate)
library(sf)
library(data.table)

source("R/utils/gee_helpers.R")

# ---- Initialize GEE ----
gee_initialize()
gee_hello()

ee <- reticulate::import("ee")

# ---- Load Turkey ADM1 (GADM 4.1 preferred, geoBoundaries fallback) ----
gadm_gpkg <- "data/raw/gadm_4.1/turkey/gadm41_TUR.gpkg"
gb_geojson <- "data/raw/gadm_4.1/turkey/geoboundaries_TUR_ADM1.geojson"

if (file.exists(gadm_gpkg)) {
  tur_adm1 <- sf::st_read(gadm_gpkg, layer = "ADM_1", quiet = TRUE)
} else {
  tur_adm1 <- sf::st_read(gb_geojson, quiet = TRUE)
  names(tur_adm1)[names(tur_adm1) == "shapeName"] <- "NAME_1"
  names(tur_adm1)[names(tur_adm1) == "shapeISO"]  <- "GID_1"
}

name_col <- names(tur_adm1)[grepl("NAME_1", names(tur_adm1))][1]
gid_col  <- names(tur_adm1)[grepl("GID_1",  names(tur_adm1))][1]
message("Loaded Turkey ADM1: ", nrow(tur_adm1), " provinces")

# Convert to GEE FeatureCollection via in-memory GeoJSON parsing.
# Simplify geometry to stay under GEE's 10 MB request payload limit.
tur_sub <- tur_adm1[, c(gid_col, name_col, "geometry")]
tur_sub <- sf::st_simplify(tur_sub, preserveTopology = TRUE, dTolerance = 500)

tmp_geojson <- tempfile(fileext = ".geojson")
sf::st_write(tur_sub, tmp_geojson, driver = "GeoJSON", quiet = TRUE)
geojson_str <- paste(readLines(tmp_geojson, warn = FALSE), collapse = "")
unlink(tmp_geojson)
message("GeoJSON payload size: ", round(nchar(geojson_str) / 1e6, 2), " MB")

reticulate::py_run_string(paste0(
  "import json, ee\n",
  "tur_fc = ee.FeatureCollection(json.loads('",
  gsub("'", "\\'", geojson_str, fixed = TRUE),
  "'))"
))
tur_fc <- reticulate::py$tur_fc

# ---- Task 4.1: DMSP-OLS 2000 ----
message("Querying DMSP-OLS stable_lights for year 2000...")

dmsp_2000 <- ee$ImageCollection("NOAA/DMSP-OLS/NIGHTTIME_LIGHTS")$
  filterDate("2000-01-01", "2000-12-31")$
  select("stable_lights")$
  mean()  # annual composite; take mean over available images in year

dmsp_result <- dmsp_2000$reduceRegions(
  collection = tur_fc,
  reducer    = ee$Reducer$mean(),
  scale      = as.integer(1000)
)

features_dmsp <- dmsp_result$getInfo()[["features"]]
df_dmsp <- data.table::rbindlist(lapply(features_dmsp, function(f) {
  as.data.frame(f[["properties"]], stringsAsFactors = FALSE)
}))
data.table::setnames(df_dmsp, "mean", "dmsp_mean_2000", skip_absent = TRUE)

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
data.table::fwrite(df_dmsp, "data/processed/turkey_dmsp_2000_test.csv")
message("DMSP-OLS test: ", nrow(df_dmsp), " provinces. Saved to data/processed/turkey_dmsp_2000_test.csv")

# ---- Task 4.2: VIIRS June 2020 ----
message("Querying VIIRS avg_rad for June 2020...")

viirs_jun2020 <- ee$ImageCollection("NOAA/VIIRS/DNB/MONTHLY_V1/VCMSLCFG")$
  filterDate("2020-06-01", "2020-06-30")$
  select("avg_rad")$
  first()

viirs_result <- viirs_jun2020$reduceRegions(
  collection = tur_fc,
  reducer    = ee$Reducer$mean(),
  scale      = as.integer(500)
)

features_viirs <- viirs_result$getInfo()[["features"]]
df_viirs <- data.table::rbindlist(lapply(features_viirs, function(f) {
  as.data.frame(f[["properties"]], stringsAsFactors = FALSE)
}))
data.table::setnames(df_viirs, "mean", "viirs_avg_rad_2020_06", skip_absent = TRUE)

data.table::fwrite(df_viirs, "data/processed/turkey_viirs_2020_06_test.csv")
message("VIIRS test: ", nrow(df_viirs), " provinces. Saved to data/processed/turkey_viirs_2020_06_test.csv")

# ---- Task 4.3: Sanity check - Rize vs Turkey average ----
message("Running Rize vs Turkey-average sanity check...")

# Query VIIRS for 2012 and 2020 annual composites to compare
# VCMSLCFG starts April 2014; use VCMCFG for 2012 (available from 2012-04)
viirs_2012 <- ee$ImageCollection("NOAA/VIIRS/DNB/MONTHLY_V1/VCMCFG")$
  filterDate("2012-04-01", "2012-12-31")$
  select("avg_rad")$
  mean()

viirs_2020 <- ee$ImageCollection("NOAA/VIIRS/DNB/MONTHLY_V1/VCMSLCFG")$
  filterDate("2020-01-01", "2020-12-31")$
  select("avg_rad")$
  mean()

get_province_viirs <- function(image, year_label) {
  res <- image$reduceRegions(
    collection = tur_fc,
    reducer    = ee$Reducer$mean(),
    scale      = as.integer(500)
  )
  feats <- res$getInfo()[["features"]]
  dt <- data.table::rbindlist(lapply(feats, function(f) {
    as.data.frame(f[["properties"]], stringsAsFactors = FALSE)
  }))
  dt[, year := year_label]
  data.table::setnames(dt, "mean", "avg_rad", skip_absent = TRUE)
  dt
}

dt_2012 <- get_province_viirs(viirs_2012, 2012)
dt_2020 <- get_province_viirs(viirs_2020, 2020)

name_col_lower <- tolower(name_col)
dt_all <- rbind(dt_2012, dt_2020)
data.table::setnames(dt_all, name_col, "province_name", skip_absent = TRUE)

# Rize DiD
rize_2012 <- dt_all[year == 2012 & grepl("Rize", province_name, ignore.case = TRUE), avg_rad]
rize_2020 <- dt_all[year == 2020 & grepl("Rize", province_name, ignore.case = TRUE), avg_rad]
turkey_2012 <- mean(dt_all[year == 2012, avg_rad], na.rm = TRUE)
turkey_2020 <- mean(dt_all[year == 2020, avg_rad], na.rm = TRUE)

did <- (rize_2020 - rize_2012) - (turkey_2020 - turkey_2012)
message("Rize 2012: ", round(rize_2012, 4))
message("Rize 2020: ", round(rize_2020, 4))
message("Turkey avg 2012: ", round(turkey_2012, 4))
message("Turkey avg 2020: ", round(turkey_2020, 4))
message("DiD (Rize vs Turkey): ", round(did, 4))
if (did > 0) {
  message("Positive DiD: Rize brightened more than average during Erdogan tenure. Expected direction.")
} else {
  message("Negative DiD: Rize did NOT brighten more than average. Check coding or use Istanbul instead.")
}

dir.create("output/notes", showWarnings = FALSE, recursive = TRUE)
writeLines(c(
  "# Sanity check: Rize vs Turkey average VIIRS 2012 vs 2020",
  "",
  paste0("Rize 2012 avg_rad: ", round(rize_2012, 4)),
  paste0("Rize 2020 avg_rad: ", round(rize_2020, 4)),
  paste0("Turkey average 2012: ", round(turkey_2012, 4)),
  paste0("Turkey average 2020: ", round(turkey_2020, 4)),
  paste0("DiD (Rize - Turkey): ", round(did, 4)),
  "",
  "Interpretation: positive DiD means Rize brightened disproportionately under Erdogan.",
  "Note: this is a descriptive sanity check, not a regression estimate."
), "output/notes/sanity_check_rize.md")
message("Sanity check written to output/notes/sanity_check_rize.md")

unlink(tmp_geojson)
