# 04_extraction/06_dmsp_birthplace_circles.R
# HR 2014 Table IV Col(1): DMSP-OLS stable_lights zonal means for the 5km
# birthplace circles built in 03_geometry/03_build_birthplace_circles.R.
#
# Output: data/processed/ntl/dmsp_circles_panel.csv
#   Columns: circle_id, gid_0, year, dmsp_ntl

library(sf)
library(data.table)

source("00_utils/local_ntl_extraction.R")
source("00_utils/dmsp_raster_catalog.R")

cat("=== Load birthplace circles ===\n")
sf::sf_use_s2(FALSE)
circles <- sf::st_read("data/processed/birthplace_circles_5km.gpkg", quiet = TRUE)
sf::st_geometry(circles) <- "geometry"
cat(sprintf("Circles: %d\n", nrow(circles)))

out_dir <- "data/processed/ntl/dmsp_circles_by_year"
extract_ntl_panel(
  polygons   = circles,
  id_col     = "circle_id",
  extra_cols = "gid_0",
  years      = dmsp_years,
  year_files = dmsp_year_files,
  value_col  = "dmsp_ntl",
  out_dir    = out_dir,
  panel_name = "data/processed/ntl/dmsp_circles_panel.csv"
)
