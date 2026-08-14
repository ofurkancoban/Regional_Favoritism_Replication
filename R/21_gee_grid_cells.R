# R/21_gee_grid_cells.R
# HR 2014 Table IV Col(4)-(7): zonal-mean stable_lights NTL over global
# rectangular grid cells (50/100/200/400 km, built in R/20_build_grid_cells.R,
# full precision, no simplification).
#
# Same three-tier strategy proven in R/07 and R/16:
#   1. Fast path: one FeatureCollection per country.
#   2. Feature-count chunking when a country has many cells.
#   3. Part-based chunking + year-level caching for any single cell whose
#      own polygon is still too complex (rare for grid cells, but possible
#      near very intricate coastlines where a cell is clipped into many
#      slivers).
#
# Usage: Rscript R/21_gee_grid_cells.R <resolution_km>
# Output: data/processed/ntl/grid_<res>km_stable_global_panel.csv

library(reticulate)
library(sf)
library(data.table)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript R/21_gee_grid_cells.R <resolution_km>")
RES_KM <- as.integer(args[1])

gee_call <- function(expr) tryCatch(expr, error = function(e) NULL)

props_to_row <- function(props) {
  as.data.frame(lapply(props, function(x) if (is.null(x) || length(x) == 0) NA else x[[1]]),
                stringsAsFactors = FALSE)
}

source("R/utils/gee_helpers.R")

out_dir <- sprintf("data/processed/ntl/grid_%dkm_by_country", RES_KM)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
part_cache_dir <- file.path(out_dir, "_part_cache")
dir.create(part_cache_dir, showWarnings = FALSE, recursive = TRUE)

years             <- 1992:2013
scale_m           <- 1000L
chunk_max_mb      <- 8
chunk_max_n       <- 100
part_vertex_cap   <- 20000
part_chunk_budget <- 15000

cat(sprintf("=== Load %d km grid cells ===\n", RES_KM))
sf::sf_use_s2(FALSE)
grid <- sf::st_read(sprintf("data/processed/grid_cells_%dkm.gpkg", RES_KM), quiet = TRUE)
sf::st_geometry(grid) <- "geometry"

cat(sprintf("Grid cells: %d | countries: %d (full PLAD country universe)\n",
    nrow(grid), uniqueN(grid$GID_0)))
iso3s <- sort(unique(grid$GID_0))

gee_initialize()
ee <- reticulate::import("ee")
dmsp_col <- ee$ImageCollection("NOAA/DMSP-OLS/NIGHTTIME_LIGHTS")$select("stable_lights")
get_year_image <- function(yr) {
  dmsp_col$filterDate(paste0(yr, "-01-01"), paste0(yr, "-12-31"))$mean()
}
mean_count_reducer <- ee$Reducer$mean()$combine(reducer2 = ee$Reducer$count(), sharedInputs = TRUE)

geojson_of <- function(sf_sub) {
  sf_sub <- sf::st_transform(sf_sub, 4326)
  tmp <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp), add = TRUE)
  sf::st_write(sf_sub, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")
  list(gjson = gjson, mb = round(nchar(gjson) / 1e6, 2))
}
fc_from_geojson <- function(gjson) {
  reticulate::py_run_string(paste0(
    "import json, ee\n_fc_up = ee.FeatureCollection(json.loads('",
    gsub("'", "\\'", gjson, fixed = TRUE), "'))"
  ))
  reticulate::py$`_fc_up`
}
sf_to_gee <- function(sf_obj, id_col) {
  obj <- geojson_of(sf_obj[, c(id_col, "geometry")])
  if (obj$mb > 9) stop("payload too large for single FC")
  list(fc = fc_from_geojson(obj$gjson), n = nrow(sf_obj))
}
build_chunk_fcs <- function(sf_obj, id_col, max_mb = chunk_max_mb, max_n = chunk_max_n) {
  n <- nrow(sf_obj)
  if (n == 0) return(list())
  if (n <= max_n) {
    obj <- geojson_of(sf_obj[, c(id_col, "geometry")])
    if (obj$mb <= max_mb || n == 1) return(list(fc_from_geojson(obj$gjson)))
  }
  half <- max(1L, floor(n / 2))
  c(build_chunk_fcs(sf_obj[seq_len(half), ], id_col, max_mb, max_n),
    build_chunk_fcs(sf_obj[(half + 1):n, ], id_col, max_mb, max_n))
}

process_row_by_parts <- function(grid_id, geom, iso3) {
  cache_file <- file.path(part_cache_dir, paste0(grid_id, ".csv"))
  cached <- if (file.exists(cache_file)) data.table::fread(cache_file) else data.table(year = integer(0))
  years_todo <- setdiff(years, cached$year)
  if (length(years_todo) == 0) return(cached)

  parts <- sf::st_cast(sf::st_geometry(geom), "POLYGON")
  vcounts <- sapply(parts, function(p) nrow(sf::st_coordinates(sf::st_sfc(p, crs = 4326))))
  cat(sprintf("  [%s] splitting into %d parts (%d total vertices); %d to do\n",
      grid_id, length(parts), sum(vcounts), length(years_todo)))

  grp <- integer(length(parts)); g <- 1L; running <- 0L
  for (k in seq_along(vcounts)) {
    if (running > 0 && running + vcounts[k] > part_chunk_budget) { g <- g + 1L; running <- 0L }
    grp[k] <- g
    running <- running + vcounts[k]
  }
  part_sf <- sf::st_sf(part_id = seq_along(parts), grp = grp, geometry = sf::st_sfc(parts, crs = 4326))
  fcs <- lapply(sort(unique(grp)), function(gg) {
    obj <- geojson_of(part_sf[part_sf$grp == gg, c("part_id", "geometry")])
    fc_from_geojson(obj$gjson)
  })

  for (yr in years_todo) {
    img <- tryCatch(get_year_image(yr), error = function(e) NULL)
    row <- NULL
    if (!is.null(img)) {
      chunk_feats <- lapply(fcs, function(fc) {
        gee_call(img$reduceRegions(collection = fc, reducer = mean_count_reducer, scale = scale_m)$getInfo()[["features"]])
      })
      feats <- unlist(chunk_feats, recursive = FALSE)
      if (length(feats) > 0) {
        dt <- data.table::rbindlist(lapply(feats, function(f) props_to_row(f[["properties"]])), fill = TRUE)
        dt <- dt[!is.na(mean) & !is.na(count) & count > 0]
        if (nrow(dt) > 0) {
          weighted_mean <- sum(dt$mean * dt$count) / sum(dt$count)
          row <- data.table(grid_id = grid_id, dmsp_stable_lights = weighted_mean, year = yr, iso3 = iso3)
        }
      }
    }
    if (!is.null(row)) {
      cached <- data.table::rbindlist(list(cached, row), fill = TRUE)
      data.table::fwrite(cached, cache_file)
    }
  }
  cached
}

process_country_chunked <- function(sf_obj, id_col, iso3) {
  fcs <- tryCatch(build_chunk_fcs(sf_obj, id_col), error = function(e) NULL)
  if (is.null(fcs) || length(fcs) == 0) return(NULL)
  rows <- data.table::rbindlist(lapply(years, function(yr) {
    img <- tryCatch(get_year_image(yr), error = function(e) NULL)
    if (is.null(img)) return(NULL)
    chunk_feats <- lapply(fcs, function(fc) {
      gee_call(img$reduceRegions(collection = fc, reducer = ee$Reducer$mean(), scale = scale_m)$getInfo()[["features"]])
    })
    feats <- unlist(chunk_feats, recursive = FALSE)
    if (length(feats) == 0) return(NULL)
    dt <- data.table::rbindlist(lapply(feats, function(f) props_to_row(f[["properties"]])), fill = TRUE)
    dt[, year := yr]; dt[, iso3 := iso3]
    if ("mean" %in% names(dt)) data.table::setnames(dt, "mean", "dmsp_stable_lights")
    dt
  }), fill = TRUE)
  if (is.null(rows) || nrow(rows) == 0) return(NULL)
  list(status = sprintf("ok_chunked_%dr_%dchunks_%dyr", nrow(sf_obj), length(fcs), uniqueN(rows$year)), rows = rows)
}

process_country <- function(iso3) {
  out_file <- file.path(out_dir, paste0(iso3, "_grid.csv"))
  if (file.exists(out_file)) return("cached")

  sf_obj <- grid[grid$GID_0 == iso3, ]
  if (nrow(sf_obj) == 0) return("no_regions")
  id_col <- "grid_id"

  vcounts <- sapply(seq_len(nrow(sf_obj)), function(i) nrow(sf::st_coordinates(sf::st_geometry(sf_obj[i, ]))))
  oversized <- vcounts > part_vertex_cap
  parts_rows <- NULL
  if (any(oversized)) {
    parts_rows <- data.table::rbindlist(lapply(which(oversized), function(i) {
      process_row_by_parts(sf_obj$grid_id[i], sf_obj[i, ], iso3)
    }), fill = TRUE)
    sf_obj <- sf_obj[!oversized, ]
  }

  normal_rows <- NULL
  status_tag <- "ok"
  if (nrow(sf_obj) > 0) {
    gee_obj <- tryCatch(sf_to_gee(sf_obj, id_col), error = function(e) NULL)
    if (!is.null(gee_obj)) {
      normal_rows <- data.table::rbindlist(lapply(years, function(yr) {
        img <- tryCatch(get_year_image(yr), error = function(e) NULL)
        if (is.null(img)) return(NULL)
        result <- gee_call(
          img$reduceRegions(collection = gee_obj$fc, reducer = ee$Reducer$mean(), scale = scale_m)$getInfo()[["features"]]
        )
        if (is.null(result)) return(NULL)
        dt <- data.table::rbindlist(lapply(result, function(f) props_to_row(f[["properties"]])), fill = TRUE)
        dt[, year := yr]; dt[, iso3 := iso3]
        if ("mean" %in% names(dt)) data.table::setnames(dt, "mean", "dmsp_stable_lights")
        dt
      }), fill = TRUE)
      n_years_ok <- if (is.null(normal_rows)) 0L else uniqueN(normal_rows$year)
      if (n_years_ok < length(years)) {
        chunked <- process_country_chunked(sf_obj, id_col, iso3)
        if (is.null(chunked)) return("chunk_error")
        normal_rows <- chunked$rows
        status_tag <- chunked$status
      }
    } else {
      chunked <- process_country_chunked(sf_obj, id_col, iso3)
      if (is.null(chunked)) return("chunk_error")
      normal_rows <- chunked$rows
      status_tag <- chunked$status
    }
  }

  all_rows <- data.table::rbindlist(list(normal_rows, parts_rows), fill = TRUE)
  if (nrow(all_rows) == 0) return("chunk_error")
  data.table::fwrite(all_rows, out_file)
  n_parts_handled <- if (is.null(parts_rows)) 0L else uniqueN(parts_rows$grid_id)
  sprintf("%s_%dr_%dpartrows", status_tag, nrow(sf_obj) + n_parts_handled, n_parts_handled)
}

cat(sprintf("Processing %d countries (%d km grid), years %d-%d\n\n", length(iso3s), RES_KM, min(years), max(years)))
for (i in seq_along(iso3s)) {
  iso3   <- iso3s[i]
  status <- tryCatch(process_country(iso3), error = function(e) paste0("ERROR:", conditionMessage(e)))
  cat(sprintf("[%3d%%] [%3d/%3d] %-6s  %s\n", round(i / length(iso3s) * 100), i, length(iso3s), iso3, status))
}

cat("\nAssembling grid global panel...\n")
csv_files <- list.files(out_dir, pattern = "_grid\\.csv$", full.names = TRUE)
panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
data.table::fwrite(panel, sprintf("data/processed/ntl/grid_%dkm_stable_global_panel.csv", RES_KM))
cat(sprintf("Panel saved: %d rows, countries: %d\n", nrow(panel), uniqueN(panel$iso3)))
