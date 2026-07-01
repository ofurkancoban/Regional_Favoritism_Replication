# R/07_gee_dmsp_global.R
# Purpose: Week 3 -- extract DMSP-OLS annual zonal statistics (1992-2013)
# for all PLAD countries using ADM2 boundaries (ADM1 fallback).
# Output: data/processed/ntl/dmsp_global_panel.csv
#
# Resume-safe: results are written per country. Already-done countries are skipped.

library(reticulate)
library(sf)
library(data.table)

source("R/utils/gee_helpers.R")

# ---- Settings ----
gb_dir   <- "data/raw/gadm_4.1/global/geoboundaries"  # GADM JSON files stored here by 06
out_dir  <- "data/processed/ntl/dmsp_by_country"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create("data/processed/ntl", showWarnings = FALSE, recursive = TRUE)

years    <- 1992:2013
dtol     <- 500   # geometry simplification tolerance (meters)
scale_m  <- 1000L # DMSP native resolution ~1 km

no_adm2_file <- "data/raw/gadm_4.1/global/no_adm2_countries.txt"
no_adm2 <- if (file.exists(no_adm2_file)) readLines(no_adm2_file) else character(0)

# Countries to process (from PLAD)
plad  <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

# ---- Initialize GEE ----
gee_initialize()
ee <- reticulate::import("ee")

# DMSP-OLS collection: annual composites, band avg_vis (matches HR 2014)
# Multiple satellites may exist per year -- take mean across satellites.
dmsp_col <- ee$ImageCollection("NOAA/DMSP-OLS/NIGHTTIME_LIGHTS")$select("avg_vis")

get_year_image <- function(yr) {
  dmsp_col$
    filterDate(paste0(yr, "-01-01"), paste0(yr, "-12-31"))$
    mean()
}

# ---- Helper: sf -> GEE FeatureCollection ----
sf_to_gee <- function(sf_obj, id_col, tol = dtol) {
  sf_sub <- sf_obj[, c(id_col, "geometry")]
  sf_sub <- sf::st_simplify(sf_sub, preserveTopology = TRUE, dTolerance = tol)
  sf_sub <- sf::st_transform(sf_sub, 4326)

  tmp <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")

  payload_mb <- round(nchar(gjson) / 1e6, 2)
  # Iteratively simplify until payload < 9 MB
  for (extra_tol in c(1000, 2000, 5000, 10000)) {
    if (payload_mb <= 9) break
    sf_sub <- sf::st_simplify(sf_sub, preserveTopology = TRUE, dTolerance = extra_tol)
    sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
    gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")
    payload_mb <- round(nchar(gjson) / 1e6, 2)
  }

  reticulate::py_run_string(paste0(
    "import json, ee\n",
    "_fc = ee.FeatureCollection(json.loads('",
    gsub("'", "\\'", gjson, fixed = TRUE),
    "'))"
  ))
  list(fc = reticulate::py$`_fc`, mb = payload_mb, n = nrow(sf_sub))
}

# ---- Process one country ----
process_country <- function(iso3) {
  out_file <- file.path(out_dir, paste0(iso3, "_dmsp.csv"))
  if (file.exists(out_file)) return("cached")

  # Choose ADM level
  adm2_file <- file.path(gb_dir, paste0(iso3, "_ADM2.geojson"))
  adm1_file <- file.path(gb_dir, paste0(iso3, "_ADM1.geojson"))
  use_adm2  <- !iso3 %in% no_adm2 && file.exists(adm2_file)
  geo_file  <- if (use_adm2) adm2_file else adm1_file
  adm_level <- if (use_adm2) "ADM2" else "ADM1"

  if (!file.exists(geo_file)) return("no_file")

  sf_obj <- tryCatch(sf::st_read(geo_file, quiet = TRUE), error = function(e) NULL)
  if (is.null(sf_obj) || nrow(sf_obj) == 0) return("read_error")

  # Pick ID column -- GADM uses GID_2/GID_1, geoBoundaries uses shapeID
  id_col <- if ("GID_2" %in% names(sf_obj)) "GID_2" else
            if ("GID_1" %in% names(sf_obj)) "GID_1" else
            if ("shapeID" %in% names(sf_obj)) "shapeID" else
            names(sf_obj)[1]

  gee_obj <- tryCatch(sf_to_gee(sf_obj, id_col), error = function(e) NULL)
  if (is.null(gee_obj)) return("gee_error")

  # Extract zonal mean per year; retry with ADM1 fallback on persistent error
  retry_adm1 <- FALSE
  rows <- data.table::rbindlist(lapply(years, function(yr) {
    img <- tryCatch(get_year_image(yr), error = function(e) NULL)
    if (is.null(img)) return(data.table(year = yr, error = "img_error"))

    result <- tryCatch(
      img$reduceRegions(
        collection = gee_obj$fc,
        reducer    = ee$Reducer$mean(),
        scale      = scale_m
      )$getInfo()[["features"]],
      error = function(e) {
        # Retry once with higher simplification
        tryCatch({
          gee_retry <- sf_to_gee(sf_obj, id_col, tol = 5000)
          img$reduceRegions(
            collection = gee_retry$fc,
            reducer    = ee$Reducer$mean(),
            scale      = scale_m
          )$getInfo()[["features"]]
        }, error = function(e2) NULL)
      }
    )
    if (is.null(result)) return(data.table(year = yr, error = "reduce_error"))

    dt <- data.table::rbindlist(lapply(result, function(f) {
      props <- f[["properties"]]
      as.data.frame(props, stringsAsFactors = FALSE)
    }), fill = TRUE)
    dt[, year      := yr]
    dt[, iso3      := iso3]
    dt[, adm_level := adm_level]
    if ("mean" %in% names(dt)) data.table::setnames(dt, "mean", "dmsp_avg_vis")
    dt
  }), fill = TRUE)

  data.table::fwrite(rows, out_file)
  return(sprintf("ok_%s_%dr", adm_level, nrow(sf_obj)))
}

# ---- Main loop ----
cat(sprintf("Processing %d countries, years %d-%d\n\n", length(iso3s), min(years), max(years)))

for (i in seq_along(iso3s)) {
  iso3   <- iso3s[i]
  pct    <- round(i / length(iso3s) * 100)
  status <- tryCatch(process_country(iso3), error = function(e) paste0("ERROR:", conditionMessage(e)))
  cat(sprintf("[%3d%%] [%3d/%3d] %-6s  %s\n", pct, i, length(iso3s), iso3, status))
}

# ---- Assemble global panel ----
cat("\nAssembling global panel...\n")
csv_files <- list.files(out_dir, pattern = "_dmsp\\.csv$", full.names = TRUE)
panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)

data.table::fwrite(panel, "data/processed/ntl/dmsp_global_panel.csv")
cat(sprintf("Panel saved: %d rows, %d columns\n", nrow(panel), ncol(panel)))
cat(sprintf("Countries: %d | Years: %d-%d\n",
    uniqueN(panel$iso3), min(panel$year, na.rm = TRUE), max(panel$year, na.rm = TRUE)))
