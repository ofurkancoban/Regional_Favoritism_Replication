# ==============================================================================
# File:          12_dmsp_adm1_holepunched_extraction.R
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
# Description:   Local zonal-statistics extraction of DMSP-OLS stable_lights over the hole-punched ADM1 geometry, for Table IV Column (3).
#
# Inputs:        01_datasets/processed/gadm_holepunched_adm1.gpkg, 01_datasets/raw/dmsp_raster_eog_manual/
# Outputs:       01_datasets/processed/ntl/dmsp_adm1_holepunched_panel.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

source("00_utils/local_ntl_extraction.R")
source("00_utils/dmsp_raster_catalog.R")

cat("=== Load hole-punched ADM1 geometries ===\n")
sf::sf_use_s2(FALSE)
holed <- sf::st_read(here::here("01_datasets/processed/gadm_holepunched_adm1.gpkg"), quiet = TRUE)
sf::st_geometry(holed) <- "geometry"
holed$iso3 <- holed$GID_0
cat(sprintf("Hole-punched ADM1 polygons: %d | countries: %d\n",
    nrow(holed), data.table::uniqueN(holed$iso3)))

out_dir <- here::here("01_datasets/processed/ntl/dmsp_adm1_holepunched_by_year")
extract_ntl_panel(
  polygons   = holed,
  id_col     = "GID_1",
  extra_cols = "iso3",
  years      = dmsp_years,
  year_files = dmsp_year_files,
  value_col  = "dmsp_stable_lights_holepunched",
  out_dir    = out_dir,
  panel_name = here::here("01_datasets/processed/ntl/dmsp_adm1_holepunched_panel.csv")
)
