# 05_covariates/02_gpw_population.R
# Purpose: Build ADM2-level population panel from GPWv4 (CIESIN) via geodata package.
# Source: Gridded Population of the World v4, 5 arc-minute resolution.
# Years:  2000, 2005, 2010 (covers 1993-2013 via interpolation/extrapolation).
# Method: Zonal sum of GPW raster over GADM 3.6 ADM2 polygons.
# Output: data/processed/population_adm2.csv

library(data.table)
library(terra)
library(sf)
library(geodata)

pop_dir <- "data/raw/gpw"
dir.create(pop_dir, showWarnings = FALSE)

cat("=== Step 1: Download GPWv4 population rasters ===\n")
gpw_years <- c(2000L, 2005L, 2010L)
rasters <- lapply(gpw_years, function(yr) {
  cat(sprintf("  Downloading GPWv4 year %d...\n", yr))
  r <- tryCatch(
    geodata::population(year = yr, res = 5, path = pop_dir),
    error = function(e) { cat("  Error:", conditionMessage(e), "\n"); NULL }
  )
  r
})
names(rasters) <- gpw_years
cat("Downloaded:", sum(!sapply(rasters, is.null)), "/", length(gpw_years), "years\n")

cat("\n=== Step 2: Load GADM 3.6 ADM2 polygons ===\n")
sf::sf_use_s2(FALSE)
sf36 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
gadm_v <- terra::vect(sf36[, c("GID_0", "GID_2")])
cat(sprintf("GADM 3.6 ADM2: %d regions\n", nrow(gadm_v)))

cat("\n=== Step 3: Zonal sum per ADM2 region ===\n")
agg_list <- lapply(gpw_years, function(yr) {
  r <- rasters[[as.character(yr)]]
  if (is.null(r)) return(NULL)
  cat(sprintf("  Zonal sum for %d...\n", yr))
  z <- terra::zonal(r, gadm_v, fun = "sum", na.rm = TRUE)
  dt <- data.table::as.data.table(z)
  data.table::setnames(dt, names(dt), c("pop_count"))
  dt[, GID_2 := gadm_v$GID_2]
  dt[, GID_0 := gadm_v$GID_0]
  dt[, year  := yr]
  dt
})
agg <- data.table::rbindlist(agg_list[!sapply(agg_list, is.null)])
agg[pop_count < 0, pop_count := 0]
cat(sprintf("Aggregated: %d rows | %d regions | %d countries\n",
    nrow(agg), uniqueN(agg$GID_2), uniqueN(agg$GID_0)))

cat("\n=== Step 4: Interpolate/extrapolate to 1993-2013 ===\n")
target_years <- 1993L:2013L

interp_col <- function(yrs, vals, target) {
  ok <- !is.na(vals) & vals >= 0
  if (sum(ok) >= 2) stats::approx(yrs[ok], vals[ok], xout = target, rule = 2)$y
  else if (sum(ok) == 1) rep(vals[ok], length(target))
  else rep(NA_real_, length(target))
}

panel <- agg[, {
  .(year      = target_years,
    pop_count = interp_col(year, pop_count, target_years),
    GID_0     = GID_0[1])
}, by = GID_2]

# lnpop = log(population in thousands)
panel[, lnpop := log(pmax(pop_count, 1) / 1000)]
cat(sprintf("Population panel: %d rows | %d regions | %d countries\n",
    nrow(panel), uniqueN(panel$GID_2), uniqueN(panel$GID_0)))

cat("\n=== Step 5: Save ===\n")
data.table::fwrite(panel[, .(GID_2, GID_0, year, pop_count, lnpop)],
                   "data/processed/population_adm2.csv")
cat("Saved: data/processed/population_adm2.csv\n")
cat(sprintf("Sample lnpop range: %.2f to %.2f\n",
    min(panel$lnpop, na.rm=TRUE), max(panel$lnpop, na.rm=TRUE)))
