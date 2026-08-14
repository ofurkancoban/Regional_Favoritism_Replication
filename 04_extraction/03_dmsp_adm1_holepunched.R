# 04_extraction/03_dmsp_adm1_holepunched.R
# Local (no GEE) replacement for the retired R/16_gee_adm1_holepunched.R.
# HR 2014 Table IV, Column (3): stable_lights zonal means over the
# hole-punched ADM1 polygons (582 affected regions, birth-ADM2 sub-polygons
# geometrically removed via st_difference -- see 03_geometry/02_build_holepunched_adm1.R,
# formerly R/15) -- "we omit all SN2 regions in which a political leader
# from our sample was ever born" (p. 1018).
#
# GEE's three-tier fast-path/chunk/part-split strategy in the old script
# existed only to work around GEE payload/timeout limits -- irrelevant
# locally, exactextractr handles arbitrarily complex polygons directly.
#
# Output: data/processed/ntl/dmsp_adm1_holepunched_panel.csv
#   Columns: GID_1, iso3, year, dmsp_stable_lights_holepunched
#   (column name matches what 06_regression/table4/02_col23_holepunch.R,
#   formerly R/17, already expects when merging with the full-area panel.)

library(sf)
library(data.table)

source("00_utils/local_ntl_extraction.R")
source("00_utils/dmsp_raster_catalog.R")

cat("=== Load hole-punched ADM1 geometries ===\n")
sf::sf_use_s2(FALSE)
holed <- sf::st_read("data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE)
sf::st_geometry(holed) <- "geometry"
holed$iso3 <- holed$GID_0
cat(sprintf("Hole-punched ADM1 polygons: %d | countries: %d\n",
    nrow(holed), data.table::uniqueN(holed$iso3)))

out_dir <- "data/processed/ntl/dmsp_adm1_holepunched_by_year"
extract_ntl_panel(
  polygons   = holed,
  id_col     = "GID_1",
  extra_cols = "iso3",
  years      = dmsp_years,
  year_files = dmsp_year_files,
  value_col  = "dmsp_stable_lights_holepunched",
  out_dir    = out_dir,
  panel_name = "data/processed/ntl/dmsp_adm1_holepunched_panel.csv"
)
