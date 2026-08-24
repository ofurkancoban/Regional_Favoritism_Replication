# Purpose: Repeat the ADM2-level spillover test
# (07_regression/extension/03_spillover_neighbors.R) on a fixed-size grid
# instead of GADM administrative units -- an independent robustness check
# that is immune to any MAUP-style critique of the ADM2 result itself
# (grid cells are uniform size, not drawn by any political/administrative
# process). If the same "birth cell + neighbor cell both significant"
# pattern shows up here too, that rules out "GADM's own irregular polygon
# shapes/sizes happen to correlate with the effect" as an explanation for
# the ADM2-level spillover finding.
#
# Resolution: 50km (HR 2014 Table IV Col(4) -- the finest grid resolution,
# and the only one where the birth-cell-only effect is itself strongly
# significant in this project's own results: 0.043*** (0.012), see
# RESEARCH_JOURNAL.md). Testing spillover at a resolution where the base
# effect is weak/insignificant (200km, 400km) wouldn't be informative.
#
# Data sources: same as 07_regression/table4/02_col4_7_grid.R (PLAD +
# Wikidata birth coordinates, dmsp_grid50km_panel.csv, grid_cells_50km.gpkg,
# Archigos leader-spell clusters).
library(data.table)
library(sf)
library(fixest)
library(haven)
library(countrycode)

years_rep <- 1992:2013
RES <- 50L

cat("=== Load PLAD + Wikidata birth coordinates, expand to country-year ===\n")
plad <- fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(latitude) & !is.na(longitude) & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]
plad_yr <- plad[, {
  yr_seq <- seq(max(startyear, min(years_rep)), min(endyear, max(years_rep)))
  if (length(yr_seq) == 0) yr_seq <- integer(0)
  .(year = yr_seq, gid_0 = gid_0, latitude = latitude, longitude = longitude)
}, by = .(leader, plad_id)]
plad_yr <- plad_yr[year %between% range(years_rep)]
setorder(plad_yr, gid_0, year)
plad_yr <- unique(plad_yr, by = c("gid_0", "year"))

wd_coords <- fread("data/processed/wikidata_supplement_coords.csv")
wd_coords_yr <- wd_coords[, {
  yr_seq <- seq(max(startyear, min(years_rep)), min(endyear, max(years_rep)))
  if (length(yr_seq) == 0) yr_seq <- integer(0)
  .(year = yr_seq, gid_0 = iso3, latitude = lat, longitude = lon)
}, by = .(leader, iso3, startyear, endyear)]
wd_coords_yr <- wd_coords_yr[year %between% range(years_rep)]
wd_coords_yr <- wd_coords_yr[!plad_yr, on = .(gid_0, year)]
setorder(wd_coords_yr, gid_0, year)
wd_coords_yr <- unique(wd_coords_yr, by = c("gid_0", "year"))

plad_yr <- rbind(plad_yr[, .(leader, gid_0, year, latitude, longitude)],
                  wd_coords_yr[, .(leader, gid_0, year, latitude, longitude)])
cat(sprintf("Combined (PLAD + Wikidata): %d country-years | %d countries\n",
    nrow(plad_yr), uniqueN(plad_yr$gid_0)))
birth_pts <- sf::st_as_sf(plad_yr, coords = c("longitude", "latitude"), crs = 4326)

cat("\n=== Load 50km grid, build adjacency (queen contiguity) ===\n")
sf::sf_use_s2(FALSE)
grid_sf <- sf::st_read(sprintf("data/processed/grid_cells_%dkm.gpkg", RES), quiet = TRUE)
sf::st_geometry(grid_sf) <- "geometry"
grid_sf <- grid_sf[, c("grid_id", "GID_0")]
cat(sprintf("Grid cells: %d\n", nrow(grid_sf)))

touch <- sf::st_touches(grid_sf)
adj <- data.table(grid_id = grid_sf$grid_id[rep(seq_len(nrow(grid_sf)), lengths(touch))],
                   neighbor_grid_id = grid_sf$grid_id[unlist(touch)])
cat(sprintf("Adjacency pairs: %d\n", nrow(adj)))

cat("\n=== Match birth coordinates to grid cell (within own country) ===\n")
join <- sf::st_join(birth_pts, grid_sf, join = sf::st_within)
join_dt <- as.data.table(sf::st_drop_geometry(join))
join_dt <- join_dt[gid_0 == GID_0]
join_dt <- unique(join_dt[, .(gid_0, year, birth_grid_id = grid_id)], by = c("gid_0", "year"))
cat(sprintf("Birth-cell matched: %d country-years\n", nrow(join_dt)))

cat("\n=== Flag neighbor-of-birth-cell per country-year ===\n")
neighbor_flags <- merge(join_dt, adj, by.x = "birth_grid_id", by.y = "grid_id", allow.cartesian = TRUE)
neighbor_flags <- unique(neighbor_flags[, .(grid_id = neighbor_grid_id, gid_0, year)])
neighbor_flags[, is_neighbor_of_birthcell := TRUE]
cat(sprintf("Neighbor-flagged cell-years: %d\n", nrow(neighbor_flags)))

cat("\n=== Load 50km grid DMSP panel, merge flags ===\n")
gpanel <- fread(sprintf("data/processed/ntl/dmsp_grid%dkm_panel.csv", RES))
gpanel <- gpanel[year %between% range(years_rep)]
setnames(gpanel, "iso3", "gid_0")

gpanel <- merge(gpanel, join_dt, by = c("gid_0", "year"), all.x = TRUE)
gpanel[, is_birthregion_grid := !is.na(birth_grid_id) & grid_id == birth_grid_id]
gpanel[, has_leader := !is.na(birth_grid_id)]
gpanel <- gpanel[has_leader == TRUE]

gpanel <- merge(gpanel, neighbor_flags[, .(grid_id, gid_0, year, is_neighbor_of_birthcell)],
                 by = c("grid_id", "gid_0", "year"), all.x = TRUE)
gpanel[is.na(is_neighbor_of_birthcell), is_neighbor_of_birthcell := FALSE]
gpanel[is_birthregion_grid == TRUE, is_neighbor_of_birthcell := FALSE]

cat(sprintf("Grid panel: %d rows | %d cells | %d countries\n",
    nrow(gpanel), uniqueN(gpanel$grid_id), uniqueN(gpanel$gid_0)))
cat(sprintf("is_birthregion_grid TRUE: %d | is_neighbor_of_birthcell TRUE: %d\n",
    sum(gpanel$is_birthregion_grid), sum(gpanel$is_neighbor_of_birthcell)))

cat("\n=== Build Archigos leader-spell clusters ===\n")
arch <- as.data.table(haven::read_dta("data/raw/archigos/Archigos_4.1.dta"))
arch[, startyear := as.integer(substr(startdate, 1, 4))]
arch[, endyear   := as.integer(substr(enddate,   1, 4))]
arch <- arch[!is.na(startyear) & !is.na(endyear)]
arch[, iso3 := suppressWarnings(countrycode::countrycode(ccode, "cown", "iso3c",
  custom_match = c("260" = "DEU", "340" = "SRB", "345" = "SRB", "678" = "YEM")))]
arch <- arch[!is.na(iso3)]
arch_yr <- arch[, {
  lo <- max(startyear, min(years_rep)); hi <- min(endyear, max(years_rep))
  yrs <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yrs, iso3 = iso3)
}, by = .(obsid)]
arch_yr <- arch_yr[year %between% range(years_rep)]
setorder(arch_yr, iso3, year, obsid)
arch_yr <- unique(arch_yr, by = c("iso3", "year"))
setorder(arch_yr, iso3, year)
arch_yr[, spell_cluster := shift(obsid, 1L), by = iso3]
arch_yr[is.na(spell_cluster), spell_cluster := obsid]

gpanel <- merge(gpanel, arch_yr[, .(gid_0 = iso3, year, spell_cluster)], by = c("gid_0", "year"), all.x = TRUE)
gpanel[is.na(spell_cluster), spell_cluster := gid_0]

gpanel[, ln_ntl := log(pmax(dmsp_stable_lights, 0) + 0.01)]
setorder(gpanel, grid_id, year)

cat("\n=== Regressions: Leader_t-1, grid-cell + country-year FE, Archigos clustering ===\n")
d_fe <- fixest::panel(gpanel[is.finite(ln_ntl)], ~grid_id + year)

cat("Col(A): birth-cell only (baseline, HR Table IV Col(4) analog)\n")
mA <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion_grid) | grid_id + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

cat("Col(B): neighbor-cell only\n")
mB <- fixest::feols(ln_ntl ~ fixest::l(is_neighbor_of_birthcell) | grid_id + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

cat("Col(C): both together\n")
mC <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion_grid) + fixest::l(is_neighbor_of_birthcell) | grid_id + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

cat("\n=== Results (50km grid) ===\n")
fixest::etable(mA, mB, mC,
  digits  = 3,
  keep    = c("is_birthregion_grid", "is_neighbor_of_birthcell"),
  headers = c("(A) Birth cell", "(B) Neighbor cells", "(C) Both")
)

report <- function(m, label) {
  cn <- grep("is_birthregion_grid|is_neighbor_of_birthcell", names(coef(m)), value = TRUE)
  for (v in cn) {
    cf <- coef(m)[v]; se <- sqrt(diag(vcov(m)))[v]
    pv <- summary(m)$coeftable[v, 4]
    sig <- ifelse(pv<0.001,"***",ifelse(pv<0.01,"**",ifelse(pv<0.05,"*",ifelse(pv<0.1,".",""))))
    cat(sprintf("  %-20s %-30s %.3f%-3s (%.3f), N=%d\n", label, v, cf, sig, se, nobs(m)))
  }
}
cat("\n=== Summary ===\n")
report(mA, "Birth cell only:")
report(mB, "Neighbors only:")
report(mC, "Both together:")

saveRDS(list(mA = mA, mB = mB, mC = mC), "data/processed/ntl/spillover_grid50km_models.rds")
cat("\nSaved: data/processed/ntl/spillover_grid50km_models.rds\n")
