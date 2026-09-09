# 02_scripts/04_tools/dmsp_raster_catalog.R
# Shared DMSP-OLS year -> satellite raw GeoTIFF file catalog, used by every
# local DMSP zonal-extraction script (ADM2, ADM1, ADM1 hole-punched, grid
# cells). Files are downloaded automatically by
# 02_data_preprocessing/03_download_dmsp_raw.R -- band is "stable_lights"
# (NOAA's noise-cleaned product; HR 2014 p.998 explicitly use this, not the
# raw "avg_vis" band). Multiple satellites overlap in some years; the
# shared engine (local_ntl_extraction.R) pixel-wise-averages them, matching
# the canonical GEE ImageCollection$mean() approach.

dmsp_raw_root <- here::here("01_datasets", "raw", "dmsp_raster_eog_manual")

dmsp_year_sat <- list(
  "1992" = "F10", "1993" = "F10",
  "1994" = c("F10", "F12"),
  "1995" = "F12", "1996" = "F12",
  "1997" = c("F12", "F14"), "1998" = c("F12", "F14"), "1999" = c("F12", "F14"),
  "2000" = c("F14", "F15"), "2001" = c("F14", "F15"),
  "2002" = c("F14", "F15"), "2003" = c("F14", "F15"),
  "2004" = c("F15", "F16"), "2005" = c("F15", "F16"),
  "2006" = c("F15", "F16"), "2007" = c("F15", "F16"),
  "2008" = "F16", "2009" = "F16",
  "2010" = "F18", "2011" = "F18", "2012" = "F18", "2013" = "F18"
)

dmsp_version_suffix <- function(sat, yr) {
  ifelse(sat == "F18", ifelse(yr == "2010", "v4d", "v4c"), "v4b")
}

#' year -> vector of raw DMSP GeoTIFF paths for that year (1+ satellites).
dmsp_year_files <- function(yr) {
  yr_chr <- as.character(yr)
  sats <- dmsp_year_sat[[yr_chr]]
  if (is.null(sats)) return(character(0))
  vs <- dmsp_version_suffix(sats, yr_chr)
  file.path(dmsp_raw_root, yr_chr,
      sprintf("%s%s.%s.global.stable_lights.avg_vis.tif", sats, yr_chr, vs))
}

dmsp_years <- 1992:2013
