# 07_regression/table6/01_continents.R
# HR 2014 Table VI: Regional Favoritism Across Continents (p. 1023).
#
# Spec: the pooled Leader_ict-1 effect from Table II Col(1) is decomposed
# into five continent-specific terms (Leader_ict-1 x Africa_c, x Americas_c,
# x Asia_c, x Europe_c, x Oceania_c), all included with no dropped reference
# category -- region + country-year FE already absorb any continent-level
# main effect, so this is a clean decomposition of the single pooled
# coefficient, not a set of contrasts against an omitted continent.
#   Col(1): continent interactions only
#   Col(2): + Leader_ict-1 x Polity_ct-1
#   Col(3): + Leader_ict-1 x (Polity_ct-1 + Schooling_ct-1 + NationalGDP_ct-1
#            + Language_c + FamilyTies_c) -- same Table V covariates
#            (05_covariates/04_table5_covariates.R), same lag convention
#            (time-varying covariates lagged, time-invariant not).
#
# Continent classification: countrycode::countrycode(iso3, "iso3c",
# "continent") -- gives the same five-region split HR use (Africa, Americas,
# Asia, Europe, Oceania).

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

cat("\n=== Merge Table V covariates (Polity, Schooling, NationalGDP, Language, FamilyTies) ===\n")
cov <- data.table::fread("data/processed/table5_covariates.csv")
d <- merge(d, cov, by = c("iso3", "year"), all.x = TRUE)

cat("\n=== Assign continents ===\n")
# is_birthregion is logical -- coerce to integer before use in `:` interaction
# formulas, otherwise R's default contrast coding for a 2-level factor
# (FALSE/TRUE) collides with the FE-absorbed intercept and drops columns via
# collinearity instead of producing the intended TRUE-indicator coefficient.
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

cat("\n=== Comparison with HR 2014 Table VI ===\n")
cat("Col(1) HR: Africa 0.071*** (0.026), Americas 0.000 (0.025), Asia 0.121*** (0.042), Europe 0.019* (0.010), Oceania 0.112 (0.077)\n")
cat("Col(2) HR: Africa 0.235*** (0.047), Americas 0.243*** (0.067), Asia 0.296*** (0.073), Europe 0.239*** (0.067), Oceania 0.106 (0.101), Polity -0.278*** (0.070)\n")
cat("Col(3) HR: Africa 0.041 (0.167), Americas 0.056 (0.179), Asia 0.005 (0.147), Europe 0.035 (0.163), Oceania 0.167 (0.168), Polity -0.252*** (0.068), Schooling -0.027*** (0.007), NationalGDP -0.047** (0.020), Language 0.024 (0.046), FamilyTies 0.011 (0.037)\n")

out_dir <- "data/processed/ntl"
saveRDS(list(m1 = m1, m2 = m2, m3 = m3),
        file.path(out_dir, "table6_continents_models.rds"))
cat(sprintf("\nModels saved: %s\n", file.path(out_dir, "table6_continents_models.rds")))
