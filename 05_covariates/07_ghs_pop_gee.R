# Purpose: GHS-POP (Schiavina et al. 2023) zonal-sum to GADM 3.6 ADM2, via
# Google Earth Engine server-side reduceRegions instead of downloading raw
# global 3-arcsecond rasters (10-12.5GB/year) and processing them locally.
#
# Context: the VPS-based raw-raster pipeline (curl download + terra::zonal
# against a pre-built id raster) repeatedly OOM-killed on the smaller VPS
# instances (7.8-11GB RAM) even after switching from exactextractr to
# terra::zonal(); it is still running in the background as an independent
# check, but GEE avoids the download/memory problem entirely by running
# the reduction in Google's own infrastructure. Run this locally (not on
# the VPS) -- it only needs a GEE-authenticated environment, which this
# project already has (see 04_extraction/08_turkey_gee_viirs_monthly.R).
#
# Note on project GEE policy: this project otherwise eliminated GEE from
# its NTL extraction pipeline (see plan "Eliminate GEE dependency", 2026)
# to keep DMSP/VIIRS extraction fully local and reproducible without an
# external quota-limited API. This one covariate (population, not the
# outcome variable) is a deliberate, narrow exception -- GHS-POP itself is
# a static published product (no extraction methodology choices at stake
# the way band/satellite selection matters for NTL), and processing it
# via GEE does not affect any light-data result.
#
# Output: data/processed/population_adm2_ghspop.csv
#   Columns: GID_2, GID_0, year, pop_count, lnpop  (same schema as
#   02_gpw_population.R and 06_dhr_population.R, so downstream code can
#   swap the population source with no changes).
library(reticulate)
library(data.table)
library(sf)
library(R.utils)

reticulate::use_virtualenv("~/.virtualenvs/gee_research_env", required = TRUE)
ee <- reticulate::import("ee")
ee$Initialize(project = "regional-favoritism")

years <- c(1990L, 1995L, 2000L, 2005L, 2010L, 2015L, 2020L)

cat("=== Load GADM 3.6 ADM2 ===\n")
adm <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
adm <- adm[, c("GID_0", "GID_1", "GID_2")]
cat(sprintf("Regions: %d\n", nrow(adm)))

# Simplify boundaries before shipping as GeoJSON -- GEE's reduceRegions()
# payload has a 10MB request limit, and some countries' ADM2 polygons
# (Argentina, Australia, Bangladesh's complex coastlines/deltas) exceed it
# even in small batches. ~100m tolerance is well below GHS-POP's own 100m
# processing scale, so this does not affect the zonal sums meaningfully.
sf::sf_use_s2(FALSE)
adm <- sf::st_simplify(adm, dTolerance = 0.001, preserveTopology = TRUE)

# Server-side reduceRegions needs an ee.FeatureCollection. GeoJSON
# round-trip (same pattern as 08_turkey_gee_viirs_monthly.R) is simplest;
# batch by country to stay under GEE's per-request feature/payload limits
# (45,962 ADM2 polygons in one call would likely time out or hit quota).
countries <- sort(unique(adm$GID_0))
cat(sprintf("Countries: %d\n", length(countries)))

out_dir <- "data/processed/ntl/ghs_pop_gee_by_country"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

fc_from_sf <- function(sf_obj) {
  gj <- tempfile(fileext = ".geojson")
  sf::st_write(sf_obj, gj, quiet = TRUE)
  ee$FeatureCollection(reticulate::py_eval(sprintf(
    "__import__('json').load(open('%s'))", gj), convert = FALSE))
}

# All 7 years as a single multi-band image (one band per year, renamed
# y1990..y2020) so reduceRegions() returns every year's sum per polygon in
# one server-side call -- cuts total requests from 174 countries x 7 years
# (1,218 calls) down to ~174-300 calls (some large countries chunked),
# roughly 7x fewer round-trips.
imgs <- lapply(years, function(y)
  ee$Image(sprintf("JRC/GHSL/P2023A/GHS_POP/%d", y))$select("population_count")$rename(sprintf("y%d", y)))
multi <- Reduce(function(a, b) a$addBands(b), imgs)

reduce_chunk <- function(sub) {
  fc <- fc_from_sf(sub)
  reduced <- multi$reduceRegions(collection = fc, reducer = ee$Reducer$sum(),
                                  scale = 100, tileScale = 4)
  # Some complex-coastline countries (AUS, IDN, PHL, NOR...) have caused a
  # single reduceRegions()$getInfo() call to hang indefinitely (no error,
  # no progress) rather than fail fast on payload size -- cap each call so
  # a stuck request degrades into a retriable failure instead of freezing
  # the whole run.
  info <- R.utils::withTimeout(reduced$getInfo(), timeout = 90, onTimeout = "error")
  feats <- info$features
  if (length(feats) == 0) return(NULL)
  rbindlist(lapply(feats, function(f) {
    p <- f$properties
    as.data.table(p[c("GID_0", "GID_1", "GID_2", sprintf("y%d", years))])
  }), fill = TRUE)
}

# Large/geometrically complex countries risk exceeding GEE's 10MB
# reduceRegions request payload -- recursively halve the chunk until it
# fits, rather than assuming a fixed feature count is always safe.
reduce_with_retry <- function(sub, depth = 0) {
  if (nrow(sub) == 0) return(NULL)
  result <- tryCatch(list(ok = TRUE, val = reduce_chunk(sub)),
                      error = function(e) list(ok = FALSE, msg = conditionMessage(e)))
  if (result$ok) return(result$val)
  if (nrow(sub) <= 1 || depth > 12) {
    cat(sprintf("    single-feature chunk still failing, skipping: %s\n", result$msg))
    return(NULL)
  }
  mid <- ceiling(nrow(sub) / 2)
  rbindlist(list(reduce_with_retry(sub[seq_len(mid), ], depth + 1),
                 reduce_with_retry(sub[(mid + 1):nrow(sub), ], depth + 1)), fill = TRUE)
}

process_country <- function(iso3) {
  out_csv <- file.path(out_dir, sprintf("%s.csv", iso3))
  skip_marker <- file.path(out_dir, sprintf("%s.SKIPPED", iso3))
  if (file.exists(out_csv) || file.exists(skip_marker)) return(invisible(NULL))

  sub <- adm[adm$GID_0 == iso3, ]
  n <- nrow(sub)
  chunk_size <- 150L
  n_chunks <- ceiling(n / chunk_size)

  # Some countries (Canada, Russia, Indonesia, Philippines, Norway...) have
  # thousands of small islands/fjords -- the recursive per-chunk retry can
  # still take a very long time in aggregate even though each individual
  # call eventually resolves. Cap the WHOLE country's processing time so
  # one pathological country can't stall the entire 166-country run;
  # these are left to the VPS raw-raster pipeline instead, which doesn't
  # care about per-request payload/geometry complexity.
  country_result <- tryCatch(
    R.utils::withTimeout({
      chunks <- lapply(seq_len(n_chunks), function(k) {
        idx <- ((k - 1) * chunk_size + 1):min(k * chunk_size, n)
        reduce_with_retry(sub[idx, ])
      })
      rbindlist(chunks, fill = TRUE)
    }, timeout = 240, onTimeout = "error"),
    error = function(e) {
      cat(sprintf("  [%s] failed/timed out (%d regions, %d chunks): %s -- skipping, will rely on VPS raw-raster pipeline for this country\n",
          iso3, n, n_chunks, conditionMessage(e)))
      NULL
    })
  if (is.null(country_result) || nrow(country_result) == 0) {
    file.create(skip_marker)
    return(invisible(NULL))
  }
  fwrite(country_result, out_csv)
}

cat("\n=== Zonal sum via GEE reduceRegions, batched by country (all 7 years per call) ===\n")
t0 <- Sys.time()
for (i in seq_along(countries)) {
  process_country(countries[i])
  if (i %% 20 == 0) {
    cat(sprintf("[%d/%d countries] elapsed %.1f min\n", i, length(countries),
                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  }
}
cat(sprintf("Done in %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))

cat("\n=== Assemble panel (wide year-columns -> long) ===\n")
files <- list.files(out_dir, pattern = "\\.csv$", full.names = TRUE)
wide <- rbindlist(lapply(files, fread), fill = TRUE)
year_cols <- sprintf("y%d", years)
panel <- melt(wide, id.vars = c("GID_0", "GID_1", "GID_2"),
               measure.vars = year_cols, variable.name = "year", value.name = "pop_count")
panel[, year := as.integer(sub("^y", "", year))]
panel[, pop_count := round(pop_count)]
panel[, lnpop := log(pmax(pop_count, 1) / 1000)]
cat(sprintf("Panel: %d rows | %d regions | %d countries | years %s\n",
    nrow(panel), uniqueN(panel$GID_2), uniqueN(panel$GID_0),
    paste(sort(unique(panel$year)), collapse = ",")))

fwrite(panel[, .(GID_2, GID_0, year, pop_count, lnpop)],
       "data/processed/population_adm2_ghspop.csv")
cat("Saved: data/processed/population_adm2_ghspop.csv\n")
