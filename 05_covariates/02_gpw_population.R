# 05_covariates/02_gpw_population.R
# Purpose: Build ADM2-level population panel using both GPWv3 and GPWv4
#          (CIESIN), so the panel has real observed anchors spanning the
#          full 1990-2010 range instead of flat-extrapolating a decade past
#          GPWv3's last vintage.
# Sources:
#   GPWv3 (CIESIN/CIAT) Population Count Grid, UN-adjusted, 2.5 arc-minute,
#     per-country ASCII archives from Harvard Dataverse (DOI
#     10.7927/H4639MPP) in data/raw/GPWv3_pcount/ -- years 1990, 1995.
#     (This is HR 2014 Appendix A's actual stated source: CIESIN data
#     "available for every fifth year from 1990 onward.")
#   GPWv4 (CIESIN) population density, rev 11, 5 arc-minute, global rasters
#     already downloaded via geodata::population() into
#     data/raw/gpw/population/pop/ -- years 2000, 2005, 2010. GPWv4 ships
#     density (persons/km^2), not counts, so each raster is converted to a
#     per-pixel count via cell area before zonal summing (same fix as the
#     original GPWv4-only version of this script).
# Anchors used for interpolation: 1990, 1995 (GPWv3) -> 2000, 2005, 2010
#   (GPWv4).
# Bridging: verification (2026-08-20) found a systematic level break at the
#   GPWv3/GPWv4 boundary in several countries -- e.g. Myanmar's implied
#   growth rate was +7.8%/yr for 1995-2000 then -2.2%/yr for 2000-2005, not
#   a real demographic reversal but an artifact of the two products
#   disagreeing on 2000's true level. Fix: compute a per-country bridge
#   factor (GPWv3's own 2000 total / GPWv4's 2000 total) and rescale
#   GPWv4's 2000/2005/2010 series by it, so the decade's growth SHAPE stays
#   GPWv4's own but its LEVEL connects smoothly to GPWv3's.
#   Capped to [0.85, 1.15]: verification also found that for some
#   countries (e.g. Bhutan, factor 2.65x) the large gap is not a mismatch
#   artifact but a genuine statistical correction -- Bhutan's 2005 census
#   revealed a true population of ~650K against the ~2M "official" estimate
#   older products like GPWv3 still carry, so bridging would overwrite
#   GPWv4's more accurate modern figure with GPWv3's outdated one. Outside
#   the cap, GPWv4's own value is left unscaled.
# Method:  Zonal sum of each country's own population raster over GADM 3.6
#          ADM2 polygons (exactextractr).
# Output:  data/processed/population_adm2.csv

library(data.table)
library(terra)
library(sf)
library(exactextractr)

gpw_dir <- "data/raw/GPWv3_pcount"
gpw_years <- c(90L, 95L)              # GPWv3 filename year codes (2000 comes from GPWv4 instead)
gpw_years_full <- c(1990L, 1995L)

gpw4_dir <- "data/raw/gpw/population/pop"
gpw4_years <- c(2000L, 2005L, 2010L)

cat("=== Step 1: Load GADM 3.6 ADM2 polygons ===\n")
sf::sf_use_s2(FALSE)
sf36 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
cat(sprintf("GADM 3.6 ADM2: %d regions, %d countries\n", nrow(sf36), data.table::uniqueN(sf36$GID_0)))

cat("\n=== Step 2: Map GADM GID_0 to GPWv3 country zip archives ===\n")
zip_files <- list.files(gpw_dir, pattern = "^download\\.jsp_file_gpwv3_level_country_.*_data_pcount_", full.names = TRUE)
zip_codes <- regmatches(zip_files, regexpr("(?<=country_code_)[A-Z]+", zip_files, perl = TRUE))
names(zip_files) <- zip_codes

# GPWv3 (released 2005) predates several GADM 3.6 country codes/splits. Known
# crosswalk cases where the modern GID_0 has no same-named GPWv3 archive but
# the historical archive's raster extent still spatially covers the modern
# country (since GPWv3's country mask reflects circa-2000 boundaries):
#   ROU (Romania)        -> ROM is GPWv3's own old ISO code for the same country
#   SRB (Serbia)          -> SCG "Serbia and Montenegro" (pre-2006 union) covers it
#   XKO (Kosovo)          -> SCG, since Kosovo was part of Serbia through GPWv3's 2000 vintage
#   SSD (South Sudan)     -> SDN, since South Sudan was part of Sudan through 2000
gid0_crosswalk <- c(ROU = "ROM", SRB = "SCG", XKO = "SCG", SSD = "SDN")

adm2_countries <- sort(unique(sf36$GID_0))
lookup_code <- ifelse(adm2_countries %in% names(gid0_crosswalk),
                       gid0_crosswalk[adm2_countries], adm2_countries)
has_zip <- lookup_code %in% zip_codes
cat(sprintf("ADM2 countries with a matching GPWv3 archive: %d / %d\n",
    sum(has_zip), length(adm2_countries)))
if (any(!has_zip)) cat("  No archive for:", paste(adm2_countries[!has_zip], collapse = ", "), "\n")

cat("\n=== Step 3: Zonal sum per country per year (UN-adjusted grid) ===\n")
tmp_dir <- file.path(tempdir(), "gpwv3_extract")
dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)

extract_country_year <- function(gid0, zip_code, yr_code) {
  zf <- zip_files[[zip_code]]
  entries <- utils::unzip(zf, list = TRUE)$Name
  target <- grep(sprintf("p%02dag\\.asc$", yr_code), entries, value = TRUE)
  if (length(target) == 0) return(NULL)
  utils::unzip(zf, files = target, exdir = tmp_dir, junkpaths = TRUE, overwrite = TRUE)
  fp <- file.path(tmp_dir, basename(target))
  r <- tryCatch(terra::rast(fp), error = function(e) NULL)
  if (is.null(r)) { unlink(fp); return(NULL) }
  terra::crs(r) <- "EPSG:4326"

  polys <- sf36[sf36$GID_0 == gid0, ]
  # terra::rast() reads lazily from disk, so the underlying file must still
  # exist when exact_extract() actually reads pixel values -- unlink only
  # after extraction completes, not right after creating the SpatRaster.
  pop_sum <- exactextractr::exact_extract(r, polys, fun = "sum", progress = FALSE)
  unlink(fp)
  data.table::data.table(GID_2 = polys$GID_2, GID_0 = gid0, pop_count = pop_sum)
}

agg_list <- list()
for (i in seq_along(adm2_countries)) {
  gid0 <- adm2_countries[i]
  if (!has_zip[i]) next
  zip_code <- lookup_code[i]
  for (j in seq_along(gpw_years)) {
    dt <- tryCatch(
      extract_country_year(gid0, zip_code, gpw_years[j]),
      error = function(e) { cat(sprintf("  %s %d FAILED: %s\n", gid0, gpw_years_full[j], conditionMessage(e))); NULL }
    )
    if (!is.null(dt)) {
      dt[, year := gpw_years_full[j]]
      agg_list[[length(agg_list) + 1]] <- dt
    }
  }
  if (i %% 20 == 0) cat(sprintf("  %d / %d countries done\n", i, length(adm2_countries)))
}
agg <- data.table::rbindlist(agg_list)
agg[pop_count < 0, pop_count := 0]
cat(sprintf("GPWv3 aggregated: %d rows | %d regions | %d countries\n",
    nrow(agg), data.table::uniqueN(agg$GID_2), data.table::uniqueN(agg$GID_0)))

cat("\n=== Step 3a-bis: GPWv3's own 2000 value, country totals, for bridging ===\n")
# Country-level only (not a panel anchor itself) -- just used to compute
# each country's GPWv3-vs-GPWv4 bridge factor below.
gpw3_2000_country <- list()
for (i in seq_along(adm2_countries)) {
  gid0 <- adm2_countries[i]
  if (!has_zip[i]) next
  zip_code <- lookup_code[i]
  dt <- tryCatch(extract_country_year(gid0, zip_code, 0L), error = function(e) NULL)
  if (!is.null(dt)) gpw3_2000_country[[gid0]] <- sum(dt$pop_count)
}
gpw3_2000_dt <- data.table::data.table(
  GID_0 = names(gpw3_2000_country),
  gpw3_2000 = unlist(gpw3_2000_country)
)
cat(sprintf("GPWv3 2000 country totals: %d countries\n", nrow(gpw3_2000_dt)))

cat("\n=== Step 3b: Zonal sum per year, GPWv4 density -> count ===\n")
gpw4_agg_list <- lapply(gpw4_years, function(yr) {
  cat(sprintf("  GPWv4 %d...\n", yr))
  fp <- file.path(gpw4_dir, sprintf("gpw_v4_population_density_rev11_%d_5m.tif", yr))
  if (!file.exists(fp)) { cat(sprintf("  missing: %s\n", fp)); return(NULL) }
  r <- terra::rast(fp)
  # GPWv4 ships density (persons/km^2); multiply by each pixel's own cell
  # area to get a per-pixel count raster before zonal-summing (see header
  # note -- same fix documented in this script's original GPWv4-only
  # version, verified against known national totals at the time).
  cell_km2 <- terra::cellSize(r, unit = "km")
  r_count <- r * cell_km2
  pop_sum <- exactextractr::exact_extract(r_count, sf36, fun = "sum", progress = FALSE)
  data.table::data.table(GID_2 = sf36$GID_2, GID_0 = sf36$GID_0, pop_count = pop_sum, year = yr)
})
gpw4_agg <- data.table::rbindlist(gpw4_agg_list[!sapply(gpw4_agg_list, is.null)])
gpw4_agg[pop_count < 0, pop_count := 0]
cat(sprintf("GPWv4 aggregated: %d rows | %d regions\n",
    nrow(gpw4_agg), data.table::uniqueN(gpw4_agg$GID_2)))

cat("\n=== Step 3c: Bridge GPWv4 onto GPWv3's 2000 level per country (capped) ===\n")
gpw4_2000_country <- gpw4_agg[year == 2000, .(gpw4_2000 = sum(pop_count)), by = GID_0]
bridge <- merge(gpw3_2000_dt, gpw4_2000_country, by = "GID_0")
bridge[, scale := gpw3_2000 / gpw4_2000]
cat(sprintf("Bridge factors computed for %d countries (median=%.3f, range %.3f-%.3f)\n",
    nrow(bridge), stats::median(bridge$scale), min(bridge$scale), max(bridge$scale)))

gpw4_agg <- merge(gpw4_agg, bridge[, .(GID_0, scale)], by = "GID_0", all.x = TRUE)
gpw4_agg[is.na(scale), scale := 1]  # no GPWv3 2000 available for this country -- leave unscaled
n_extreme <- data.table::uniqueN(gpw4_agg[scale < 0.85 | scale > 1.15, GID_0])
gpw4_agg[scale < 0.85 | scale > 1.15, scale := 1]
cat(sprintf("Capped scale to 1 (left GPWv4 unscaled) for %d countries outside [0.85, 1.15]\n", n_extreme))
gpw4_agg[, pop_count := pop_count * scale]
gpw4_agg[, scale := NULL]

agg <- data.table::rbindlist(list(agg, gpw4_agg), use.names = TRUE)
cat(sprintf("Combined anchors: %d rows | years %s\n",
    nrow(agg), paste(sort(unique(agg$year)), collapse = ", ")))

cat("\n=== Step 4: Interpolate/extrapolate to 1992-2013 ===\n")
# Anchors are now 1990, 1995 (GPWv3) and 2000, 2005, 2010 (GPWv4) -- five
# real observations spanning the full panel. 1992-2010 is genuine linear
# interpolation between real data; only 2011-2013 (3 years, vs. the
# previous 13) is flat extrapolation (rule = 2) past the last observation.
target_years <- 1992L:2013L

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
    nrow(panel), data.table::uniqueN(panel$GID_2), data.table::uniqueN(panel$GID_0)))

cat("\n=== Step 5: Save ===\n")
data.table::fwrite(panel[, .(GID_2, GID_0, year, pop_count, lnpop)],
                   "data/processed/population_adm2.csv")
cat("Saved: data/processed/population_adm2.csv\n")
cat(sprintf("Sample lnpop range: %.2f to %.2f\n",
    min(panel$lnpop, na.rm = TRUE), max(panel$lnpop, na.rm = TRUE)))

unlink(tmp_dir, recursive = TRUE)
