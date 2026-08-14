# 04_extraction/02_dmsp_adm1_full.R
# Local (no GEE) replacement for the retired R/13_gee_adm1_stable.R.
# HR 2014 Table IV, Column (2): stable_lights zonal means at the first
# subnational administrative level (SN1/ADM1), all PLAD countries.
#
# Geometry: GADM 3.6 level1 (data/raw/gadm_3.6/gadm36_level1_only.gpkg) --
# same vintage as before, so GID_1 stays consistent with the analysis panel.
# Band/multi-satellite averaging: same as 01_dmsp_adm2.R.
#
# Output: data/processed/ntl/dmsp_adm1_panel.csv
#   Columns: GID_1, iso3, year, dmsp_ntl

library(sf)
library(data.table)

source("00_utils/local_ntl_extraction.R")
source("00_utils/dmsp_raster_catalog.R")

plad  <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

cat("=== Load GADM 3.6 level1 (ADM1) ===\n")
sf::sf_use_s2(FALSE)
adm1 <- sf::st_read("data/raw/gadm_3.6/gadm36_level1_only.gpkg", quiet = TRUE)
sf::st_geometry(adm1) <- "geometry"
adm1 <- adm1[adm1$GID_0 %in% iso3s, ]
adm1$iso3 <- adm1$GID_0
cat(sprintf("ADM1 regions: %d | countries: %d\n", nrow(adm1), data.table::uniqueN(adm1$iso3)))

out_dir <- "data/processed/ntl/dmsp_adm1_by_year"
extract_ntl_panel(
  polygons   = adm1,
  id_col     = "GID_1",
  extra_cols = "iso3",
  years      = dmsp_years,
  year_files = dmsp_year_files,
  value_col  = "dmsp_ntl",
  out_dir    = out_dir,
  panel_name = "data/processed/ntl/dmsp_adm1_panel.csv"
)
