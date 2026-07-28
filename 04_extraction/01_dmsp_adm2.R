# 04_extraction/01_dmsp_adm2.R
# Local (no GEE) replacement for the retired R/07_gee_dmsp_global.R.
#
# Extracts DMSP-OLS stable_lights zonal means (1992-2013) for all PLAD
# countries at ADM2, falling back to ADM1 for countries with no ADM2-level
# geometry.
#
# Geometry: GADM 3.6 (data/raw/gadm_3.6/gadm36_levels.gpkg, layers level2/
# level1) -- matches DHR's own replication panel and HR 2014's original
# vintage exactly (DHR's `adm_2.csv.gz` uses GADM 3.6 GID_2 identifiers,
# format COL.1.1_1). Previously this script used GADM 4.1 per-country
# geoboundaries GeoJSONs, which required a GID crosswalk
# (data/processed/gadm36_41_crosswalk.csv) to reconcile back to the
# analysis panel's other GADM-3.6-vintage inputs (PLAD birthplace match,
# GPWv4 population) -- switching the source geometry to GADM 3.6 directly
# removes that translation step entirely for the core replication.
#
# Band: stable_lights (HR 2014 p.998's NOAA noise-cleaned product, not the
# raw avg_vis band). Multi-satellite years are pixel-wise averaged by the
# shared engine (00_utils/local_ntl_extraction.R), matching the canonical
# GEE ImageCollection$mean() approach.
#
# Output: data/processed/ntl/dmsp_adm2_panel.csv
#   Columns: region_id, iso3, adm_level, year, dmsp_ntl
#   (region_id = GID_2 for ADM2 rows, GID_1 for ADM1-fallback rows -- same
#   schema 06_panel/01_build_analysis_panel.R expects.)

library(sf)
library(data.table)

source("00_utils/local_ntl_extraction.R")
source("00_utils/dmsp_raster_catalog.R")

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

out_dir <- "data/processed/ntl/dmsp_adm2_by_year"
extract_ntl_panel(
  polygons   = grid,
  id_col     = "region_id",
  extra_cols = c("iso3", "adm_level"),
  years      = dmsp_years,
  year_files = dmsp_year_files,
  value_col  = "dmsp_ntl",
  out_dir    = out_dir,
  panel_name = "data/processed/ntl/dmsp_adm2_panel.csv"
)
