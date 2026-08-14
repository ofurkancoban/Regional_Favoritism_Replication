# 04_extraction/01_dmsp_adm2.R
# Local (no GEE) replacement for the retired R/07_gee_dmsp_global.R.
#
# Extracts DMSP-OLS stable_lights zonal means (1992-2013) for all PLAD
# countries at ADM2, falling back to ADM1 for the small set of countries
# with no ADM2-level geometry -- identical country/geometry universe logic
# to the original GEE script (GADM 4.1 geoboundaries per-country GeoJSONs,
# data/raw/gadm_4.1/global/geoboundaries/<ISO3>_ADM{1,2}.geojson, with
# data/raw/gadm_4.1/global/no_adm2_countries.txt forcing the ADM1 fallback
# for a couple of territories even when an ADM2 file exists).
#
# Band: stable_lights (HR 2014 p.998's NOAA noise-cleaned product, not the
# raw avg_vis band). Multi-satellite years are pixel-wise averaged by the
# shared engine (00_utils/local_ntl_extraction.R), matching the canonical
# GEE ImageCollection$mean() approach.
#
# Output: data/processed/ntl/dmsp_adm2_panel.csv
#   Columns: region_id, iso3, adm_level, year, dmsp_ntl
#   (region_id = GID_2 for ADM2 rows, GID_1 for ADM1-fallback rows -- same
#   schema 05_panel/01_build_analysis_panel.R expects.)

library(sf)
library(data.table)

source("00_utils/local_ntl_extraction.R")
source("00_utils/dmsp_raster_catalog.R")

gb_dir <- "data/raw/gadm_4.1/global/geoboundaries"
no_adm2_file <- "data/raw/gadm_4.1/global/no_adm2_countries.txt"
no_adm2 <- if (file.exists(no_adm2_file)) readLines(no_adm2_file) else character(0)

plad  <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

cat(sprintf("=== Load GADM 4.1 geoboundaries (ADM2, ADM1 fallback) for %d PLAD countries ===\n", length(iso3s)))
sf::sf_use_s2(FALSE)

country_sf_list <- vector("list", length(iso3s))
for (i in seq_along(iso3s)) {
  iso3 <- iso3s[i]
  adm2_file <- file.path(gb_dir, paste0(iso3, "_ADM2.geojson"))
  adm1_file <- file.path(gb_dir, paste0(iso3, "_ADM1.geojson"))
  use_adm2  <- !iso3 %in% no_adm2 && file.exists(adm2_file)
  geo_file  <- if (use_adm2) adm2_file else adm1_file
  adm_level <- if (use_adm2) "ADM2" else "ADM1"
  if (!file.exists(geo_file)) next

  g <- tryCatch(sf::st_read(geo_file, quiet = TRUE), error = function(e) NULL)
  if (is.null(g) || nrow(g) == 0) next

  id_col <- if ("GID_2" %in% names(g)) "GID_2" else
            if ("GID_1" %in% names(g)) "GID_1" else
            if ("shapeID" %in% names(g)) "shapeID" else names(g)[1]

  g <- g[, c(id_col, "geometry")]
  names(g)[1] <- "region_id"
  g$iso3 <- iso3
  g$adm_level <- adm_level
  country_sf_list[[i]] <- g
}
country_sf_list <- country_sf_list[!vapply(country_sf_list, is.null, logical(1))]
grid <- do.call(rbind, country_sf_list)
rm(country_sf_list)
sf::st_geometry(grid) <- "geometry"
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
