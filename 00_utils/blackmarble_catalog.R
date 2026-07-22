# 00_utils/blackmarble_catalog.R
# Shared helpers for the NASA Black Marble (VNP46A3 monthly) VIIRS pipeline
# -- replaces the annual EOG/Payne Institute VIIRS composite as this
# project's VIIRS source (2026-08-18 decision: monthly frequency is
# required for any future event-study / crisis-interaction extension in
# the spirit of Bora 2025, which the annual-only EOG product cannot
# support at all).
#
# Auth: NASA Earthdata Login credentials must be present in ~/.netrc as
#   machine urs.earthdata.nasa.gov login <user> password <pass>
# `get_nasa_token()` exchanges these for a bearer token (valid ~60 days).
#
# Raw HDF5 tile cache: redirected to an external drive
# (/Volumes/Intenso/GIS/blackmarble_raw) since the global monthly tile
# cache is large and local disk space was nearly exhausted (23GB free
# locally vs. 476GB free on the external drive) as of 2026-08-18.

library(blackmarbler)

# Overridable via BLACKMARBLE_H5_DIR so the same driver script can run on
# multiple machines (each with its own disk layout) processing different
# month ranges in parallel. Confirmed 2026-08-19.
blackmarble_h5_dir <- Sys.getenv("BLACKMARBLE_H5_DIR", "/Volumes/Intenso/GIS/blackmarble_raw")
dir.create(blackmarble_h5_dir, showWarnings = FALSE, recursive = TRUE)

#' Get (or refresh) a NASA bearer token from ~/.netrc credentials.
get_blackmarble_token <- function() {
  netrc <- readLines("~/.netrc")
  line <- grep("urs.earthdata.nasa.gov", netrc, value = TRUE)[1]
  user <- sub(".*login ([^ ]+).*", "\\1", line)
  pass <- sub(".*password (.+)$", "\\1", line)
  blackmarbler::get_nasa_token(username = user, password = pass)
}

# VNP46A3 (monthly) is available from January 2012 (VIIRS launched Oct
# 2011; Jan 2012 is the first full calendar month) onward. DMSP-OLS runs
# through 2013, giving a 2012-2013 overlap window for any future
# calibration/harmonization work.
blackmarble_months <- function(end_date = Sys.Date()) {
  seq(as.Date("2012-01-01"), as.Date(format(end_date, "%Y-%m-01")), by = "month")
}

#' Which Black Marble sinusoidal-grid tiles intersect our region set.
#' Tile geometry is date-independent, so this only needs to be computed
#' once per session and reused across every month -- the sequential,
#' one-tile-at-a-time httr download in blackmarbler::download_h5_files()
#' was network-latency-bound (observed: ~93s of actual compute time vs.
#' ~20 minutes of wall time for a single month, i.e. almost entirely
#' waiting on serial HTTP round-trips), so we instead pre-fetch the tile
#' list once and download tiles for each month in parallel via curl.
get_blackmarble_tile_ids <- function(roi_sf) {
  bm_tiles_sf <- sf::read_sf("https://raw.githubusercontent.com/worldbank/blackmarbler/main/data/blackmarbletiles.geojson")
  bm_tiles_sf <- bm_tiles_sf[!grepl("h00", bm_tiles_sf$TileID), ]
  bm_tiles_sf <- bm_tiles_sf[!grepl("v00", bm_tiles_sf$TileID), ]
  inter <- apply(sf::st_intersects(bm_tiles_sf, roi_sf, sparse = FALSE), 1, sum)
  bm_tiles_sf$TileID[inter > 0]
}

#' Patch blackmarbler::bm_extract()'s internal bm_raster_i() so it reads
#' the Black Marble tile grid from a local on-disk cache instead of
#' re-fetching https://raw.githubusercontent.com/.../blackmarbletiles.geojson
#' from GitHub on every single call. Tile geometry never changes, so with
#' EXTRACT_BATCH_SIZE=20 and 174 countries this GitHub fetch alone was
#' happening ~9 times per month (once per batch), each adding real network
#' latency on top of the h5 download/extract work. Confirmed 2026-08-19.
#' Call once per session, before any bm_extract() call.
patch_blackmarble_tile_cache <- function(cache_file = file.path(blackmarble_h5_dir, "blackmarbletiles.geojson")) {
  if (!file.exists(cache_file)) {
    sf::write_sf(
      sf::read_sf("https://raw.githubusercontent.com/worldbank/blackmarbler/main/data/blackmarbletiles.geojson"),
      cache_file
    )
  }
  ns <- asNamespace("blackmarbler")
  f <- ns$bm_raster_i
  src <- deparse(f)
  src <- sub(
    'read_sf\\("https://raw\\.githubusercontent\\.com/worldbank/blackmarbler/main/data/blackmarbletiles\\.geojson"\\)',
    sprintf('read_sf(%s)', deparse(cache_file)),
    src
  )
  f_patched <- eval(parse(text = src), envir = environment(f))
  environment(f_patched) <- environment(f)
  unlockBinding("bm_raster_i", ns)
  assign("bm_raster_i", f_patched, envir = ns)
  lockBinding("bm_raster_i", ns)
  invisible(NULL)
}

#' Download all VNP46A3 h5 tiles for one year-month, in parallel, into
#' `blackmarble_h5_dir`. Skips tiles already present. Returns invisibly.
download_blackmarble_month_parallel <- function(ym, tile_ids, token,
                                                  n_parallel = 12, timeout_s = 120) {
  d <- as.Date(paste0(ym, "-01"))
  year <- format(d, "%Y")
  day  <- sprintf("%03d", as.integer(format(d, "%j")))
  csv_url <- sprintf(
    "https://ladsweb.modaps.eosdis.nasa.gov/archive/allData/5200/VNP46A3/%s/%s.csv",
    year, day)
  listing <- tryCatch(data.table::fread(csv_url), error = function(e) NULL)
  if (is.null(listing) || nrow(listing) == 0) {
    cat(sprintf("  [%s] no file listing available\n", ym)); return(invisible(NULL))
  }
  tile_rx <- paste(tile_ids, collapse = "|")
  files <- listing$name[grepl(tile_rx, listing$name)]
  files <- files[!file.exists(file.path(blackmarble_h5_dir, files))]
  if (length(files) == 0) return(invisible(NULL))

  url_list_file <- tempfile()
  urls <- sprintf("url = \"https://ladsweb.modaps.eosdis.nasa.gov/archive/allData/5200/VNP46A3/%s/%s/%s\"\noutput = \"%s\"",
                   year, day, files, file.path(blackmarble_h5_dir, files))
  writeLines(urls, url_list_file)

  system2("curl", c(
    "--silent", "--fail", "--retry", "3", "--max-time", as.character(timeout_s),
    "--parallel", "--parallel-max", as.character(n_parallel),
    "-H", shQuote(paste("Authorization: Bearer", token)),
    "-K", url_list_file
  ))
  unlink(url_list_file)
  invisible(NULL)
}
