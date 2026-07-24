# ==============================================================================
# File:          20_ghspop_interpolate.R
# Project:       Regional Favoritism: A Replication and Extension of
#                Hodler & Raschky (2014)
# Author:        Ömer Furkan Çoban
#
# University:    Carl von Ossietzky University of Oldenburg
# Department:    Applied Economics and Data Science
# Course:        Applied Econometrics Using GIS Techniques
# Semester:      SoSe 2026
# Lecturer:      Prof. Dr. Erkan Gören
#
# Category:      Data Preprocessing
#
# Description:   Linearly interpolates the 5-year GHS-POP benchmarks to an annual region-year population series for the extension window.
#
# Inputs:        01_datasets/processed/population_adm2_ghspop_vps.csv
# Outputs:       01_datasets/processed/population_adm2_ghspop_interpolated.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

cat("=== Load VPS-computed GHS-POP benchmark panel ===\n")
bench <- data.table::fread(here::here("01_datasets/processed/population_adm2_ghspop_vps.csv"))
bench_years <- sort(unique(bench$year))
cat(sprintf("Benchmark years: %s\n", paste(bench_years, collapse = ", ")))

target_years <- 1990:2023

interp_col <- function(yrs, vals, target) {
  ok <- !is.na(vals) & vals >= 0
  if (sum(ok) >= 2) stats::approx(yrs[ok], vals[ok], xout = target, rule = 2)$y
  else if (sum(ok) == 1) rep(as.numeric(vals[ok]), length(target))
  else rep(NA_real_, length(target))
}

cat("\n=== Linear interpolation between benchmarks (DHR's method), flat-extrapolate past 2020 ===\n")
panel <- bench[, {
  .(year      = target_years,
    pop_count = interp_col(year, pop_count, target_years),
    GID_0     = GID_0[1])
}, by = GID_2]

panel[, pop_count := round(pop_count)]
panel[, lnpop := log(pmax(pop_count, 1) / 1000)]

cat(sprintf("Interpolated panel: %d rows | %d regions | %d countries | years %d-%d\n",
    nrow(panel), data.table::uniqueN(panel$GID_2), data.table::uniqueN(panel$GID_0), min(panel$year), max(panel$year)))
n_extrap <- panel[year > max(bench_years), .N]
cat(sprintf("Flat-extrapolated rows (year > %d, held at %d level): %d\n",
    max(bench_years), max(bench_years), n_extrap))

data.table::fwrite(panel[, .(GID_2, GID_0, year, pop_count, lnpop)],
       here::here("01_datasets/processed/population_adm2_ghspop_interpolated.csv"))
cat("Saved: data/processed/population_adm2_ghspop_interpolated.csv\n")
