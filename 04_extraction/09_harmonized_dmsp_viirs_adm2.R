# 04_extraction/09_harmonized_dmsp_viirs_adm2.R
# Extracts zonal means (1992-2024) from Li, Zhou, Zhao & Zhao's harmonized
# DMSP-OLS/VIIRS nighttime lights dataset for all PLAD countries at ADM2,
# falling back to ADM1 for countries with no ADM2-level geometry.
#
# Source: "Harmonization of DMSP and VIIRS nighttime light data from
# 1992-2024 at the global scale" (figshare 10.6084/m9.figshare.9828827),
# building on the stepwise inter-satellite calibration method described in
# Li & Zhou (2017, Remote Sens. 9, 637). 1992-2013 is calibrated DMSP-OLS
# (Harmonized_DN_NTL_YYYY_calDMSP.tif); 2014-2024 is VIIRS converted onto
# the same 0-63 DMSP DN scale (Harmonized_DN_NTL_YYYY_simVIIRS.tif) -- both
# halves are directly comparable in one continuous 33-year series, solving
# the DMSP/VIIRS scale-discontinuity problem this project spent most of
# 2026-08-19 trying to solve via a from-scratch Black Marble pipeline.
# Confirmed 2026-08-19: both halves share the same 0-63 range, 30
# arc-second resolution, WGS84, -65 to 75 deg latitude coverage.
#
# The source authors suggest treating DN <= 7 as noise floor; this script
# extracts the raw zonal mean and leaves that filtering decision to the
# analysis stage (matching this project's convention elsewhere of keeping
# raw extracted values and applying thresholds downstream, not baked into
# the extraction step).
#
# Geometry: GADM 3.6 (matches every other extraction driver in this
# project -- DHR's own replication panel, PLAD birthplace match, GPWv4
# population all use this vintage).
#
# Output: data/processed/ntl/harmonized_dmsp_viirs_adm2_panel.csv
#   Columns: region_id, iso3, adm_level, year, harmonized_ntl

library(sf)
library(data.table)

source("00_utils/local_ntl_extraction.R")

raw_dir <- "/Users/ofurkancoban/Downloads/9828827"
harmonized_years <- 1992:2024
harmonized_year_files <- function(yr) {
  suffix <- if (yr <= 2013) "calDMSP" else "simVIIRS"
  file.path(raw_dir, sprintf("Harmonized_DN_NTL_%d_%s.tif", yr, suffix))
}

plad  <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

cat(sprintf("=== Load GADM 3.6 (ADM2, ADM1 fallback) for %d PLAD countries ===\n", length(iso3s)))
sf::sf_use_s2(FALSE)

adm2 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
sf::st_geometry(adm2) <- "geometry"
adm2 <- adm2[adm2$GID_0 %in% iso3s, c("GID_0", "GID_2", "geometry")]
data.table::setnames(adm2, c("GID_0", "GID_2"), c("iso3", "region_id"))
adm2$adm_level <- "ADM2"

adm1 <- sf::st_read("data/raw/gadm_3.6/gadm36_level1_only.gpkg", quiet = TRUE)
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

out_dir <- "data/processed/ntl/harmonized_dmsp_viirs_adm2_by_year"
extract_ntl_panel(
  polygons   = grid,
  id_col     = "region_id",
  extra_cols = c("iso3", "adm_level"),
  years      = harmonized_years,
  year_files = harmonized_year_files,
  value_col  = "harmonized_ntl",
  out_dir    = out_dir,
  panel_name = "data/processed/ntl/harmonized_dmsp_viirs_adm2_panel.csv"
)
