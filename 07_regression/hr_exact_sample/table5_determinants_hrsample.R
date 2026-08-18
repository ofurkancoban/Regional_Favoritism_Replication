# 07_regression/table5/01_determinants.R
# HR 2014 Table V: Determinants of Regional Favoritism.
# Spec (p.1020-1021): ln_ntl ~ l(is_birthregion) + l(is_birthregion):X | gid_2 + gid_0^year
# for X in {Polity, Schooling, NationalGDP, Language, FamilyTies}, plus a
# combined Col(6) with all five determinants together -- confirmed against
# the paper text ("In column (6), we look at all five potential
# determinants together," p.1022) and the table's own Col(6) values, which
# include Leader x NationalGDP = 0.050***. A previous version of this
# script incorrectly omitted NationalGDP from Col(6).
#
# Covariates: 05_covariates/04_table5_covariates.R (Polity2 rescaled 0-1,
# Barro-Lee schooling interpolated to annual, QoG PWT-based GDP per capita,
# Alesina et al. 2003 linguistic fractionalization, WVS-derived FamilyTies).
#
# Data source deviations from HR 2014 (documented, same pattern as the
# Table II Col(8) G-Econ substitution):
#   - NationalGDP: QoG's `pwt_rgdp`/`pwt_pop` (a more recent PWT vintage)
#     instead of HR's Heston, Summers & Aten (2012) PWT 7.1.
#   - FamilyTies: reconstructed from WVS microdata (waves 1-4, 1981-2004)
#     following Alesina & Giuliano's own published methodology, since
#     neither their 2010 nor 2014 paper publishes a raw country lookup
#     table (values are only shown as a map/figure) -- see
#     05_covariates/03_wvs_family_ties.R header for full detail. Only
#     4 waves (not 6) could be reconstructed; empirically validated against
#     the country pattern the paper itself describes (Scandinavia weakest,
#     Egypt/Zimbabwe/Philippines/Venezuela strongest).

library(data.table)
library(fixest)
library(haven)
library(countrycode)

cat("=== Load analysis panel ===\n")
d <- data.table::fread("data/processed/analysis_panel.csv")
# HR 2014 exact-sample restriction test (2026-08-17): drop countries with
# avg population < 500,000 and ADM2 regions entirely above 65N latitude,
# matching HR's own stated exclusion criteria (p. 1001).
hr126 <- data.table::fread("data/raw/plad/hr2014_126_countries.csv")
hr_65n <- data.table::fread("data/processed/hr_excluded_above65n_regions.csv")
d <- d[iso3 %in% hr126$iso3]
d <- d[!gid_2 %in% hr_65n$gid_2]
d <- d[year %between% c(1992L, 2009L)]
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    nrow(d), data.table::uniqueN(d$gid_2), data.table::uniqueN(d$iso3)))

cat("\n=== Build Archigos leader-spell clusters ===\n")
arch <- data.table::as.data.table(haven::read_dta("data/raw/archigos/Archigos_4.1.dta"))
arch[, startyear := as.integer(substr(startdate, 1, 4))]
arch[, endyear   := as.integer(substr(enddate,   1, 4))]
arch <- arch[!is.na(startyear) & !is.na(endyear)]
arch[, iso3 := suppressWarnings(countrycode::countrycode(ccode, "cown", "iso3c",
  custom_match = c("260" = "DEU", "340" = "SRB", "345" = "SRB", "678" = "YEM")))]
arch <- arch[!is.na(iso3)]

arch_yr <- arch[, {
  lo <- max(startyear, 1992L)
  hi <- min(endyear, 2009L)
  yrs <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yrs, iso3 = iso3)
}, by = .(obsid)]
arch_yr <- arch_yr[year %between% c(1992L, 2009L)]
data.table::setorder(arch_yr, iso3, year, obsid)
arch_yr <- unique(arch_yr, by = c("iso3", "year"))
data.table::setorder(arch_yr, iso3, year)
arch_yr[, spell_cluster := data.table::shift(obsid, 1L), by = iso3]
arch_yr[is.na(spell_cluster), spell_cluster := obsid]

d <- merge(d, arch_yr[, .(iso3, year, spell_cluster)], by = c("iso3", "year"), all.x = TRUE)
d[is.na(spell_cluster), spell_cluster := iso3]

cat("\n=== Merge Table V covariates ===\n")
cov <- data.table::fread("data/processed/table5_covariates.csv")
d <- merge(d, cov, by = c("iso3", "year"), all.x = TRUE)
cat(sprintf("Non-NA: polity=%d national_gdp=%d schooling=%d language=%d family_ties=%d\n",
    d[!is.na(polity), .N], d[!is.na(national_gdp), .N], d[!is.na(schooling), .N],
    d[!is.na(language), .N], d[!is.na(family_ties), .N]))

data.table::setorder(d, gid_2, year)
d_fe <- fixest::panel(d, ~gid_2 + year)

cat("\n=== Table V regressions ===\n")
# HR's notation is Leader_ict-1 x Polity_ct-1 / Schooling_ct-1 / NationalGDP_ct-1
# -- the time-varying covariates are ALSO lagged one period, not just Leader.
# Language_c and FamilyTies_c carry no time subscript (time-invariant), so
# they are correctly left unlagged.
m1 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(polity) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m2 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(schooling) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m3 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(national_gdp) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m4 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * language | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m5 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * family_ties | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m6 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * (fixest::l(polity) + fixest::l(schooling) + fixest::l(national_gdp) + language + family_ties) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

fixest::etable(m1, m2, m3, m4, m5, m6,
  digits  = 3,
  headers = c("(1) Polity", "(2) Schooling", "(3) NationalGDP", "(4) Language", "(5) FamilyTies", "(6) Combined")
)

cat("\n=== Comparison with HR 2014 Table V ===\n")
cat("Col(1) HR: Leader 0.262*** (0.056), Leader x Polity -0.298*** (0.063)\n")
cat("Col(2) HR: Leader 0.119*** (0.040), Leader x Schooling -0.012*** (0.004)\n")
cat("Col(3) HR: Leader 0.196** (0.082), Leader x NationalGDP -0.019** (0.009)\n")
cat("Col(4) HR: Leader -0.008 (0.017), Leader x Language 0.120*** (0.040)\n")
cat("Col(5) HR: Leader 0.008 (0.012), Leader x FamilyTies 0.063** (0.032)\n")
cat("Col(6) HR: Leader 0.036 (0.134), Leader x Polity -0.240*** (0.065),\n")
cat("           Leader x Schooling -0.024*** (0.007), Leader x NationalGDP 0.050*** (0.018),\n")
cat("           Leader x Language 0.016 (0.052), Leader x FamilyTies 0.035 (0.034)\n")

out_dir <- "data/processed/ntl"
saveRDS(list(m1 = m1, m2 = m2, m3 = m3, m4 = m4, m5 = m5, m6 = m6),
        file.path(out_dir, "table5_determinants_models.rds"))
cat(sprintf("\nModels saved: %s\n", file.path(out_dir, "table5_determinants_models.rds")))
