# 07_regression/table4/02_col4_7_grid.R
# HR 2014 Table IV Col(4)-(7): "Geographic Extent" robustness check using
# global rectangular grid cells (50/100/200/400 km) instead of GADM ADM1/
# ADM2 administrative units as the spatial unit of observation.
#
# Same is_birthregion logic as Table II Col(1), just applied at the grid
# level: for each country-year with a leader in power, the grid cell whose
# polygon contains the leader's birthplace coordinates (PLAD lat/lon) is
# flagged is_birthregion_grid = TRUE; all other grid cells in that country
# are the control group. Spec:
#   ln_ntl ~ l(is_birthregion_grid) | grid_id + gid_0^year, vcov = ~spell_cluster
# run separately per resolution (Col(4)=50km, Col(5)=100km, Col(6)=200km,
# Col(7)=400km), matching HR 2014's own robustness table structure (p. 1018:
# "We create grids of same-sized, rectangular cells ... at four different
# resolutions").
#
# Data sources:
#   - Grid-cell DMSP NTL panels: data/processed/ntl/dmsp_grid<res>km_panel.csv
#     (built locally via 04_extraction/04_dmsp_grid_cells.R + exactextractr, not GEE)
#   - Grid-cell polygons (for the birthplace point-in-polygon join):
#     data/processed/grid_cells_<res>km.gpkg
#   - Leader birthplace coordinates + spell dates: PLAD (data/raw/plad/PLAD_April_2024.tab)
#   - Leader-spell clusters for SE clustering: Archigos 4.1
#
# Each resolution is run twice: (a) our full PLAD/GADM country universe
# (174 countries), and (b) restricted to HR 2014's original 126-country
# sample (data/raw/plad/hr2014_126_countries.csv, transcribed from the
# paper's own Supplementary Material, p.1 "List of countries") -- our
# broader sample has more countries/spell clusters than HR's, which by
# itself changes standard errors and coefficient composition (see
# RESEARCH_JOURNAL.md Section on Table II: DHR 147 vs HR 126 countries),
# so the restricted-sample column isolates that effect from genuine
# grid-resolution robustness.

library(data.table)
library(sf)
library(fixest)
library(haven)
library(countrycode)

years_rep <- 1992:2009
RESOLUTIONS <- c(50L, 100L, 200L, 400L)

# --------------------------------------------------
# 1. PLAD -> country-year -> leader birth coordinates
# --------------------------------------------------
cat("=== Load PLAD, expand to country-year birth coordinates ===\n")
plad <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(latitude) & !is.na(longitude) & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]

plad_yr <- plad[, {
  yr_seq <- seq(max(startyear, min(years_rep)), min(endyear, max(years_rep)))
  if (length(yr_seq) == 0) yr_seq <- integer(0)
  .(year = yr_seq, gid_0 = gid_0, latitude = latitude, longitude = longitude)
}, by = .(leader, plad_id)]
plad_yr <- plad_yr[year %between% range(years_rep)]
data.table::setorder(plad_yr, gid_0, year)
plad_yr <- unique(plad_yr, by = c("gid_0", "year"))
cat(sprintf("PLAD country-years with a birthplace-located leader: %d (%d countries)\n",
    nrow(plad_yr), uniqueN(plad_yr$gid_0)))

# Supplement PLAD gaps with Wikidata-geocoded coordinates for the leaders it
# has no birthplace for (see RESEARCH_JOURNAL.md, "PLAD coverage gap"
# section, 2026-08-17). Point-in-country validity is enforced downstream by
# the existing `join_dt[gid_0 == GID_0]` filter (line ~121), so it's safe to
# include all resolved coordinates here, not just the pre-validated subset
# -- any wrong-country geocode (e.g. a leader genuinely born abroad) simply
# fails that filter and contributes no birth cell, same as PLAD entries would.
wd_coords <- data.table::fread("data/processed/wikidata_supplement_coords.csv")
wd_coords_yr <- wd_coords[, {
  yr_seq <- seq(max(startyear, min(years_rep)), min(endyear, max(years_rep)))
  if (length(yr_seq) == 0) yr_seq <- integer(0)
  .(year = yr_seq, gid_0 = iso3, latitude = lat, longitude = lon)
}, by = .(leader, iso3, startyear, endyear)]
wd_coords_yr <- wd_coords_yr[year %between% range(years_rep)]
wd_coords_yr <- wd_coords_yr[!plad_yr, on = .(gid_0, year)]
data.table::setorder(wd_coords_yr, gid_0, year)
wd_coords_yr <- unique(wd_coords_yr, by = c("gid_0", "year"))
cat(sprintf("Wikidata supplement: %d additional country-years | %d countries\n",
    nrow(wd_coords_yr), uniqueN(wd_coords_yr$gid_0)))

plad_yr <- rbind(plad_yr[, .(leader, gid_0, year, latitude, longitude)],
                  wd_coords_yr[, .(leader, gid_0, year, latitude, longitude)])
cat(sprintf("Combined (PLAD + Wikidata supplement): %d country-years | %d countries\n",
    nrow(plad_yr), uniqueN(plad_yr$gid_0)))

birth_pts <- sf::st_as_sf(plad_yr, coords = c("longitude", "latitude"), crs = 4326)

cat("\n=== Load HR 2014's original 126-country sample ===\n")
hr126 <- data.table::fread("data/raw/plad/hr2014_126_countries.csv")
hr126_iso3 <- unique(hr126$iso3)
cat(sprintf("HR 2014 sample: %d countries\n", length(hr126_iso3)))

# --------------------------------------------------
# 2. Archigos leader-spell clusters (same construction as R/17)
# --------------------------------------------------
cat("\n=== Build Archigos leader-spell clusters ===\n")
arch <- data.table::as.data.table(haven::read_dta("data/raw/archigos/Archigos_4.1.dta"))
arch[, startyear := as.integer(substr(startdate, 1, 4))]
arch[, endyear   := as.integer(substr(enddate,   1, 4))]
arch <- arch[!is.na(startyear) & !is.na(endyear)]
arch[, iso3 := suppressWarnings(countrycode::countrycode(ccode, "cown", "iso3c",
  custom_match = c("260" = "DEU", "340" = "SRB", "345" = "SRB", "678" = "YEM")))]
arch <- arch[!is.na(iso3)]

arch_yr <- arch[, {
  lo <- max(startyear, min(years_rep))
  hi <- min(endyear, max(years_rep))
  yrs <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yrs, iso3 = iso3)
}, by = .(obsid)]
arch_yr <- arch_yr[year %between% range(years_rep)]
data.table::setorder(arch_yr, iso3, year, obsid)
arch_yr <- unique(arch_yr, by = c("iso3", "year"))
data.table::setorder(arch_yr, iso3, year)
arch_yr[, spell_cluster := data.table::shift(obsid, 1L), by = iso3]
arch_yr[is.na(spell_cluster), spell_cluster := obsid]

# --------------------------------------------------
# 3. Per-resolution: point-in-polygon join, merge onto grid NTL panel, regress
# --------------------------------------------------
run_grid_regression <- function(res, restrict_iso3 = NULL, exclude_above65n = FALSE) {
  gpkg_path <- sprintf("data/processed/grid_cells_%dkm.gpkg", res)
  panel_path <- sprintf("data/processed/ntl/dmsp_grid%dkm_panel.csv", res)
  if (!file.exists(gpkg_path) || !file.exists(panel_path)) {
    cat(sprintf("  MISSING input file(s) for %d km -- skipping\n", res))
    return(NULL)
  }

  sf::sf_use_s2(FALSE)
  grid_sf <- sf::st_read(gpkg_path, quiet = TRUE)
  sf::st_geometry(grid_sf) <- "geometry"
  grid_sf <- grid_sf[, c("grid_id", "GID_0")]

  # HR 2014 exact-sample restriction test (2026-08-17): drop cells entirely
  # above 65N latitude, matching HR's own exclusion criterion (p. 1001).
  # Grid geometry is in an equal-area projected CRS (ESRI:54034), so
  # transform to WGS84 first to test latitude.
  if (exclude_above65n) {
    grid_wgs84 <- sf::st_transform(grid_sf, 4326)
    ymin_vals <- vapply(sf::st_geometry(grid_wgs84), function(g) sf::st_bbox(g)["ymin"], numeric(1))
    keep_ids <- grid_sf$grid_id[ymin_vals <= 65]
    n_before <- nrow(grid_sf)
    grid_sf <- grid_sf[grid_sf$grid_id %in% keep_ids, ]
    cat(sprintf("  Dropped %d/%d cells entirely above 65N\n", n_before - nrow(grid_sf), n_before))
  }

  birth_pts_use <- birth_pts
  if (!is.null(restrict_iso3)) {
    birth_pts_use <- birth_pts_use[birth_pts_use$gid_0 %in% restrict_iso3, ]
    grid_sf <- grid_sf[grid_sf$GID_0 %in% restrict_iso3, ]
  }

  # Point-in-polygon: which grid cell contains each country-year's birthplace?
  # Restrict candidate cells to the leader's own country first (cheaper, and
  # avoids any cross-border ambiguity for birthplaces near a border).
  join <- sf::st_join(birth_pts_use, grid_sf, join = sf::st_within)
  join_dt <- data.table::as.data.table(sf::st_drop_geometry(join))
  join_dt <- join_dt[gid_0 == GID_0]  # keep only matches within the leader's own country
  join_dt <- unique(join_dt[, .(gid_0, year, birth_grid_id = grid_id)], by = c("gid_0", "year"))
  cat(sprintf("  Birth-cell matched: %d country-years\n", nrow(join_dt)))

  gpanel <- data.table::fread(panel_path)
  gpanel <- gpanel[year %between% range(years_rep)]
  data.table::setnames(gpanel, "iso3", "gid_0")
  if (!is.null(restrict_iso3)) gpanel <- gpanel[gid_0 %in% restrict_iso3]
  if (exclude_above65n) gpanel <- gpanel[grid_id %in% grid_sf$grid_id]

  gpanel <- merge(gpanel, join_dt, by = c("gid_0", "year"), all.x = TRUE)
  gpanel[, is_birthregion_grid := !is.na(birth_grid_id) & grid_id == birth_grid_id]
  gpanel[, has_leader := !is.na(birth_grid_id)]

  # Restrict to the leader universe (country-years with an identified leader
  # birthplace), matching Col(1)-(3)'s has_leader == 1 restriction.
  gpanel <- gpanel[has_leader == TRUE]
  cat(sprintf("  Grid panel (leader-country-years only): %d rows | %d cells | %d countries\n",
      nrow(gpanel), uniqueN(gpanel$grid_id), uniqueN(gpanel$gid_0)))
  cat(sprintf("  is_birthregion_grid = TRUE: %d cell-years\n", gpanel[is_birthregion_grid == TRUE, .N]))

  if (uniqueN(gpanel$gid_0) < 2 || nrow(gpanel) == 0) {
    cat("  Too few countries/rows -- skipping regression\n")
    return(NULL)
  }

  gpanel[, ln_ntl := log(pmax(dmsp_stable_lights, 0) + 0.01)]
  gpanel <- merge(gpanel, arch_yr[, .(gid_0 = iso3, year, spell_cluster)], by = c("gid_0", "year"), all.x = TRUE)
  gpanel[is.na(spell_cluster), spell_cluster := gid_0]

  data.table::setorder(gpanel, grid_id, year)
  d_fe <- fixest::panel(gpanel[is.finite(ln_ntl)], ~grid_id + year)
  fixest::feols(
    ln_ntl ~ fixest::l(is_birthregion_grid) | grid_id + gid_0^year,
    data = d_fe, vcov = ~spell_cluster
  )
}

models_full <- list()
models_hr126 <- list()
models_hrexact <- list()
col_labels <- c(`50` = "50km grid", `100` = "100km grid",
                 `200` = "200km grid", `400` = "400km grid")

# HR 2014 exact-sample restriction test (2026-08-17): drop countries with
# avg population < 500,000, in addition to the above-65N cell exclusion
# applied inside run_grid_regression().
hr_small <- data.table::fread("data/processed/hr_excluded_small_countries.csv")
hrexact_iso3 <- setdiff(unique(birth_pts$gid_0), hr_small$iso3)

for (res in RESOLUTIONS) {
  cat(sprintf("\n=== %d km grid -- full sample (174 countries) ===\n", res))
  m_full <- run_grid_regression(res, restrict_iso3 = NULL)
  if (!is.null(m_full)) models_full[[as.character(res)]] <- m_full

  cat(sprintf("\n=== %d km grid -- HR 2014 126-country sample ===\n", res))
  m_hr <- run_grid_regression(res, restrict_iso3 = hr126_iso3)
  if (!is.null(m_hr)) models_hr126[[as.character(res)]] <- m_hr

  cat(sprintf("\n=== %d km grid -- HR 2014 exact-sample (pop<500k + above-65N excluded) ===\n", res))
  m_hrexact <- run_grid_regression(res, restrict_iso3 = hrexact_iso3, exclude_above65n = TRUE)
  if (!is.null(m_hrexact)) models_hrexact[[as.character(res)]] <- m_hrexact
}

# --------------------------------------------------
# 4. Report
# --------------------------------------------------
cat("\n=== TABLE IV Col(4)-(7): Grid-Cell Geographic Extent Robustness ===\n")
cat("\n--- Full sample (174 countries) ---\n")
fixest::etable(models_full,
  digits  = 3,
  headers = paste0("(", 4:(3 + length(models_full)), ") ", col_labels[names(models_full)], " -- full")
)

cat("\n--- HR 2014 126-country sample ---\n")
fixest::etable(models_hr126,
  digits  = 3,
  headers = paste0("(", 4:(3 + length(models_hr126)), ") ", col_labels[names(models_hr126)], " -- HR126")
)

cat("\n--- HR 2014 exact-sample (pop<500k + above-65N excluded) ---\n")
fixest::etable(models_hrexact,
  digits  = 3,
  headers = paste0("(", 4:(3 + length(models_hrexact)), ") ", col_labels[names(models_hrexact)], " -- HRexact")
)

out_dir <- "data/processed/ntl"
saveRDS(list(full = models_full, hr126 = models_hr126, hrexact = models_hrexact),
        file.path(out_dir, "table4_col4_7_grid_models_hrsample.rds"))
cat(sprintf("\nModels saved: %s\n", file.path(out_dir, "table4_col4_7_grid_models.rds")))
