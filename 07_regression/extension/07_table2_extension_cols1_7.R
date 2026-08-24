# 07_regression/extension/07_table2_extension_cols1_7.R
# Purpose: Extension test -- re-estimate HR 2014 Table II's Columns (1)-(7)
# (all except Col(8), the regional-GDP specification, which depends on
# G-Econ 4.0 and is not extended past the HR-window replication) over the
# full 1992-2023 harmonized DMSP/VIIRS panel, using our own independently
# built GHS-POP population source throughout.
#
# NTL:        harmonized_dmsp_viirs_adm2_panel.csv (Li et al. 2020 method)
# Birthregion: PLAD + Wikidata supplement, full country universe
# Population: own GHS-POP pipeline (05_covariates/07-10*.R), not DHR's
#             interim source -- see 01_full_range_lnpop.R's own header note
# Clustering: country-level (~gid_0), per the project's formal convention
#             for extension work past Archigos 4.1's 2015 coverage limit
# Window:     1992-2023

library(data.table)
library(fixest)

years_rep <- 1992:2023

cat("=== Load harmonized NTL panel ===\n")
ntl <- fread("data/processed/ntl/harmonized_dmsp_viirs_adm2_panel.csv")
ntl <- ntl[year %in% years_rep]
ntl_adm2 <- ntl[adm_level == "ADM2"]
ntl_adm1 <- ntl[adm_level == "ADM1" & !iso3 %in% ntl_adm2$iso3]
ntl <- rbind(ntl_adm2, ntl_adm1)
ntl[, gid_2 := region_id]
cat(sprintf("NTL: %d rows | %d regions | %d countries | years %d-%d\n",
    nrow(ntl), uniqueN(ntl$gid_2), uniqueN(ntl$iso3), min(ntl$year), max(ntl$year)))

cat("\n=== Expand PLAD (+ Wikidata supplement) to country-year, full 1992-2023 range ===\n")
plad <- fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]
plad <- plad[is.na(foreign_leader) | foreign_leader != 1]

plad_yr <- plad[, {
  lo <- max(startyear, min(years_rep))
  hi <- min(endyear, max(years_rep))
  yr_seq <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yr_seq, gid_0 = gid_0, birth_gid2 = gid_2)
}, by = .(leader, plad_id)]
plad_yr <- plad_yr[year %in% years_rep]
cat(sprintf("PLAD leader-year rows: %d | countries: %d | max year: %d\n",
    nrow(plad_yr), uniqueN(plad_yr$gid_0), max(plad_yr$year)))

cat("\n=== Build birthplace flags (t0, t-1 via fixest::l(), t-2) ===\n")
birth_ry <- unique(plad_yr[, .(gid_2 = birth_gid2, iso3 = gid_0, year)])
ntl[, is_birthregion := FALSE]
ntl[birth_ry, on = .(gid_2, iso3, year), is_birthregion := TRUE]
ntl[plad_yr, on = .(iso3 = gid_0, year), has_leader := 1L]
ntl[is.na(has_leader), has_leader := 0L]
ntl <- unique(ntl, by = c("gid_2", "year"))
ntl[, gid_0 := iso3]

setorder(ntl, gid_2, year)
ntl[, ln_ntl    := log(pmax(harmonized_ntl, 0) + 0.01)]
ntl[, ln_ntl_00 := fifelse(harmonized_ntl > 0, log(harmonized_ntl), NA_real_)]
ntl[, leader_t0 := is_birthregion]
ntl[, leader_t2 := data.table::shift(is_birthregion, 2L), by = gid_2]
ntl[, ln_ntl_lag := data.table::shift(ln_ntl, 1L), by = gid_2]

cat("\n=== Merge our own GHS-POP lnpop (VPS-computed, DHR-style interpolated) ===\n")
pop <- fread("data/processed/population_adm2_ghspop_interpolated.csv",
             select = c("GID_2", "year", "pop_count", "lnpop"))
setnames(pop, "GID_2", "gid_2")
pop <- pop[is.finite(lnpop)]
ntl <- merge(ntl, pop, by = c("gid_2", "year"), all.x = TRUE)
ntl[, ln_ntlpc := log(pmax(harmonized_ntl, 0) / pop_count + 0.01)]
cat(sprintf("Rows with non-missing lnpop: %d / %d (%.1f%%)\n",
    sum(!is.na(ntl$lnpop)), nrow(ntl), 100 * mean(!is.na(ntl$lnpop))))

d <- ntl[has_leader == 1]
cat(sprintf("Panel: %d obs | %d regions | %d countries | years %d-%d\n",
    nrow(d), uniqueN(d$gid_2), uniqueN(d$iso3), min(d$year), max(d$year)))

cat("\n=== Clustering: country-level (matching the extension convention) ===\n")
d[, country_cluster := gid_0]

cat("\n=== Col(1): Baseline -- Leader_t-1, region + country-year FE ===\n")
d_fe <- fixest::panel(d[!is.na(is_birthregion)], ~gid_2 + year)
m1 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
  data = d_fe, vcov = ~country_cluster
)

cat("=== Col(2): Contemporaneous Leader_t ===\n")
m2 <- fixest::feols(
  ln_ntl ~ leader_t0 | gid_2 + gid_0^year,
  data = d_fe, vcov = ~country_cluster
)

cat("=== Col(3): 2-period lag Leader_t-2 ===\n")
m3 <- fixest::feols(
  ln_ntl ~ leader_t2 | gid_2 + gid_0^year,
  data = d_fe, vcov = ~country_cluster
)

cat("=== Col(4): + lagged light (dynamic panel), no population control ===\n")
# Matches HR 2014's own Table II Col(4): Pop_ict is blank in that column
# (see table2/02_track2_own.R's own verification note on this).
d_fe4 <- fixest::panel(d[!is.na(is_birthregion) & !is.na(ln_ntl_lag)], ~gid_2 + year)
m4 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) + ln_ntl_lag | gid_2 + gid_0^year,
  data = d_fe4, vcov = ~country_cluster
)

cat("=== Col(5): OLS -- lagged light, NO region FE ===\n")
d_fe5 <- fixest::panel(d[!is.na(is_birthregion) & !is.na(ln_ntl_lag)], ~gid_2 + year)
m5 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) + ln_ntl_lag | gid_0^year,
  data = d_fe5, vcov = ~country_cluster
)

cat("=== Col(6): Extensive margin Light0 (drops zero-light obs) ===\n")
d_fe6 <- fixest::panel(d[!is.na(is_birthregion) & is.finite(ln_ntl_00)], ~gid_2 + year)
m6 <- fixest::feols(
  ln_ntl_00 ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
  data = d_fe6, vcov = ~country_cluster
)

cat("=== Col(7): Per capita light + population control ===\n")
d_fe7 <- fixest::panel(d[!is.na(is_birthregion) & is.finite(ln_ntlpc) & !is.na(lnpop)], ~gid_2 + year)
m7 <- fixest::feols(
  ln_ntlpc ~ fixest::l(is_birthregion) + lnpop | gid_2 + gid_0^year,
  data = d_fe7, vcov = ~country_cluster
)

cat("\n=== EXTENSION -- TABLE II, COLUMNS (1)-(7), FULL 1992-2023 WINDOW ===\n")
fixest::etable(m1, m2, m3, m4, m5, m6, m7,
  digits  = 3,
  keep    = c("is_birthregion", "leader_t0", "leader_t2", "ln_ntl_lag", "lnpop"),
  headers = c("(1) Light", "(2) Light", "(3) Light", "(4) Light",
              "(5) Light", "(6) Light0", "(7) Lightpc")
)

saveRDS(list(m1 = m1, m2 = m2, m3 = m3, m4 = m4, m5 = m5, m6 = m6, m7 = m7),
        "data/processed/ntl/extension_table2_cols1_7_models.rds")
cat("\nSaved: data/processed/ntl/extension_table2_cols1_7_models.rds\n")

cat("\n=== Region-only-baseline within R2 (matching the deck's own convention) ===\n")
# fixest's own default within-R2 (demeaning by both region AND
# country-year FE) reports near-zero for these single-dummy specs, same
# issue already documented for the HR-window Table II/IV slides. Convention
# used throughout this deck: 1 - RSS(full model) / TSS(region-FE-only null),
# i.e. how much of the region-demeaned variance the full model explains.
# Column (5) has no region FE, so its own reported R2 (full model R2) is
# used instead, matching the existing convention.
region_only_r2 <- function(dd, yvar, region_var = "gid_2") {
  f <- as.formula(sprintf("%s ~ 1 | %s", yvar, region_var))
  null_m <- fixest::feols(f, data = dd)
  1 - deviance(null_m)
}

wr2 <- function(m, dd, yvar) {
  null_dev <- {
    f <- as.formula(sprintf("%s ~ 1 | gid_2", yvar))
    deviance(fixest::feols(f, data = dd))
  }
  1 - deviance(m) / null_dev
}

cat(sprintf("Col(1) within R2: %.3f\n", wr2(m1, d_fe[!is.na(is_birthregion)], "ln_ntl")))
cat(sprintf("Col(2) within R2: %.3f\n", wr2(m2, d_fe[!is.na(is_birthregion)], "ln_ntl")))
cat(sprintf("Col(3) within R2: %.3f\n", wr2(m3, d_fe[!is.na(is_birthregion) & !is.na(leader_t2)], "ln_ntl")))
cat(sprintf("Col(4) within R2: %.3f\n", wr2(m4, d_fe4[!is.na(is_birthregion) & !is.na(ln_ntl_lag)], "ln_ntl")))
cat(sprintf("Col(5) full R2 (no region FE): %.3f\n", fixest::r2(m5, "r2")))
cat(sprintf("Col(6) within R2: %.3f\n", wr2(m6, d_fe6[!is.na(is_birthregion) & is.finite(ln_ntl_00)], "ln_ntl_00")))
cat(sprintf("Col(7) within R2: %.3f\n", wr2(m7, d_fe7[!is.na(is_birthregion) & is.finite(ln_ntlpc) & !is.na(lnpop)], "ln_ntlpc")))

cat("\n=== Region counts per column ===\n")
cat(sprintf("Col(1) regions: %d\n", fixest::fixef(m1)$gid_2 |> length()))
cat(sprintf("Col(2) regions: %d\n", fixest::fixef(m2)$gid_2 |> length()))
cat(sprintf("Col(3) regions: %d\n", fixest::fixef(m3)$gid_2 |> length()))
cat(sprintf("Col(4) regions: %d\n", fixest::fixef(m4)$gid_2 |> length()))
cat(sprintf("Col(6) regions: %d\n", fixest::fixef(m6)$gid_2 |> length()))
cat(sprintf("Col(7) regions: %d\n", fixest::fixef(m7)$gid_2 |> length()))
cat(sprintf("Col(5) regions (no region FE, distinct gid_2 in sample): %d\n", uniqueN(d_fe5[!is.na(is_birthregion) & !is.na(ln_ntl_lag)]$gid_2)))
