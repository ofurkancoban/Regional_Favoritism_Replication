# Purpose: Interpolate our own VPS-computed GHS-POP benchmark-year panel
# (data/processed/population_adm2_ghspop_vps.csv, years 1990/1995/.../2020)
# to annual values, matching DHR (2025/2026)'s own interpolation method
# exactly: for each pair of consecutive 5-year benchmarks, linear
# interpolation in levels (not logs), computed AFTER zonal summation to
# ADM2 (i.e. on the region-level population totals, not on the raw
# raster) -- see 01_literature/dataverse_files/code/dataprep/population.R,
# lines ~33-49 ("Interpolate population").
#
# Years past the last available benchmark (2020, since we did not download
# the 1985 or 2025 benchmarks DHR's own script uses) are flat-extrapolated
# (last observed value held constant) via `rule = 2`, matching the
# convention already used in 02_gpw_population.R for its own post-2010
# extrapolation years. This is a real limitation relative to DHR, who
# interpolate through 2024 using a genuine 2025 benchmark anchor -- our
# 2021-2023 values are NOT interpolated between two real data points, they
# are held flat at the 2020 level. Documented, not hidden.
#
# Output: data/processed/population_adm2_ghspop_interpolated.csv
#   Columns: GID_2, GID_0, year, pop_count, lnpop (same schema as
#   02_gpw_population.R / 06_dhr_population.R / population_adm2_ghspop_vps.csv)
library(data.table)

cat("=== Load VPS-computed GHS-POP benchmark panel ===\n")
bench <- fread("data/processed/population_adm2_ghspop_vps.csv")
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
    nrow(panel), uniqueN(panel$GID_2), uniqueN(panel$GID_0), min(panel$year), max(panel$year)))
n_extrap <- panel[year > max(bench_years), .N]
cat(sprintf("Flat-extrapolated rows (year > %d, held at %d level): %d\n",
    max(bench_years), max(bench_years), n_extrap))

fwrite(panel[, .(GID_2, GID_0, year, pop_count, lnpop)],
       "data/processed/population_adm2_ghspop_interpolated.csv")
cat("Saved: data/processed/population_adm2_ghspop_interpolated.csv\n")
