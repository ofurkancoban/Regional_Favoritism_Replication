# 07_regression/table5/01_determinants.R
# HR 2014 Table V: Determinants of Regional Favoritism.
# Spec (p.1020-1021): ln_ntl ~ l(is_birthregion) + l(is_birthregion):X | gid_2 + gid_0^year
# for X in {Polity, Schooling, NationalGDP, Language, FamilyTies}, plus a
# combined Col(6) with Polity + Schooling + Language + FamilyTies together
# (HR's own Col(6) omits NationalGDP -- matched here).
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
d <- d[year %between% c(1992L, 2013L)]
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    nrow(d), data.table::uniqueN(d$gid_2), data.table::uniqueN(d$iso3)))

cat("\n=== Build Archigos leader-spell clusters ===\n")
arch <- data.table::as.data.table(haven::read_dta("data/raw/archigos/Archigos_4.1.dta"))
arch[, startyear := as.integer(substr(startdate, 1, 4))]
arch[, endyear   := as.integer(substr(enddate,   1, 4))]
arch <- arch[!is.na(startyear) & !is.na(endyear)]
arch[, iso3 := suppressWarnings(countrycode::countrycode(ccode, "cown", "iso3c"))]
arch <- arch[!is.na(iso3)]

arch_yr <- arch[, {
  yrs <- seq(max(startyear, 1992L), min(endyear, 2013L))
  if (length(yrs) == 0L) yrs <- integer(0)
  .(year = yrs, iso3 = iso3)
}, by = .(obsid)]
arch_yr <- arch_yr[year %between% c(1992L, 2013L)]
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
m1 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * polity | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m2 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * schooling | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m3 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * national_gdp | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m4 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * language | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m5 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * family_ties | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m6 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * (polity + schooling + language + family_ties) | gid_2 + gid_0^year,
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

out_dir <- "data/processed/ntl"
saveRDS(list(m1 = m1, m2 = m2, m3 = m3, m4 = m4, m5 = m5, m6 = m6),
        file.path(out_dir, "table5_determinants_models.rds"))
cat(sprintf("\nModels saved: %s\n", file.path(out_dir, "table5_determinants_models.rds")))
