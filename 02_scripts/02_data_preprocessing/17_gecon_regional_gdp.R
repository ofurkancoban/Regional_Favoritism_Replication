# ==============================================================================
# File:          17_gecon_regional_gdp.R
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
# Description:   Aggregates G-Econ 4.0 (Nordhaus et al.) gridded regional GDP to ADM2, substituting for the authors' unreleased Gennaioli et al. (2014) source in Table II Column (8).
#
# Inputs:        01_datasets/raw/gecon/
# Outputs:       01_datasets/processed/gecon_regional_gdp.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

sf::sf_use_s2(FALSE)

cat("=== Step 1: Load G-Econ data ===\n")
g <- data.table::as.data.table(
  readxl::read_xls(here::here("01_datasets/raw/gecon/Gecon40_post_final.xls"))
)
g <- g[!is.na(LAT) & !is.na(LONGITUDE)]

# PPP GDP (billions USD) and population (thousands) for 4 time points
gdp_years  <- c(1990L, 1995L, 2000L, 2005L)
gdp_cols   <- paste0("PPP",  gdp_years, "_40")
pop_cols   <- paste0("POPGPW_", gdp_years, "_40")

# Keep only rows with at least one GDP observation
g <- g[rowSums(!is.na(g[, ..gdp_cols])) > 0]
cat(sprintf("G-Econ cells with GDP: %d | countries: %d\n",
    nrow(g), data.table::uniqueN(g$COUNTRY)))

cat("\n=== Step 2: Load GADM 3.6 ADM2 polygons (matches DHR GID_2 format) ===\n")
sf36 <- sf::st_read(here::here("01_datasets/raw/gadm_3.6/gadm36_levels.gpkg"), layer = "level2", quiet = TRUE)
sf36 <- sf::st_transform(sf36, 4326)
sf41 <- sf36[, c("GID_2", "GID_0")]
cat(sprintf("GADM 3.6 ADM2: %d regions\n", nrow(sf41)))

cat("\n=== Step 3: Spatial join grid centroids to ADM2 ===\n")
g_sf <- sf::st_as_sf(g, coords = c("LONGITUDE", "LAT"), crs = 4326)

joined <- sf::st_join(g_sf, sf41[, c("GID_2", "GID_0")], join = sf::st_within, left = FALSE)
joined_dt <- data.table::as.data.table(joined)
joined_dt[, geometry := NULL]

cat(sprintf("Grid cells matched to ADM2: %d / %d (%.1f%%)\n",
    nrow(joined_dt), nrow(g), 100 * nrow(joined_dt) / nrow(g)))

cat("\n=== Step 4: Aggregate to ADM2 (sum GDP and population per region) ===\n")
agg_list <- lapply(seq_along(gdp_years), function(i) {
  yr  <- gdp_years[i]
  gc  <- gdp_cols[i]
  pc  <- pop_cols[i]
  tmp <- joined_dt[!is.na(get(gc)) & !is.na(get(pc)) & get(pc) > 0,
                   .(gdp_total = sum(get(gc), na.rm = TRUE),
                     pop_total = sum(get(pc), na.rm = TRUE)),
                   by = .(GID_2, GID_0)]
  tmp[, year := yr]
  # GDP per capita in US dollars, matching HR's RegionalGDP_ict definition
  # ("Logarithm of regional GDP per capita in US dollars"). G-Econ's
  # PPP*_40 columns are in BILLIONS of USD (verified: summing PPP2005_40
  # over all US cells gives ~12,580, i.e. ~$12.58 trillion, matching actual
  # 2005 US GDP), while POPGPW_*_40 is RAW PERSON COUNT, not thousands as
  # a previous version of this script assumed (verified: summing
  # POPGPW_2005_40 over all US cells gives ~296.5 million, matching actual
  # 2005 US population directly). The prior `gdp_total / pop_total` without
  # the billions->dollars conversion produced gppc on the order of 1e-5
  # (billions of dollars per raw person), giving implausible ln_rgdppc
  # values in the -Inf to -7.7 range instead of realistic ~6-11. Fixed by
  # multiplying by 1e9 before taking logs. Confirmed 2026-08-17.
  tmp[, gdppc      := (gdp_total * 1e9) / pop_total]
  tmp[, ln_rgdppc  := log(gdppc)]
  # log(population in thousands), matching the convention used everywhere
  # else in this pipeline (05_covariates/02_gpw_population.R, 06_panel/
  # 01_build_analysis_panel.R) -- not currently read by any downstream
  # script, fixed for consistency only.
  tmp[, lnpop      := log(pop_total / 1000)]
  tmp[, c("gdp_total", "pop_total", "gdppc") := NULL]
  tmp
})
agg <- data.table::rbindlist(agg_list)
cat(sprintf("ADM2 GDP panel (4 years): %d rows | %d regions | %d countries\n",
    nrow(agg), data.table::uniqueN(agg$GID_2), data.table::uniqueN(agg$GID_0)))

cat("\n=== Step 5: Interpolate 1992-2009 ===\n")
# For each region, linearly interpolate between 1990/1995/2000/2005, extrapolate to 2009
target_years <- 1992L:2009L

data.table::setorder(agg, GID_2, year)
interp_col <- function(yrs, vals, target) {
  ok <- !is.na(vals)
  if (sum(ok) >= 2) stats::approx(yrs[ok], vals[ok], xout = target, rule = 2)$y
  else if (sum(ok) == 1) rep(vals[ok], length(target))
  else rep(NA_real_, length(target))
}

panel_list <- agg[, {
  .(year      = target_years,
    ln_rgdppc = interp_col(year, ln_rgdppc, target_years),
    lnpop     = interp_col(year, lnpop,     target_years),
    GID_0     = GID_0[1])
}, by = GID_2]

cat(sprintf("Interpolated panel: %d rows | %d regions | %d countries\n",
    nrow(panel_list), data.table::uniqueN(panel_list$GID_2), data.table::uniqueN(panel_list$GID_0)))

cat("\n=== Step 6: Save ===\n")
data.table::fwrite(panel_list, here::here("01_datasets/processed/regional_gdp_panel.csv"))
cat("Saved: data/processed/regional_gdp_panel.csv\n")
cat(sprintf("Coverage: %d ADM2 regions in %d countries\n",
    data.table::uniqueN(panel_list$GID_2), data.table::uniqueN(panel_list$GID_0)))
