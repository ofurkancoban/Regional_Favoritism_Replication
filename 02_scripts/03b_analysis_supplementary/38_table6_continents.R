# ==============================================================================
# File:          38_table6_continents.R
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
# Category:      Econometric Analysis (Supplementary)
#
# Description:   Full replication of HR 2014 Table VI (Regional
#                Favoritism across Continents, p. 1023) on the authors'
#                exact 126-country, 1992-2009 sample. The pooled
#                Leader_ict-1 effect is decomposed into five
#                continent-specific terms (Leader x Africa, x Americas,
#                x Asia, x Europe, x Oceania), all included with no
#                dropped reference category, since region and
#                country-year fixed effects already absorb any
#                continent-level main effect. Column (1) is the plain
#                decomposition; Column (2) adds Leader x Polity; Column
#                (3) adds all five Table V covariates (same lag
#                convention as Stage 37). Continent classification via
#                countrycode::countrycode(iso3, "iso3c", "continent"),
#                the same five-region split HR use.
#
# Inputs:        01_datasets/processed/analysis_panel.csv,
#                01_datasets/raw/plad/hr2014_126_countries.csv,
#                01_datasets/processed/hr_excluded_above65n_regions.csv,
#                01_datasets/raw/archigos/Archigos_4.1.dta,
#                01_datasets/processed/table5_covariates.csv (Stage 34)
# Outputs:       01_datasets/processed/ntl/table6_continents_models.rds
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

cat("=== Load analysis panel ===\n")
d <- data.table::fread(here::here("01_datasets/processed/analysis_panel.csv"))
hr126 <- data.table::fread(here::here("01_datasets/raw/plad/hr2014_126_countries.csv"))
hr_65n <- data.table::fread(here::here("01_datasets/processed/hr_excluded_above65n_regions.csv"))
d <- d[iso3 %in% hr126$iso3]
d <- d[!gid_2 %in% hr_65n$gid_2]
d <- d[year %between% c(1992L, 2009L)]
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    nrow(d), data.table::uniqueN(d$gid_2), data.table::uniqueN(d$iso3)))

cat("\n=== Build Archigos leader-spell clusters ===\n")
arch <- data.table::as.data.table(haven::read_dta(here::here("01_datasets/raw/archigos/Archigos_4.1.dta")))
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

cat("\n=== Merge Table V covariates (Stage 34) ===\n")
cov <- data.table::fread(here::here("01_datasets/processed/table5_covariates.csv"))
d <- merge(d, cov, by = c("iso3", "year"), all.x = TRUE)

cat("\n=== Assign continents ===\n")
# is_birthregion is logical; coerce to integer before use in `:`
# interaction formulas, otherwise R's default contrast coding for a
# 2-level factor (FALSE/TRUE) collides with the FE-absorbed intercept
# and drops columns via collinearity instead of producing the intended
# TRUE-indicator coefficient.
d[, is_birthregion := as.integer(is_birthregion)]
d[, continent := countrycode::countrycode(iso3, "iso3c", "continent")]
cat("Continent distribution (country-years):\n")
print(d[, .N, by = continent])
d[, africa   := as.integer(continent == "Africa")]
d[, americas := as.integer(continent == "Americas")]
d[, asia     := as.integer(continent == "Asia")]
d[, europe   := as.integer(continent == "Europe")]
d[, oceania  := as.integer(continent == "Oceania")]

data.table::setorder(d, gid_2, year)
d_fe <- fixest::panel(d, ~gid_2 + year)

cat("\n=== Table VI regressions ===\n")
m1 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion):africa + fixest::l(is_birthregion):americas +
           fixest::l(is_birthregion):asia + fixest::l(is_birthregion):europe +
           fixest::l(is_birthregion):oceania | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)
m2 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion):africa + fixest::l(is_birthregion):americas +
           fixest::l(is_birthregion):asia + fixest::l(is_birthregion):europe +
           fixest::l(is_birthregion):oceania +
           fixest::l(is_birthregion):fixest::l(polity) | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)
m3 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion):africa + fixest::l(is_birthregion):americas +
           fixest::l(is_birthregion):asia + fixest::l(is_birthregion):europe +
           fixest::l(is_birthregion):oceania +
           fixest::l(is_birthregion):(fixest::l(polity) + fixest::l(schooling) +
             fixest::l(national_gdp) + language + family_ties) | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

fixest::etable(m1, m2, m3,
  digits  = 3,
  headers = c("(1) Continents", "(2) + Polity", "(3) + All covariates")
)

cat("\n=== Comparison with HR 2014 Table VI (p. 1023) ===\n")
cat("Col(1) HR: Africa 0.071*** (0.026), Americas 0.000 (0.025), Asia 0.121*** (0.042), Europe -0.019* (0.010), Oceania -0.112 (0.077)\n")
cat("Col(2) HR: Africa 0.235*** (0.047), Americas 0.243*** (0.067), Asia 0.296*** (0.073), Europe 0.239*** (0.067), Oceania 0.106 (0.101), Polity -0.278*** (0.070)\n")
cat("Col(3) HR: Africa 0.041 (0.167), Americas 0.056 (0.179), Asia 0.005 (0.147), Europe 0.035 (0.163), Oceania 0.167 (0.168), Polity -0.252*** (0.068), Schooling -0.027*** (0.007), NationalGDP 0.047** (0.020), Language 0.024 (0.046), FamilyTies 0.011 (0.037)\n")

out_dir <- here::here("01_datasets/processed/ntl")
saveRDS(list(m1 = m1, m2 = m2, m3 = m3),
        file.path(out_dir, "table6_continents_models.rds"))
cat(sprintf("\nModels saved: %s\n", file.path(out_dir, "table6_continents_models.rds")))
