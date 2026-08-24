# Purpose: Test whether HR 2014-style regional favoritism is a sharply
# targeted, point-specific effect (only the leader's literal birth region
# lights up) or spills into geographically adjacent regions -- a
# robustness/precision check on the birth-region measure itself, and a
# direct check on the modifiable-areal-unit-problem (MAUP) critique of
# using administrative units at all. Neither HR 2014 nor DHR (2025/2026)
# test this.
#
# Interpretation:
#   - If neighboring regions ALSO show a significant light increase, the
#     effect is geographically broader than the literal birth region --
#     the admin-unit boundary is measuring something coarser than the
#     true mechanism.
#   - If neighbors show NO effect while the birth region itself remains
#     significant, this is evidence the effect is sharply targeted --
#     strengthens confidence that HR 2014's birth-region measure is
#     capturing a real, specific mechanism rather than noise correlated
#     with broad geography.
#
# Data:
#   NTL/birth-region panel: data/processed/analysis_panel.csv (Track2, our
#     own DMSP extraction, 1993-2013 -- same source/window as
#     07_regression/table2/02_track2_own.R).
#   Adjacency: GADM 3.6 ADM2 polygons, queen contiguity (shares any
#     boundary point) via sf::st_touches().
#   Birth region per country-year: PLAD (same construction as
#     07_regression/extension/01_full_range_lnpop.R).
library(data.table)
library(fixest)
library(sf)
library(haven)
library(countrycode)

cat("=== Load our own DMSP analysis panel (Track2, 1993-2013) ===\n")
d <- fread("data/processed/analysis_panel.csv")
d <- d[year %between% c(1993L, 2013L)]
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    nrow(d), uniqueN(d$gid_2), uniqueN(d$iso3)))

cat("\n=== Build GADM 3.6 ADM2 adjacency (queen contiguity) ===\n")
sf::sf_use_s2(FALSE)
adm <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
adm <- adm[, c("GID_0", "GID_2")]
adm <- sf::st_make_valid(adm)
touch <- sf::st_touches(adm)
adj <- data.table(gid_2 = adm$GID_2[rep(seq_len(nrow(adm)), lengths(touch))],
                   neighbor_gid_2 = adm$GID_2[unlist(touch)])
cat(sprintf("Adjacency pairs: %d | regions with >=1 neighbor: %d / %d\n",
    nrow(adj), uniqueN(adj$gid_2), nrow(adm)))

years_rep <- 1993:2013

cat("\n=== Build birth-region per country-year directly from the panel's own is_birthregion ===\n")
# Re-deriving birth regions from raw PLAD (as an earlier version of this
# script did) undercounts by ~6% (191/3,062 country-years, checked
# 2026-08-21) versus what analysis_panel.csv actually uses, because
# 06_panel/01_build_analysis_panel.R supplements ~120 PLAD-missing
# leader-spells with Wikidata-geocoded birthplaces (see that script's
# "Step 2b"). Reading birth_gid2 straight off the panel's own
# is_birthregion flag guarantees the neighbor set is defined consistently
# with the variable it is meant to be a spillover of.
plad_yr <- unique(d[is_birthregion == TRUE, .(gid_0 = iso3, year, birth_gid2 = gid_2)])
cat(sprintf("Country-year birth-region rows: %d\n", nrow(plad_yr)))

cat("\n=== Flag neighbor-of-birth-region per country-year ===\n")
# For every (country, year, birth_gid2), look up that region's neighbors,
# then flag those neighbor regions (excluding the birth region itself) as
# treated in that country-year.
neighbor_flags <- merge(plad_yr, adj, by.x = "birth_gid2", by.y = "gid_2", allow.cartesian = TRUE)
neighbor_flags <- unique(neighbor_flags[, .(gid_2 = neighbor_gid_2, iso3 = gid_0, year)])
neighbor_flags[, is_neighbor_of_birthregion := TRUE]
cat(sprintf("Neighbor-flagged region-years: %d\n", nrow(neighbor_flags)))

d <- merge(d, neighbor_flags, by = c("gid_2", "iso3", "year"), all.x = TRUE)
d[is.na(is_neighbor_of_birthregion), is_neighbor_of_birthregion := FALSE]
# A region that IS the birth region should never also be counted as a
# "neighbor" even if some topological quirk made it touch itself.
d[is_birthregion == TRUE, is_neighbor_of_birthregion := FALSE]
cat(sprintf("is_birthregion TRUE: %d | is_neighbor_of_birthregion TRUE: %d (of %d obs)\n",
    sum(d$is_birthregion, na.rm = TRUE), sum(d$is_neighbor_of_birthregion), nrow(d)))

cat("\n=== Build Archigos leader-spell clusters (HR-window convention) ===\n")
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
arch_yr <- arch_yr[year %in% years_rep]
setorder(arch_yr, iso3, year, obsid)
arch_yr <- unique(arch_yr, by = c("iso3", "year"))
setorder(arch_yr, iso3, year)
arch_yr[, spell_cluster := shift(obsid, 1L), by = iso3]
arch_yr[is.na(spell_cluster), spell_cluster := obsid]

d <- merge(d, arch_yr[, .(iso3, year, spell_cluster)], by = c("iso3", "year"), all.x = TRUE)
d[is.na(spell_cluster), spell_cluster := iso3]

setorder(d, gid_2, year)

cat("\n=== Regressions: Leader_t-1, region + country-year FE, Archigos clustering ===\n")
d_fe <- fixest::panel(d[!is.na(is_birthregion) & !is.na(is_neighbor_of_birthregion)], ~gid_2 + year)

cat("Col(A): birth-region only (baseline)\n")
mA <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

cat("Col(B): neighbor-of-birth-region only\n")
mB <- fixest::feols(ln_ntl ~ fixest::l(is_neighbor_of_birthregion) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

cat("Col(C): both together\n")
mC <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) + fixest::l(is_neighbor_of_birthregion) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

cat("\n=== Results ===\n")
fixest::etable(mA, mB, mC,
  digits  = 3,
  keep    = c("is_birthregion", "is_neighbor_of_birthregion"),
  headers = c("(A) Birth region", "(B) Neighbors", "(C) Both")
)

report <- function(m, label) {
  cn <- grep("is_birthregion|is_neighbor_of_birthregion", names(coef(m)), value = TRUE)
  for (v in cn) {
    cf <- coef(m)[v]; se <- sqrt(diag(vcov(m)))[v]
    pv <- summary(m)$coeftable[v, 4]
    sig <- ifelse(pv<0.001,"***",ifelse(pv<0.01,"**",ifelse(pv<0.05,"*",ifelse(pv<0.1,".",""))))
    cat(sprintf("  %-20s %-30s %.3f%-3s (%.3f), N=%d\n", label, v, cf, sig, se, nobs(m)))
  }
}
cat("\n=== Summary ===\n")
report(mA, "Birth region only:")
report(mB, "Neighbors only:")
report(mC, "Both together:")

saveRDS(list(mA = mA, mB = mB, mC = mC), "data/processed/ntl/spillover_neighbors_models.rds")
cat("\nSaved: data/processed/ntl/spillover_neighbors_models.rds\n")
