# Purpose: Extension test -- harmonized DMSP/VIIRS panel (Li et al. 2020)
# over the full 1992-2023 range PLAD's leader data supports, with a
# population control (Table II Panel C analog: is_birthregion + lnpop).
#
# Population source: DHR (2025/2026)'s own already-processed lnpop
# (05_covariates/06_dhr_population.R output), used as an interim source
# while our own GHS-POP VPS pipeline runs in the background. DHR's gid_2
# scheme is a 100% subset of our GADM 3.6 level2 GID_2 (verified
# 2026-08-21), so this is a direct merge key, no crosswalk needed.
#
# Clustering: country-level (~gid_0), per the project's formal convention
# for any extension work past Archigos 4.1's 2015 coverage limit --
# matches DHR's own regressions.R (`vcov = ~gid_0` throughout).
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

cat("\n=== Expand PLAD to country-year, full 1992-2023 range ===\n")
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

cat("\n=== Build birthplace flag ===\n")
birth_ry <- unique(plad_yr[, .(gid_2 = birth_gid2, iso3 = gid_0, year)])
ntl[, is_birthregion := FALSE]
ntl[birth_ry, on = .(gid_2, iso3, year), is_birthregion := TRUE]
ntl[plad_yr, on = .(iso3 = gid_0, year), has_leader := 1L]
ntl[is.na(has_leader), has_leader := 0L]
ntl <- unique(ntl, by = c("gid_2", "year"))

setorder(ntl, gid_2, year)
ntl[, ln_ntl := log(pmax(harmonized_ntl, 0) + 0.01)]
ntl[, gid_0 := iso3]

cat("\n=== Merge our own GHS-POP lnpop (VPS-computed, DHR-style interpolated) ===\n")
# Superseded DHR's interim lnpop (05_covariates/06_dhr_population.R) now
# that our own independent GHS-POP pipeline is complete: VPS-computed
# benchmark years (05_covariates/07-09) verified to match DHR's own
# country totals exactly for 1990-2020 (ratio 1.000 across 5 spot-checked
# countries), then interpolated between benchmarks using DHR's own method
# (05_covariates/10_ghspop_interpolate.R). 2021-2023 are flat-extrapolated
# from 2020 (no 2025 benchmark downloaded), unlike DHR's real
# interpolation through 2024 -- a documented limitation, not hidden.
pop <- fread("data/processed/population_adm2_ghspop_interpolated.csv", select = c("GID_2", "year", "lnpop"))
setnames(pop, "GID_2", "gid_2")
pop <- pop[is.finite(lnpop)]
ntl <- merge(ntl, pop, by = c("gid_2", "year"), all.x = TRUE)
cat(sprintf("Rows with non-missing lnpop: %d / %d (%.1f%%)\n",
    sum(!is.na(ntl$lnpop)), nrow(ntl), 100 * mean(!is.na(ntl$lnpop))))

d <- ntl[has_leader == 1]
cat(sprintf("Panel: %d obs | %d regions | %d countries | years %d-%d\n",
    nrow(d), uniqueN(d$gid_2), uniqueN(d$iso3), min(d$year), max(d$year)))

cat("\n=== Clustering: country-level (matching DHR2026's own vcov = ~gid_0 convention) ===\n")
d[, country_cluster := gid_0]

cat("\n=== HR exact-sample restriction (126-country) ===\n")
hr126 <- fread("data/raw/plad/hr2014_126_countries.csv")
hr_65n <- fread("data/processed/hr_excluded_above65n_regions.csv")
d_hrex <- d[iso3 %in% hr126$iso3 & !gid_2 %in% hr_65n$gid_2]
cat(sprintf("HRexact panel: %d rows | %d regions | %d countries\n",
    nrow(d_hrex), uniqueN(d_hrex$gid_2), uniqueN(d_hrex$iso3)))

cat("\n=== Regressions: Table II Col(1) & Panel C (+ lnpop) analogs, full 1992-2023 range ===\n")
run_reg <- function(dd, label, with_pop = FALSE) {
  setorder(dd, gid_2, year)
  d_fe <- fixest::panel(dd[!is.na(is_birthregion)], ~gid_2 + year)
  rhs <- if (with_pop) "fixest::l(is_birthregion) + lnpop" else "fixest::l(is_birthregion)"
  m <- fixest::feols(as.formula(sprintf("ln_ntl ~ %s | gid_2 + gid_0^year", rhs)),
                      data = d_fe, vcov = ~country_cluster)
  cat(sprintf("\n%s: N=%d obs, %d regions\n", label, nobs(m), uniqueN(dd[!is.na(is_birthregion), gid_2])))
  print(fixest::etable(m, digits = 3))
  m
}

m_full_col1 <- run_reg(copy(d), "Col(1) [no lnpop], full sample (1992-2023)", with_pop = FALSE)
m_hrex_col1 <- run_reg(copy(d_hrex), "Col(1) [no lnpop], HRexact (1992-2023)", with_pop = FALSE)
m_full_panelC <- run_reg(copy(d[!is.na(lnpop)]), "Panel C [+lnpop], full sample (1992-2023)", with_pop = TRUE)
m_hrex_panelC <- run_reg(copy(d_hrex[!is.na(lnpop)]), "Panel C [+lnpop], HRexact (1992-2023)", with_pop = TRUE)

cat("\n=== Comparison ===\n")
cat("HR 2014 Table II Col(1) (1992-2009 window):  0.038*** (0.014), N=690,495 obs, 38,427 regions\n")
report <- function(m, dd, label) {
  cf <- coef(m)["fixest::l(is_birthregion)TRUE"]
  se <- sqrt(diag(vcov(m)))["fixest::l(is_birthregion)TRUE"]
  cat(sprintf("%-45s %.3f (%.3f), N=%d obs, %d regions\n",
      label, cf, se, nobs(m), uniqueN(dd[!is.na(is_birthregion), gid_2])))
}
report(m_full_col1, d, "Extended (1992-2023), full, no lnpop:")
report(m_hrex_col1, d_hrex, "Extended (1992-2023), HRexact, no lnpop:")
report(m_full_panelC, d[!is.na(lnpop)], "Extended (1992-2023), full, +lnpop:")
report(m_hrex_panelC, d_hrex[!is.na(lnpop)], "Extended (1992-2023), HRexact, +lnpop:")

saveRDS(list(m_full_col1 = m_full_col1, m_hrex_col1 = m_hrex_col1,
             m_full_panelC = m_full_panelC, m_hrex_panelC = m_hrex_panelC),
        "data/processed/ntl/extension_table2_lnpop_models.rds")
cat("\nSaved: data/processed/ntl/extension_table2_lnpop_models.rds\n")
