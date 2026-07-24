# ==============================================================================
# File:          15_dmsp_birthplace_circles_extraction.R
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
# Description:   Local zonal-statistics extraction of DMSP-OLS stable_lights over the 5km birthplace circles, for Table IV Column (1).
#
# Inputs:        01_datasets/processed/birthplace_circles_5km.gpkg, 01_datasets/raw/dmsp_raster_eog_manual/
# Outputs:       01_datasets/processed/ntl/dmsp_circles_panel.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

source("00_utils/local_ntl_extraction.R")
source("00_utils/dmsp_raster_catalog.R")

cat("=== Load birthplace circles ===\n")
sf::sf_use_s2(FALSE)
circles <- sf::st_read(here::here("01_datasets/processed/birthplace_circles_5km.gpkg"), quiet = TRUE)
sf::st_geometry(circles) <- "geometry"
cat(sprintf("Circles: %d\n", nrow(circles)))

out_dir <- here::here("01_datasets/processed/ntl/dmsp_circles_by_year")
extract_ntl_panel(
  polygons   = circles,
  id_col     = "circle_id",
  extra_cols = "gid_0",
  years      = dmsp_years,
  year_files = dmsp_year_files,
  value_col  = "dmsp_ntl",
  out_dir    = out_dir,
  panel_name = here::here("01_datasets/processed/ntl/dmsp_circles_panel.csv")
)
