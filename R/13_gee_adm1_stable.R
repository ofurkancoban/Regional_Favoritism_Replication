# R/13_gee_adm1_stable.R
# Purpose: HR 2014 Table IV, Column (2) -- extract stable_lights NTL at the
# first subnational administrative level (SN1/ADM1), for all PLAD countries.
# Source geometry: GADM 3.6 level1 (gadm36_levels.gpkg), same vintage as the
# ADM2 extraction, so GID_1 identifiers are consistent with the analysis panel.
# Uses the same fast-path + chunked-fallback pattern as R/07_gee_dmsp_global.R.
# Output: data/processed/ntl/adm1_stable_global_panel.csv

library(reticulate)
library(sf)
library(data.table)

source("R/utils/gee_helpers.R")

out_dir <- "data/processed/ntl/adm1_stable_by_country"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

years        <- 1992:2013
scale_m      <- 1000L
chunk_max_mb <- 8
chunk_max_n  <- 100

plad  <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

cat("=== Load GADM 3.6 level1 (ADM1) ===\n")
sf::sf_use_s2(FALSE)
sf36_1 <- sf::st_read("data/raw/gadm_3.6/gadm36_level1_only.gpkg", quiet = TRUE)
sf::st_geometry(sf36_1) <- "geometry"
cat(sprintf("GADM 3.6 ADM1: %d regions total\n", nrow(sf36_1)))

gee_initialize()
ee <- reticulate::import("ee")
dmsp_col <- ee$ImageCollection("NOAA/DMSP-OLS/NIGHTTIME_LIGHTS")$select("stable_lights")
get_year_image <- function(yr) {
  dmsp_col$filterDate(paste0(yr, "-01-01"), paste0(yr, "-12-31"))$mean()
}

sf_to_gee <- function(sf_obj, id_col, tol = 500) {
  sf_sub <- sf_obj[, c(id_col, "geometry")]
  sf_sub <- sf::st_simplify(sf_sub, preserveTopology = TRUE, dTolerance = tol)
  sf_sub <- sf::st_transform(sf_sub, 4326)
  tmp <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")
  if (round(nchar(gjson) / 1e6, 2) > 9) stop("payload too large for single FC")
  reticulate::py_run_string(paste0(
    "import json, ee\n_fc = ee.FeatureCollection(json.loads('",
    gsub("'", "\\'", gjson, fixed = TRUE), "'))"
  ))
  list(fc = reticulate::py$`_fc`, n = nrow(sf_sub))
}

sf_chunk_to_fc <- function(sf_chunk, id_col) {
  sf_sub <- sf_chunk[, c(id_col, "geometry")]
  sf_sub <- sf::st_transform(sf_sub, 4326)
  tmp <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")
  list(gjson = gjson, mb = round(nchar(gjson) / 1e6, 2))
}

build_chunk_fcs <- function(sf_obj, id_col, max_mb = chunk_max_mb, max_n = chunk_max_n) {
  n <- nrow(sf_obj)
  if (n == 0) return(list())
  if (n <= max_n) {
    obj <- sf_chunk_to_fc(sf_obj, id_col)
    if (obj$mb <= max_mb || n == 1) {
      reticulate::py_run_string(paste0(
        "import json, ee\n_fc_chunk = ee.FeatureCollection(json.loads('",
        gsub("'", "\\'", obj$gjson, fixed = TRUE), "'))"
      ))
      return(list(reticulate::py$`_fc_chunk`))
    }
  }
  half <- max(1L, floor(n / 2))
  c(build_chunk_fcs(sf_obj[seq_len(half), ], id_col, max_mb, max_n),
    build_chunk_fcs(sf_obj[(half + 1):n, ], id_col, max_mb, max_n))
}

process_country_chunked <- function(sf_obj, id_col, iso3) {
  fcs <- tryCatch(build_chunk_fcs(sf_obj, id_col), error = function(e) NULL)
  if (is.null(fcs) || length(fcs) == 0) return(NULL)
  rows <- data.table::rbindlist(lapply(years, function(yr) {
    img <- tryCatch(get_year_image(yr), error = function(e) NULL)
    if (is.null(img)) return(NULL)
    chunk_feats <- lapply(fcs, function(fc) {
      tryCatch(img$reduceRegions(collection = fc, reducer = ee$Reducer$mean(), scale = scale_m)$getInfo()[["features"]],
               error = function(e) NULL)
    })
    feats <- unlist(chunk_feats, recursive = FALSE)
    if (length(feats) == 0) return(NULL)
    dt <- data.table::rbindlist(lapply(feats, function(f) as.data.frame(f[["properties"]], stringsAsFactors = FALSE)), fill = TRUE)
    dt[, year := yr]; dt[, iso3 := iso3]
    if ("mean" %in% names(dt)) data.table::setnames(dt, "mean", "dmsp_stable_lights")
    dt
  }), fill = TRUE)
  if (is.null(rows) || nrow(rows) == 0) return(NULL)
  list(status = sprintf("ok_chunked_%dr_%dchunks_%dyr", nrow(sf_obj), length(fcs), uniqueN(rows$year)), rows = rows)
}

process_country <- function(iso3) {
  out_file <- file.path(out_dir, paste0(iso3, "_adm1.csv"))
  if (file.exists(out_file)) return("cached")

  sf_obj <- sf36_1[sf36_1$GID_0 == iso3, ]
  if (nrow(sf_obj) == 0) return("no_regions")
  id_col <- "GID_1"

  gee_obj <- tryCatch(sf_to_gee(sf_obj, id_col), error = function(e) NULL)
  if (!is.null(gee_obj)) {
    rows <- data.table::rbindlist(lapply(years, function(yr) {
      img <- tryCatch(get_year_image(yr), error = function(e) NULL)
      if (is.null(img)) return(NULL)
      result <- tryCatch(
        img$reduceRegions(collection = gee_obj$fc, reducer = ee$Reducer$mean(), scale = scale_m)$getInfo()[["features"]],
        error = function(e) NULL
      )
      if (is.null(result)) return(NULL)
      dt <- data.table::rbindlist(lapply(result, function(f) as.data.frame(f[["properties"]], stringsAsFactors = FALSE)), fill = TRUE)
      dt[, year := yr]; dt[, iso3 := iso3]
      if ("mean" %in% names(dt)) data.table::setnames(dt, "mean", "dmsp_stable_lights")
      dt
    }), fill = TRUE)
    n_years_ok <- if (is.null(rows)) 0L else uniqueN(rows$year)
    if (n_years_ok == length(years)) {
      data.table::fwrite(rows, out_file)
      return(sprintf("ok_%dr", nrow(sf_obj)))
    }
  }

  chunked <- process_country_chunked(sf_obj, id_col, iso3)
  if (is.null(chunked)) return("chunk_error")
  data.table::fwrite(chunked$rows, out_file)
  return(chunked$status)
}

cat(sprintf("Processing %d countries (ADM1), years %d-%d\n\n", length(iso3s), min(years), max(years)))
for (i in seq_along(iso3s)) {
  iso3   <- iso3s[i]
  status <- tryCatch(process_country(iso3), error = function(e) paste0("ERROR:", conditionMessage(e)))
  cat(sprintf("[%3d%%] [%3d/%3d] %-6s  %s\n", round(i / length(iso3s) * 100), i, length(iso3s), iso3, status))
}

cat("\nAssembling ADM1 global panel...\n")
csv_files <- list.files(out_dir, pattern = "_adm1\\.csv$", full.names = TRUE)
panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
data.table::fwrite(panel, "data/processed/ntl/adm1_stable_global_panel.csv")
cat(sprintf("Panel saved: %d rows, countries: %d\n", nrow(panel), uniqueN(panel$iso3)))
