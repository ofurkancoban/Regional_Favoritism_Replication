# R/26_local_download_dmsp_nightlightstats.R
# Purpose: Download the raw DMSP-OLS stable_lights (avg_vis) global GeoTIFFs
# directly from NOAA (ngdc.noaa.gov) via the nightlightstats package, WITHOUT
# going through Google Earth Engine. Full native resolution (30 arc-sec),
# no simplification. Runs alongside (not instead of) the GEE-based export.
#
# nightlightstats' nightlight_download() also keeps a cf_cvg.tif quality
# file per satellite-year that our pipeline does not use -- these are large
# and local disk space is limited, so this script deletes them right after
# each is downloaded (harmless: the package only checks for their existence
# once per year, at the start of that year's own download block).

library(nightlightstats)

out_dir <- "data/raw/dmsp_raster_nightlightstats"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat(sprintf("Downloading DMSP-OLS stable_lights 1992-2013 (world) to %s\n", out_dir))
cat("Source: https://www.ngdc.noaa.gov/eog/data/web_data/v4composites/\n\n")

nightlightstats::nightlight_download(
  area_names     = "world",
  time           = c("1992", "2013"),
  light_location = out_dir
)

cat("\nDownload loop finished.\n")
