# R/06_gecon_regional_gdp.R
# Purpose: Build ADM2-level regional GDP panel from G-Econ 4.0 data.
# G-Econ: 1-degree grid cells, PPP GDP in 1990/1995/2000/2005.
# Method: Point-in-polygon join of grid centroids to GADM 4.1 ADM2,
#         population-weighted aggregation, linear interpolation 1992-2009.
# Output: data/processed/regional_gdp_panel.csv

library(sf)
library(data.table)
library(readxl)
sf::sf_use_s2(FALSE)

cat("=== Step 1: Load G-Econ data ===\n")
g <- data.table::as.data.table(
  readxl::read_xls("data/raw/gecon/Gecon40_post_final.xls")
)
g <- g[!is.na(LAT) & !is.na(LONGITUDE)]

# PPP GDP (billions USD) and population (thousands) for 4 time points
gdp_years  <- c(1990L, 1995L, 2000L, 2005L)
gdp_cols   <- paste0("PPP",  gdp_years, "_40")
pop_cols   <- paste0("POPGPW_", gdp_years, "_40")

# Keep only rows with at least one GDP observation
g <- g[rowSums(!is.na(g[, ..gdp_cols])) > 0]
cat(sprintf("G-Econ cells with GDP: %d | countries: %d\n",
    nrow(g), uniqueN(g$COUNTRY)))

cat("\n=== Step 2: Load GADM 3.6 ADM2 polygons (matches DHR GID_2 format) ===\n")
sf36 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
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
  # GDP per capita: GDP in billions USD / population in thousands = millions USD per person
  tmp[, gdppc      := gdp_total / pop_total]
  tmp[, ln_rgdppc  := log(gdppc)]
  # Population in thousands -> log(thousands)
  tmp[, lnpop      := log(pop_total)]
  tmp[, c("gdp_total", "pop_total", "gdppc") := NULL]
  tmp
})
agg <- data.table::rbindlist(agg_list)
cat(sprintf("ADM2 GDP panel (4 years): %d rows | %d regions | %d countries\n",
    nrow(agg), uniqueN(agg$GID_2), uniqueN(agg$GID_0)))

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
    nrow(panel_list), uniqueN(panel_list$GID_2), uniqueN(panel_list$GID_0)))

cat("\n=== Step 6: Save ===\n")
data.table::fwrite(panel_list, "data/processed/regional_gdp_panel.csv")
cat("Saved: data/processed/regional_gdp_panel.csv\n")
cat(sprintf("Coverage: %d ADM2 regions in %d countries\n",
    uniqueN(panel_list$GID_2), uniqueN(panel_list$GID_0)))
