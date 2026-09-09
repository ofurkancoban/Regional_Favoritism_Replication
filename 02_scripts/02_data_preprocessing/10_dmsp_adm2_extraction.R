# ==============================================================================
# File:          10_dmsp_adm2_extraction.R
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
# Description:   Local zonal-statistics extraction (exactextractr, no Google Earth Engine) of DMSP-OLS stable_lights over GADM 4.1 ADM2 polygons -- the main replication panel's nighttime-lights source.
#
# Inputs:        01_datasets/raw/dmsp_raster_eog_manual/, GADM 4.1 ADM2 geometry
# Outputs:       01_datasets/processed/ntl/dmsp_adm2_panel.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

source(here::here("02_scripts", "04_tools", "local_ntl_extraction.R"))
source(here::here("02_scripts", "04_tools", "dmsp_raster_catalog.R"))

plad  <- data.table::fread(here::here("01_datasets/raw/plad/PLAD_April_2024.tab"), sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

cat(sprintf("=== Load GADM 3.6 (ADM2, ADM1 fallback) for %d PLAD countries ===\n", length(iso3s)))
sf::sf_use_s2(FALSE)

adm2 <- sf::st_read(here::here("01_datasets/raw/gadm_3.6/gadm36_levels.gpkg"), layer = "level2", quiet = TRUE)
sf::st_geometry(adm2) <- "geometry"
adm2 <- adm2[adm2$GID_0 %in% iso3s, c("GID_0", "GID_2", "geometry")]
data.table::setnames(adm2, c("GID_0", "GID_2"), c("iso3", "region_id"))
adm2$adm_level <- "ADM2"

adm1 <- sf::st_read(here::here("01_datasets/raw/gadm_3.6/gadm36_level1_only.gpkg"), quiet = TRUE)
sf::st_geometry(adm1) <- "geometry"
adm1 <- adm1[adm1$GID_0 %in% iso3s, c("GID_0", "GID_1", "geometry")]
data.table::setnames(adm1, c("GID_0", "GID_1"), c("iso3", "region_id"))
adm1$adm_level <- "ADM1"

# ADM1 fallback only for countries with no ADM2 geometry at all -- same
# logic as the retired GADM 4.1 version (a couple of small territories
# have no level2 breakdown in GADM).
has_adm2 <- unique(adm2$iso3)
adm1_fallback <- adm1[!adm1$iso3 %in% has_adm2, ]

grid <- rbind(adm2[, c("region_id", "iso3", "adm_level")],
              adm1_fallback[, c("region_id", "iso3", "adm_level")])
cat(sprintf("Regions: %d | ADM2: %d | ADM1-fallback: %d | countries: %d\n",
    nrow(grid), sum(grid$adm_level == "ADM2"), sum(grid$adm_level == "ADM1"),
    data.table::uniqueN(grid$iso3)))

out_dir <- here::here("01_datasets/processed/ntl/dmsp_adm2_by_year")
extract_ntl_panel(
  polygons   = grid,
  id_col     = "region_id",
  extra_cols = c("iso3", "adm_level"),
  years      = dmsp_years,
  year_files = dmsp_year_files,
  value_col  = "dmsp_ntl",
  out_dir    = out_dir,
  panel_name = here::here("01_datasets/processed/ntl/dmsp_adm2_panel.csv")
)
