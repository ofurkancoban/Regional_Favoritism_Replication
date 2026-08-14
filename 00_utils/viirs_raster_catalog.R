# 00_utils/viirs_raster_catalog.R
# Shared VIIRS year -> raw GeoTIFF file catalog.
#
# Product: VNL (VIIRS Nighttime Lights) annual composites, v2.1 (2012-2021)
# and v2.2 (2022-2024), band "average_masked" (background-zeroed annual
# average radiance -- the VIIRS analogue of DMSP's stable_lights: persistent
# lighting only, ephemeral/noise sources removed). Downloaded directly from
# EOG (01_download/07_download_viirs_raw.R, formerly R/29_download_viirs_annual_v2.R).
#
# NOTE on methodology divergence from the earlier GEE VIIRS pipeline: the
# now-retired R/08a_gee_viirs_submit.R used a DIFFERENT VIIRS product --
# Monthly V1 (VCMCFG/VCMSLCFG collections), band avg_rad, averaged across
# the year's 12 monthly composites. That choice predates the deliberate
# switch (documented in this session) to the Annual v2.1/v2.2 average_masked
# product: v2.0 had a real bug (monthly radiances sometimes paired with the
# wrong month's cloud-free-coverage count), fixed in v2.1; v2.2 corrects an
# August 2022 SNPP sensor gap via NOAA-20 blending. HR 2014 itself does not
# use VIIRS at all (their sample is DMSP-only, 1992-2013) -- VIIRS is this
# project's own extension, so there is no "original paper" band/version to
# match here, but this IS a genuine product change from the old GEE-era
# panel, not a byte-for-byte local replacement of it.

viirs_raw_root <- "data/raw/viirs_raster_eog_manual"
viirs_years <- 2012:2024

#' year -> single raw VIIRS GeoTIFF path for that year (filenames embed an
#' unpredictable creation timestamp, so match by glob, not a fixed pattern).
viirs_year_files <- function(yr) {
  yr_dir <- file.path(viirs_raw_root, as.character(yr))
  if (!dir.exists(yr_dir)) return(character(0))
  f <- list.files(yr_dir, pattern = "average_masked.*\\.tif$", full.names = TRUE)
  if (length(f) == 0) return(character(0))
  f[1]
}
