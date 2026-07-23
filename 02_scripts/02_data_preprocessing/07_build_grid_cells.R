# ==============================================================================
# File:          07_build_grid_cells.R
# Project:       Regional Favoritism: A Replication and Extension of
#                Hodler & Raschky (2014)
# Author:        Ömer Furkan Çoban
#
# University:    Carl von Ossietzky University of Oldenburg
# Department:    Applied Economics and Data Science
# Course:        Applied Econometrics Using GIS Techniques
# Semester:      SoSe 2026
# Lecturer:      Prof. Dr. Erkan Gören
#
# Category:      Data Preprocessing
#
# Description:   Builds the equal-area global rectangular grid (50/100/200/400 km resolutions) used as the geographic-extent unit of observation in Table IV Columns (4)-(7).
#
# Inputs:        01_datasets/raw/gadm_4.1/
# Outputs:       01_datasets/processed/grid_cells_<res>km.gpkg
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

sf::sf_use_s2(FALSE)
EQUAL_AREA_CRS <- "ESRI:54034"  # World Cylindrical Equal Area

cat("=== Load country universe (PLAD countries) and GADM 3.6 level0 boundaries ===\n")
plad <- data.table::fread(here::here("01_datasets/raw/plad/PLAD_April_2024.tab"), sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]
cat(sprintf("Target countries: %d\n", length(iso3s)))

l0 <- sf::st_read(here::here("01_datasets/raw/gadm_3.6/gadm36_levels.gpkg"), layer = "level0", quiet = TRUE)
sf::st_geometry(l0) <- "geometry"
l0 <- l0[l0$GID_0 %in% iso3s, ]
cat(sprintf("Matched countries in GADM: %d\n", nrow(l0)))
l0_eq <- sf::st_transform(l0, EQUAL_AREA_CRS)

build_grid_for_resolution <- function(res_km) {
  cell_m <- res_km * 1000

  cat(sprintf("\n=== Building %d km grid ===\n", res_km))
  bbox <- sf::st_bbox(l0_eq)
  grid <- sf::st_make_grid(sf::st_as_sfc(bbox), cellsize = c(cell_m, cell_m), what = "polygons")
  grid_sf <- sf::st_sf(cell_id = seq_along(grid), geometry = grid)
  cat(sprintf("Global grid: %d cells (before clipping)\n", nrow(grid_sf)))

  # Keep only cells that actually intersect at least one target country.
  # Testing against the 174-country FEATURE COLLECTION (not a single unioned
  # polygon) lets sf/GEOS use its spatial index (STRtree) for the bulk
  # predicate test -- st_union() of all 174 full-precision country
  # boundaries into one enormous multipolygon first made this step
  # intractably slow (8+ min with no result).
  hit_list <- sf::st_intersects(grid_sf, l0_eq)
  hit <- lengths(hit_list) > 0
  grid_sf <- grid_sf[hit, ]
  cat(sprintf("Cells intersecting target countries: %d\n", nrow(grid_sf)))

  n_workers <- max(1L, parallel::detectCores() - 1L)
  future::plan(future::multicore, workers = n_workers)

  clip_one_country <- function(i) {
    ctry <- l0_eq[i, ]
    iso3 <- ctry$GID_0
    cand_idx <- lengths(sf::st_intersects(grid_sf, ctry)) > 0
    if (!any(cand_idx)) return(NULL)
    cand <- grid_sf[cand_idx, ]
    clipped <- tryCatch(sf::st_intersection(cand, sf::st_geometry(ctry)), error = function(e) NULL)
    if (is.null(clipped) || nrow(clipped) == 0) return(NULL)
    clipped <- clipped[!sf::st_is_empty(clipped), ]
    if (nrow(clipped) == 0) return(NULL)
    clipped$GID_0 <- iso3
    clipped$grid_id <- paste0(iso3, "_", clipped$cell_id)
    clipped[, c("grid_id", "GID_0", "cell_id")]
  }

  t0 <- Sys.time()
  pieces <- future.apply::future_lapply(seq_len(nrow(l0_eq)), clip_one_country, future.seed = TRUE)
  pieces <- pieces[!sapply(pieces, is.null)]
  cat(sprintf("Elapsed: %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))

  out <- do.call(rbind, pieces)
  out <- sf::st_transform(out, 4326)
  out <- sf::st_make_valid(out)
  cat(sprintf("%d km grid: %d clipped cells across %d countries\n",
      res_km, nrow(out), data.table::uniqueN(out$GID_0)))

  out_file <- here::here(sprintf("01_datasets/processed/grid_cells_%dkm.gpkg", res_km))
  sf::st_write(out, out_file, quiet = TRUE, delete_dsn = TRUE)
  cat(sprintf("Saved: %s\n", out_file))
  out
}

args <- commandArgs(trailingOnly = TRUE)
res_to_build <- if (length(args) > 0) as.integer(args) else c(100L)
for (res in res_to_build) build_grid_for_resolution(res)
