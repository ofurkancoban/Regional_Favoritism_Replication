# ==============================================================================
# File:          16_harmonized_dmsp_viirs_adm2.R
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
# Description:   Builds the harmonized DMSP/VIIRS panel (Li et al. 2020 inter-satellite calibration): 1992-2013 inter-calibrated DMSP-OLS, 2014-2023 VIIRS converted onto DMSP's 0-63 digital-number scale, one continuous series for the extension.
#
# Inputs:        01_datasets/processed/ntl/dmsp_adm2_panel.csv, 01_datasets/processed/ntl/viirs_adm2_panel.csv
# Outputs:       01_datasets/processed/ntl/harmonized_dmsp_viirs_adm2_panel.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

source("00_utils/local_ntl_extraction.R")

raw_dir <- "/Users/ofurkancoban/Downloads/9828827"
harmonized_years <- 1992:2024
harmonized_year_files <- function(yr) {
  suffix <- if (yr <= 2013) "calDMSP" else "simVIIRS"
  file.path(raw_dir, sprintf("Harmonized_DN_NTL_%d_%s.tif", yr, suffix))
}

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

has_adm2 <- unique(adm2$iso3)
adm1_fallback <- adm1[!adm1$iso3 %in% has_adm2, ]

grid <- rbind(adm2[, c("region_id", "iso3", "adm_level")],
              adm1_fallback[, c("region_id", "iso3", "adm_level")])
cat(sprintf("Regions: %d | ADM2: %d | ADM1-fallback: %d | countries: %d\n",
    nrow(grid), sum(grid$adm_level == "ADM2"), sum(grid$adm_level == "ADM1"),
    data.table::uniqueN(grid$iso3)))

out_dir <- here::here("01_datasets/processed/ntl/harmonized_dmsp_viirs_adm2_by_year")
extract_ntl_panel(
  polygons   = grid,
  id_col     = "region_id",
  extra_cols = c("iso3", "adm_level"),
  years      = harmonized_years,
  year_files = harmonized_year_files,
  value_col  = "harmonized_ntl",
  out_dir    = out_dir,
  panel_name = here::here("01_datasets/processed/ntl/harmonized_dmsp_viirs_adm2_panel.csv")
)
