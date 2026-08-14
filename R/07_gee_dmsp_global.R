# R/07_gee_dmsp_global.R
# Purpose: Extract DMSP-OLS annual zonal statistics (1992-2013)
# for all PLAD countries using ADM2 boundaries (ADM1 fallback).
# Output: data/processed/ntl/dmsp_stable_global_panel.csv
#
# Resume-safe: results are written per country. Already-done countries are skipped.
#
# Large/complex-geometry countries: if building a single FeatureCollection for
# the whole country fails (or reduceRegions fails for any year), the country is
# reprocessed by recursively splitting its regions into smaller feature chunks
# at FULL geometry precision (no simplification), so no polygon detail is lost.

library(reticulate)
library(sf)
library(data.table)

source("R/utils/gee_helpers.R")

# ---- Settings ----
gb_dir   <- "data/raw/gadm_4.1/global/geoboundaries"  # GADM JSON files stored here by 06
out_dir  <- "data/processed/ntl/dmsp_stable_by_country"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create("data/processed/ntl", showWarnings = FALSE, recursive = TRUE)

years         <- 1992:2013
dtol          <- 500   # geometry simplification tolerance (meters) -- single-FC fast path only
scale_m       <- 1000L # DMSP native resolution ~1 km
chunk_max_mb  <- 8      # max geojson payload per chunk
chunk_max_n   <- 100    # max features per chunk (initial split) -- payload check still
                        # splits further if a chunk's geojson exceeds chunk_max_mb

no_adm2_file <- "data/raw/gadm_4.1/global/no_adm2_countries.txt"
no_adm2 <- if (file.exists(no_adm2_file)) readLines(no_adm2_file) else character(0)

# Countries to process (from PLAD)
plad  <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

# ---- Initialize GEE ----
gee_initialize()
ee <- reticulate::import("ee")

# DMSP-OLS collection: annual composites, band stable_lights.
# HR 2014 (p. 998) use NOAA's noise-cleaned product: readings likely to
# reflect fires, ephemeral lights, or background noise are set to zero.
# This is the "stable_lights" band, not the raw "avg_vis" band.
# Multiple satellites may exist per year -- take mean across satellites.
dmsp_col <- ee$ImageCollection("NOAA/DMSP-OLS/NIGHTTIME_LIGHTS")$select("stable_lights")

get_year_image <- function(yr) {
  dmsp_col$
    filterDate(paste0(yr, "-01-01"), paste0(yr, "-12-31"))$
    mean()
}

# ---- Fast path: sf -> single GEE FeatureCollection (simplified geometry) ----
sf_to_gee <- function(sf_obj, id_col, tol = dtol) {
  sf_sub <- sf_obj[, c(id_col, "geometry")]
  sf_sub <- sf::st_simplify(sf_sub, preserveTopology = TRUE, dTolerance = tol)
  sf_sub <- sf::st_transform(sf_sub, 4326)

  tmp <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")

  payload_mb <- round(nchar(gjson) / 1e6, 2)
  if (payload_mb > 9) stop("payload too large for single FC")

  reticulate::py_run_string(paste0(
    "import json, ee\n",
    "_fc = ee.FeatureCollection(json.loads('",
    gsub("'", "\\'", gjson, fixed = TRUE),
    "'))"
  ))
  list(fc = reticulate::py$`_fc`, mb = payload_mb, n = nrow(sf_sub))
}

# ---- Fallback path: recursive chunking at FULL precision (no simplify) ----
sf_chunk_to_fc <- function(sf_chunk, id_col) {
  sf_sub <- sf_chunk[, c(id_col, "geometry")]
  sf_sub <- sf::st_transform(sf_sub, 4326)
  tmp <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")
  round(nchar(gjson) / 1e6, 2) -> payload_mb
  list(gjson = gjson, mb = payload_mb)
}

# Recursively split sf_obj into chunks small enough to upload, at full precision.
build_chunk_fcs <- function(sf_obj, id_col, max_mb = chunk_max_mb, max_n = chunk_max_n) {
  n <- nrow(sf_obj)
  if (n == 0) return(list())

  if (n <= max_n) {
    obj <- sf_chunk_to_fc(sf_obj, id_col)
    if (obj$mb <= max_mb || n == 1) {
      reticulate::py_run_string(paste0(
        "import json, ee\n",
        "_fc_chunk = ee.FeatureCollection(json.loads('",
        gsub("'", "\\'", obj$gjson, fixed = TRUE),
        "'))"
      ))
      return(list(reticulate::py$`_fc_chunk`))
    }
    # payload still too big even at <=max_n features -- split further
  }

  half <- max(1L, floor(n / 2))
  c(
    build_chunk_fcs(sf_obj[seq_len(half), ], id_col, max_mb, max_n),
    build_chunk_fcs(sf_obj[(half + 1):n, ], id_col, max_mb, max_n)
  )
}

# Process a country via chunked, full-precision geometry.
process_country_chunked <- function(sf_obj, id_col, iso3, adm_level) {
  fcs <- tryCatch(build_chunk_fcs(sf_obj, id_col), error = function(e) NULL)
  if (is.null(fcs) || length(fcs) == 0) return(list(status = "chunk_error", rows = NULL))

  rows <- data.table::rbindlist(lapply(years, function(yr) {
    img <- tryCatch(get_year_image(yr), error = function(e) NULL)
    if (is.null(img)) return(NULL)

    chunk_feats <- lapply(fcs, function(fc) {
      tryCatch(
        img$reduceRegions(collection = fc, reducer = ee$Reducer$mean(), scale = scale_m)$getInfo()[["features"]],
        error = function(e) NULL
      )
    })
    feats <- unlist(chunk_feats, recursive = FALSE)
    if (length(feats) == 0) return(NULL)

    dt <- data.table::rbindlist(lapply(feats, function(f) {
      as.data.frame(f[["properties"]], stringsAsFactors = FALSE)
    }), fill = TRUE)
    dt[, year      := yr]
    dt[, iso3      := iso3]
    dt[, adm_level := adm_level]
    if ("mean" %in% names(dt)) data.table::setnames(dt, "mean", "dmsp_stable_lights")
    dt
  }), fill = TRUE)

  if (is.null(rows) || nrow(rows) == 0) return(list(status = "chunk_error", rows = NULL))

  list(
    status = sprintf("ok_chunked_%s_%dr_%dchunks_%dyr",
                      adm_level, nrow(sf_obj), length(fcs), uniqueN(rows$year)),
    rows = rows
  )
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

  # ---- Fast path: single simplified FeatureCollection ----
  gee_obj <- tryCatch(sf_to_gee(sf_obj, id_col), error = function(e) NULL)

  if (!is.null(gee_obj)) {
    rows <- data.table::rbindlist(lapply(years, function(yr) {
      img <- tryCatch(get_year_image(yr), error = function(e) NULL)
      if (is.null(img)) return(NULL)
      result <- tryCatch(
        img$reduceRegions(
          collection = gee_obj$fc,
          reducer    = ee$Reducer$mean(),
          scale      = scale_m
        )$getInfo()[["features"]],
        error = function(e) NULL
      )
      if (is.null(result)) return(NULL)
      dt <- data.table::rbindlist(lapply(result, function(f) {
        as.data.frame(f[["properties"]], stringsAsFactors = FALSE)
      }), fill = TRUE)
      dt[, year      := yr]
      dt[, iso3      := iso3]
      dt[, adm_level := adm_level]
      if ("mean" %in% names(dt)) data.table::setnames(dt, "mean", "dmsp_stable_lights")
      dt
    }), fill = TRUE)

    n_years_ok <- if (is.null(rows)) 0L else uniqueN(rows$year)
    if (n_years_ok == length(years)) {
      data.table::fwrite(rows, out_file)
      return(sprintf("ok_%s_%dr", adm_level, nrow(sf_obj)))
    }
    # else: partial failure -- fall through to chunked fallback for full precision + robustness
  }

  # ---- Fallback path: recursive chunking, full precision, no simplify ----
  chunked <- process_country_chunked(sf_obj, id_col, iso3, adm_level)
  if (is.null(chunked$rows)) return("chunk_error")
  data.table::fwrite(chunked$rows, out_file)
  return(chunked$status)
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

data.table::fwrite(panel, "data/processed/ntl/dmsp_stable_global_panel.csv")
cat(sprintf("Panel saved: %d rows, %d columns\n", nrow(panel), ncol(panel)))
cat(sprintf("Countries: %d | Years: %d-%d\n",
    uniqueN(panel$iso3), min(panel$year, na.rm = TRUE), max(panel$year, na.rm = TRUE)))
