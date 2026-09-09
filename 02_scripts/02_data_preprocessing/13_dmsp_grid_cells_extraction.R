# ==============================================================================
# File:          13_dmsp_grid_cells_extraction.R
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
# Description:   Local zonal-statistics extraction of DMSP-OLS stable_lights over the equal-area grid cells (all four resolutions), for Table IV Columns (4)-(7).
#
# Inputs:        01_datasets/processed/grid_cells_<res>km.gpkg, 01_datasets/raw/dmsp_raster_eog_manual/
# Outputs:       01_datasets/processed/ntl/dmsp_grid<res>km_panel.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

source(here::here("02_scripts", "04_tools", "local_ntl_extraction.R"))
source(here::here("02_scripts", "04_tools", "dmsp_raster_catalog.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript 04_extraction/04_dmsp_grid_cells.R <resolution_km> [year1,year2,...]")
RES_KM <- as.integer(args[1])

log_msg <- function(...) { cat(...); flush.console() }

log_msg(sprintf("=== Load %d km grid cells ===\n", RES_KM))
sf::sf_use_s2(FALSE)
grid <- sf::st_read(here::here(sprintf("01_datasets/processed/grid_cells_%dkm.gpkg", RES_KM)), quiet = TRUE)
sf::st_geometry(grid) <- "geometry"
grid <- sf::st_transform(grid, 4326)
grid$iso3 <- grid$GID_0
log_msg(sprintf("Grid cells: %d | countries: %d\n", nrow(grid), data.table::uniqueN(grid$iso3)))

years <- dmsp_years
if (length(args) >= 2 && nzchar(args[2])) {
  requested <- as.integer(strsplit(args[2], ",")[[1]])
  years <- intersect(years, requested)
}

out_dir <- here::here(sprintf("01_datasets/processed/ntl/dmsp_grid%dkm_by_year", RES_KM))
extract_ntl_panel(
  polygons   = grid,
  id_col     = "grid_id",
  extra_cols = "iso3",
  years      = years,
  year_files = dmsp_year_files,
  value_col  = "dmsp_stable_lights",
  out_dir    = out_dir,
  panel_name = here::here(sprintf("01_datasets/processed/ntl/dmsp_grid%dkm_panel.csv", RES_KM)),
  log_msg    = log_msg
)
