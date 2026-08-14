# 04_extraction/04_dmsp_grid_cells.R
# HR 2014 Table IV Col(4)-(7): zonal-mean stable_lights NTL over global
# rectangular grid cells (50/100/200/400 km), computed locally via
# exactextractr from the raw DMSP-OLS GeoTIFFs (01_download/04_download_dmsp_raw.R).
# No Google Earth Engine anywhere in this pipeline.
#
# This was the first step of the local-extraction pipeline built this
# session (formerly R/30_local_terra_dmsp_grid.R) and is what all four
# 01-05 extraction scripts in this folder now follow architecturally --
# see 00_utils/local_ntl_extraction.R's header for the full rationale
# (terra::extract()'s full-raster-extent rasterization made it 19-26+
# minutes per year; exactextractr::exact_extract() with a custom
# `majority_rule` summary function -- matching GEE's pixel-sampling
# reduceRegions(mean()) rather than exactextractr's own area-weighted
# default -- brought that down to ~11 seconds, ~100x faster).
#
# Usage: Rscript 04_extraction/04_dmsp_grid_cells.R <resolution_km> [year1,year2,...]
# Output: data/processed/ntl/dmsp_grid<res>km_by_year/<year>.csv
#         data/processed/ntl/dmsp_grid<res>km_panel.csv (assembled)

library(sf)
library(data.table)

source("00_utils/local_ntl_extraction.R")
source("00_utils/dmsp_raster_catalog.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript 04_extraction/04_dmsp_grid_cells.R <resolution_km> [year1,year2,...]")
RES_KM <- as.integer(args[1])

log_msg <- function(...) { cat(...); flush.console() }

log_msg(sprintf("=== Load %d km grid cells ===\n", RES_KM))
sf::sf_use_s2(FALSE)
grid <- sf::st_read(sprintf("data/processed/grid_cells_%dkm.gpkg", RES_KM), quiet = TRUE)
sf::st_geometry(grid) <- "geometry"
grid <- sf::st_transform(grid, 4326)
grid$iso3 <- grid$GID_0
log_msg(sprintf("Grid cells: %d | countries: %d\n", nrow(grid), data.table::uniqueN(grid$iso3)))

years <- dmsp_years
if (length(args) >= 2 && nzchar(args[2])) {
  requested <- as.integer(strsplit(args[2], ",")[[1]])
  years <- intersect(years, requested)
}

out_dir <- sprintf("data/processed/ntl/dmsp_grid%dkm_by_year", RES_KM)
extract_ntl_panel(
  polygons   = grid,
  id_col     = "grid_id",
  extra_cols = "iso3",
  years      = years,
  year_files = dmsp_year_files,
  value_col  = "dmsp_stable_lights",
  out_dir    = out_dir,
  panel_name = sprintf("data/processed/ntl/dmsp_grid%dkm_panel.csv", RES_KM),
  log_msg    = log_msg
)
