# 04_extraction/04_viirs_adm2.R
# Local (no GEE) replacement for the retired R/08a_gee_viirs_submit.R +
# R/08b_gee_viirs_download.R. Extracts VIIRS VNL annual average_masked
# zonal means (2012-2024) for all PLAD countries, same ADM2/ADM1-fallback
# geometry universe as 01_dmsp_adm2.R (GADM 4.1 geoboundaries).
#
# METHODOLOGY NOTE: the retired GEE script used a DIFFERENT VIIRS product
# (Monthly V1 VCMCFG/VCMSLCFG, band avg_rad, averaged across a year's 12
# monthly composites). This script uses the Annual v2.1/v2.2 average_masked
# product downloaded in this session (00_utils/viirs_raster_catalog.R) --
# a deliberate upgrade (v2.1 fixes a real v2.0 bug; v2.2 fixes an August
# 2022 SNPP sensor gap), not a byte-identical local replacement of the old
# GEE panel. HR 2014 itself does not use VIIRS at all (DMSP-only,
# 1992-2013) -- this is purely this project's own NTL-source extension, so
# there is no "original paper" VIIRS spec to match here.
#
# Output: data/processed/ntl/viirs_adm2_panel.csv
#   Columns: region_id, iso3, adm_level, year, viirs_ntl

library(sf)
library(data.table)

source("00_utils/local_ntl_extraction.R")
source("00_utils/viirs_raster_catalog.R")

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
cat(sprintf("Regions: %d | countries: %d\n", nrow(grid), data.table::uniqueN(grid$iso3)))

out_dir <- "data/processed/ntl/viirs_adm2_by_year"
extract_ntl_panel(
  polygons   = grid,
  id_col     = "region_id",
  extra_cols = c("iso3", "adm_level"),
  years      = viirs_years,
  year_files = viirs_year_files,
  value_col  = "viirs_ntl",
  out_dir    = out_dir,
  panel_name = "data/processed/ntl/viirs_adm2_panel.csv"
)
