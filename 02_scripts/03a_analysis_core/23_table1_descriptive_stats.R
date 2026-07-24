# ==============================================================================
# File:          23_table1_descriptive_stats.R
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
# Category:      Econometric Analysis
#
# Description:   Computes this project's own Table I descriptive statistics (region-year and country-year panel-data xtsum-style summaries) on the authors' exact 126-country, 1992-2009 sample.
#
# Inputs:        01_datasets/processed/analysis_panel.csv
# Outputs:       01_datasets/processed/table1_descriptive_region_hrsample.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

years_hr <- 1992:2009

cat("=== Load analysis panel, restrict to HR's exact sample ===\n")
d <- data.table::fread(here::here("01_datasets/processed/analysis_panel.csv"))
hr126 <- data.table::fread(here::here("01_datasets/raw/plad/hr2014_126_countries.csv"))
hr_65n <- data.table::fread(here::here("01_datasets/processed/hr_excluded_above65n_regions.csv"))
# Third exclusion criterion (p. 1001): "the few regions that are
# unpopulated." Proxy: regions never matched to a GPWv4 population figure
# in any observed year -- see Stage 21b for the important caveat that
# this is not a verified match to the authors' own concept, just the
# closest available signal.
hr_unpop <- data.table::fread(here::here("01_datasets/processed/hr_excluded_unpopulated_regions.csv"))
d <- d[iso3 %in% hr126$iso3]
d <- d[!gid_2 %in% hr_65n$gid_2]
d <- d[!gid_2 %in% hr_unpop$gid_2]
d <- d[year %in% years_hr]
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    nrow(d), data.table::uniqueN(d$gid_2), data.table::uniqueN(d$iso3)))

cat("\n=== Build Leader_ict-1 (lagged is_birthregion) ===\n")
lag_map <- d[, .(gid_2, year = year + 1L, leader_lag = as.integer(is_birthregion))]
d <- merge(d, lag_map, by = c("gid_2", "year"), all.x = TRUE)

cat("\n=== Merge Table V + Table VII covariates, build lags ===\n")
cov5 <- data.table::fread(here::here("01_datasets/processed/table5_covariates.csv"))
cov7 <- data.table::fread(here::here("01_datasets/processed/table7_covariates.csv"))[, .(iso3, year, aid, oil)]
cov <- merge(cov5, cov7, by = c("iso3", "year"), all = TRUE)

# Time-varying covariates carry a t-1 lag in HR's own notation (Polityct-1,
# Schoolingct-1, NationalGDPct-1, Aidct-1, Oilct-1); Language_c and
# FamilyTies_c are time-invariant, no lag applies.
cov_lag <- cov[, .(iso3, year = year + 1L,
                    polity_lag = polity, schooling_lag = schooling,
                    national_gdp_lag = national_gdp, aid_lag = aid, oil_lag = oil)]
d <- merge(d, cov_lag, by = c("iso3", "year"), all.x = TRUE)
d <- merge(d, unique(cov[, .(iso3, language, family_ties)], by = "iso3"), by = "iso3", all.x = TRUE)

cat("\n=== Compute panel descriptive stats (xtsum-style) ===\n")
xtsum <- function(x, unit) {
  ok <- !is.na(x) & !is.na(unit)
  x <- x[ok]; unit <- unit[ok]
  if (length(x) == 0) return(c(obs = 0, mean = NA, sd_overall = NA, sd_between = NA, sd_within = NA, min = NA, max = NA))
  grand_mean <- mean(x)
  dt <- data.table::data.table(x = x, unit = unit)
  unit_means <- dt[, .(m = mean(x)), by = unit]
  dt <- merge(dt, unit_means, by = "unit")
  c(obs = length(x), mean = grand_mean, sd_overall = stats::sd(x),
    sd_between = stats::sd(unit_means$m), sd_within = stats::sd(x - dt$m + grand_mean),
    min = min(x), max = max(x))
}

vars <- list(
  Lightict         = "ln_ntl",
  `Leaderict-1`     = "leader_lag",
  `Polityct-1`      = "polity_lag",
  `Schoolingct-1`   = "schooling_lag",
  `NationalGDPct-1` = "national_gdp_lag",
  Languagec        = "language",
  FamilyTiesc      = "family_ties",
  `Aidct-1`         = "aid_lag",
  `Oilct-1`         = "oil_lag"
)

cat("\n=== Region-year level (main rows) ===\n")
region_stats <- lapply(vars, function(v) xtsum(d[[v]], d$gid_2))
region_dt <- data.table::rbindlist(lapply(region_stats, function(x) as.list(x)))
region_dt[, variable := names(vars)]
data.table::setcolorder(region_dt, "variable")
print(region_dt, digits = 3)

cat("\n=== Country-year level (parenthetical rows) ===\n")
# Collapse to one row per country-year first (values are already constant
# within a country-year for the country-level covariates; for Light/Leader,
# take the country-year mean across regions, same aggregation HR describe).
cy <- d[, c(list(iso3 = iso3[1]), lapply(.SD, function(x) if (is.numeric(x)) mean(x, na.rm = TRUE) else x[1])),
        by = .(iso3, year), .SDcols = unlist(vars)]
cy_stats <- lapply(vars, function(v) xtsum(cy[[v]], cy$iso3))
cy_dt <- data.table::rbindlist(lapply(cy_stats, function(x) as.list(x)))
cy_dt[, variable := names(vars)]
data.table::setcolorder(cy_dt, "variable")
print(cy_dt, digits = 3)

cat("\n=== HR 2014 Table I (for reference) ===\n")
cat("Lightict:         Obs 690,495 | Mean 0.050 | SD (2.482, 2.425, 0.538) | Min -4.605 | Max 4.143\n")
cat("Leaderict-1:      Obs 690,495 | Mean 0.004 | SD (0.060, 0.045, 0.040) | Min 0.000 | Max 1.000\n")
cat("Polityct-1:       Obs 684,213 | Mean 0.789 | SD (0.257, 0.239, 0.099) | region-year; (2,205 obs, mean 0.670, SD 0.312/0.288/0.123) country-year\n")
cat("Schoolingct-1:    Obs 648,240 | Mean 8.168 | SD (2.783, 2.724, 0.570) | region-year; (1,922 obs, mean 6.968, SD 2.920/2.891/0.518) country-year\n")
cat("NationalGDPct-1:  Obs 683,669 | Mean 8.868 | SD (1.147, 1.137, 0.151) | region-year; (2,200 obs, mean 8.212, SD 1.347/1.337/0.180) country-year\n")
cat("Languagec:        Obs 679,119 | Mean 0.318 | SD (0.281, 0.281, 0.000) | region-year; (2,161 obs, mean 0.438, SD 0.298/0.298/0.000) country-year\n")
cat("FamilyTiesc:      Obs 551,004 | Mean 0.096 | SD (0.311, 0.311, 0.000) | region-year; (1,112 obs, mean 0.041, SD 0.368/0.371/0.000) country-year\n")
cat("Aidct-1:          Obs 690,495 | Mean 6.191 | SD (4.743, 4.069, 2.440) | region-year; (2,251 obs, mean 7.794, SD 4.746/4.348/1.931) country-year\n")
cat("Oilct-1:          Obs 645,396 | Mean 9.357 | SD (4.116, 4.457, 1.001) | region-year; (1,820 obs, mean 6.590, SD 5.262/5.312/1.191) country-year\n")

data.table::fwrite(region_dt, here::here("01_datasets/processed/ntl/table1_descriptive_region_hrsample.csv"))
data.table::fwrite(cy_dt, here::here("01_datasets/processed/ntl/table1_descriptive_countryyear_hrsample.csv"))
cat("\nSaved: data/processed/ntl/table1_descriptive_region_hrsample.csv, table1_descriptive_countryyear_hrsample.csv\n")
