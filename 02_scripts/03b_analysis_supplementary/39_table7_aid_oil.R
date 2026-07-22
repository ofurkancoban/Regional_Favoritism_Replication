# ==============================================================================
# File:          39_table7_aid_oil.R
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
# Description:   Full replication of HR 2014 Table VII (Aid, Oil, and
#                Regional Favoritism, p. 1024) on the authors' exact
#                126-country, 1992-2009 sample. Spec: ln_ntl ~
#                l(is_birthregion) * X [* Polity] | gid_2 + gid_0^year:
#                  Col(1): X = Aid
#                  Col(2): X = Oil
#                  Col(3): X = Aid, plus a triple interaction with Polity
#                  Col(4): X = Oil, plus a triple interaction with Polity
#                HR's notation lags all time-varying covariates
#                (Aid/Oil/Polity) one period, same as Table V.
#
# Inputs:        01_datasets/processed/analysis_panel.csv,
#                01_datasets/raw/plad/hr2014_126_countries.csv,
#                01_datasets/processed/hr_excluded_above65n_regions.csv,
#                01_datasets/raw/archigos/Archigos_4.1.dta,
#                01_datasets/processed/table7_covariates.csv (Stage 35)
# Outputs:       01_datasets/processed/ntl/table7_aid_oil_models.rds,
#                01_datasets/processed/ntl/table7_aid_oil_summary.csv
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

cat("\n=== Merge Aid/Oil/Polity covariates (Stage 35) ===\n")
cov <- data.table::fread(here::here("01_datasets/processed/table7_covariates.csv"))
d <- merge(d, cov, by = c("iso3", "year"), all.x = TRUE)
cat(sprintf("Non-NA: aid=%d oil=%d polity=%d\n",
    d[!is.na(aid), .N], d[!is.na(oil), .N], d[!is.na(polity), .N]))

data.table::setorder(d, gid_2, year)
d_fe <- fixest::panel(d, ~gid_2 + year)

cat("\n=== Table VII regressions ===\n")
m1 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(aid) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m2 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(oil) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m3 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(aid) * fixest::l(polity) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m4 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(oil) * fixest::l(polity) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

fixest::etable(m1, m2, m3, m4,
  digits  = 3,
  headers = c("(1) Aid", "(2) Oil", "(3) Aid x Polity", "(4) Oil x Polity")
)

cat("\n=== Comparison with HR 2014 Table VII (p. 1024) ===\n")
cat("Col(1) HR: Leader -0.019 (0.015), Leader x Aid 0.008*** (0.002)\n")
cat("Col(2) HR: Leader  0.020 (0.022), Leader x Oil 0.000 (0.002)\n")
cat("Col(3) HR: Leader  0.086 (0.073), Leader x Aid 0.019** (0.009), Leader x Polity -0.121 (0.074), Leader x Aid x Polity -0.019* (0.010)\n")
cat("Col(4) HR: Leader  0.118 (0.084), Leader x Oil 0.010 (0.008), Leader x Polity -0.109 (0.094), Leader x Oil x Polity -0.014 (0.010)\n")

cat("\n=== Summary stats (Number of regions, R2) ===\n")
summary_rows <- data.table::data.table(
  col = 1:4,
  n_regions = sapply(list(m1, m2, m3, m4), function(m) length(fixest::fixef(m)[[1]])),
  n_obs = sapply(list(m1, m2, m3, m4), stats::nobs),
  r2 = round(sapply(list(m1, m2, m3, m4), function(m) fixest::r2(m, "r2")), 3)
)
print(summary_rows)

out_dir <- here::here("01_datasets/processed/ntl")
saveRDS(list(m1 = m1, m2 = m2, m3 = m3, m4 = m4),
        file.path(out_dir, "table7_aid_oil_models.rds"))
data.table::fwrite(summary_rows, file.path(out_dir, "table7_aid_oil_summary.csv"))
cat(sprintf("Summary saved: %s\n", file.path(out_dir, "table7_aid_oil_summary.csv")))
cat(sprintf("\nModels saved: %s\n", file.path(out_dir, "table7_aid_oil_models.rds")))
