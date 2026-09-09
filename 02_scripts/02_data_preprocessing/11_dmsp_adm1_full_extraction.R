# ==============================================================================
# File:          11_dmsp_adm1_full_extraction.R
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
# Description:   Local zonal-statistics extraction of DMSP-OLS stable_lights over full-area GADM 3.6 ADM1 polygons, for Table IV Column (2).
#
# Inputs:        01_datasets/raw/dmsp_raster_eog_manual/, GADM 3.6 ADM1 geometry
# Outputs:       01_datasets/processed/ntl/dmsp_adm1_panel.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

source(here::here("02_scripts", "04_tools", "local_ntl_extraction.R"))
source(here::here("02_scripts", "04_tools", "dmsp_raster_catalog.R"))

plad  <- data.table::fread(here::here("01_datasets/raw/plad/PLAD_April_2024.tab"), sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

cat("=== Load GADM 3.6 level1 (ADM1) ===\n")
sf::sf_use_s2(FALSE)
adm1 <- sf::st_read(here::here("01_datasets/raw/gadm_3.6/gadm36_level1_only.gpkg"), quiet = TRUE)
sf::st_geometry(adm1) <- "geometry"
adm1 <- adm1[adm1$GID_0 %in% iso3s, ]
adm1$iso3 <- adm1$GID_0
cat(sprintf("ADM1 regions: %d | countries: %d\n", nrow(adm1), data.table::uniqueN(adm1$iso3)))

out_dir <- here::here("01_datasets/processed/ntl/dmsp_adm1_by_year")
extract_ntl_panel(
  polygons   = adm1,
  id_col     = "GID_1",
  extra_cols = "iso3",
  years      = dmsp_years,
  year_files = dmsp_year_files,
  value_col  = "dmsp_ntl",
  out_dir    = out_dir,
  panel_name = here::here("01_datasets/processed/ntl/dmsp_adm1_panel.csv")
)
