# ==============================================================================
# File:          34_table5_covariates.R
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
# Category:      Data Preprocessing (Supplementary)
#
# Description:   Builds the five country-year covariates behind HR 2014
#                Table V (Determinants of Regional Favoritism), Table VI
#                (Continents), and Table VII (Aid, Oil)'s Polity control:
#                  Polity_ct:      Polity2 score, rescaled 0-1. QoG.
#                  Schooling_ct:   Average years of schooling, 15+.
#                                  Barro & Lee (2013), interpolated from
#                                  5-year intervals to an annual panel.
#                  NationalGDP_ct: log GDP per capita, PPP, 2005 constant
#                                  prices. Penn World Table 7.1 via CRAN's
#                                  `pwt` package (`rgdpch`), HR's exact
#                                  stated source, not a substitute.
#                  Language_c:     Linguistic fractionalization index
#                                  (time-invariant). Alesina et al. (2003)
#                                  via QoG's `al_language2000`.
#                  FamilyTies_c:   Time-invariant, from Stage 33.
#
# Inputs:        01_datasets/raw/qog/qog_std_ts_jan26.csv,
#                01_datasets/raw/qog/BL2013_MF1599_v2.2.csv,
#                01_datasets/processed/family_ties_country.csv (Stage 33),
#                CRAN package `pwt` (data(pwt7.1))
# Outputs:       01_datasets/processed/table5_covariates.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

years_rep <- 1992:2013

cat("=== Polity, Language from QoG ===\n")
qog <- data.table::fread(
  here::here("01_datasets/raw/qog/qog_std_ts_jan26.csv"),
  select = c("ccodealp", "year", "p_polity2", "al_language2000")
)
data.table::setnames(qog, "ccodealp", "iso3")
qog <- qog[year %in% years_rep]
qog[, polity := (p_polity2 + 10) / 20]  # HR: rescaled to range from 0 to 1
lang <- unique(qog[!is.na(al_language2000), .(iso3, language = al_language2000)], by = "iso3")
cat(sprintf("Polity rows: %d | Language (time-invariant) countries: %d\n", nrow(qog), nrow(lang)))

cat("\n=== NationalGDP: Penn World Table 7.1 (HR's exact source) ===\n")
utils::data("pwt7.1", package = "pwt")
pwt_dt <- data.table::as.data.table(pwt7.1)
# PWT 7.1 uses several non-ISO3166 legacy codes: GER (not DEU) for Germany,
# ZAR (not COD, pre-1997 "Zaire" name) for DR Congo, ROM (not ROU) for
# Romania. Remapped before merging so these three countries aren't
# silently dropped. Myanmar/North Korea/Kosovo are genuine coverage gaps
# in PWT 7.1, not a coding issue.
pwt_iso3_fix <- c(GER = "DEU", ZAR = "COD", ROM = "ROU")
pwt_dt[, iso3_raw := as.character(isocode)]
pwt_dt[, iso3 := data.table::fifelse(iso3_raw %in% names(pwt_iso3_fix), pwt_iso3_fix[iso3_raw], iso3_raw)]
pwt_dt <- pwt_dt[year %in% years_rep & !is.na(rgdpch), .(iso3, year, national_gdp = log(rgdpch))]
cat(sprintf("PWT 7.1 rows: %d | countries: %d\n", nrow(pwt_dt), data.table::uniqueN(pwt_dt$iso3)))

cat("\n=== Schooling: Barro-Lee ===\n")
bl <- data.table::fread(here::here("01_datasets/raw/qog/BL2013_MF1599_v2.2.csv"))
bl <- bl[sex == "MF", .(iso3 = WBcode, year, schooling = yr_sch)]
bl <- bl[!is.na(iso3) & iso3 != ""]
cat(sprintf("Barro-Lee rows (5-year intervals, 1950-2010): %d | countries: %d\n",
    nrow(bl), data.table::uniqueN(bl$iso3)))

# Interpolate/extrapolate the 5-year Barro-Lee series to an annual
# 1992-2013 panel per country (stats::approx(..., rule=2), same approach
# used for GPWv4 population in Stage 18).
cat("Interpolating to annual panel (1992-2013)...\n")
schooling_annual <- bl[, {
  if (.N < 2) {
    .(year = years_rep, schooling = NA_real_)
  } else {
    ap <- stats::approx(x = year, y = schooling, xout = years_rep, rule = 2)
    .(year = ap$x, schooling = ap$y)
  }
}, by = iso3]
schooling_annual <- schooling_annual[!is.na(schooling)]
cat(sprintf("Schooling annual rows: %d | countries: %d\n",
    nrow(schooling_annual), data.table::uniqueN(schooling_annual$iso3)))

cat("\n=== FamilyTies (WVS/EVS, time-invariant, Stage 33) ===\n")
ft_path <- here::here("01_datasets/processed/family_ties_country.csv")
require_input_file(ft_path, "FamilyTies country index",
  "n/a -- run Stage 33 (33_wvs_family_ties.R) first",
  note = "This is a project output, not a raw download; Stage 33 itself needs the WVS/EVS Trend Files (see its own header).")
ft <- data.table::fread(ft_path)
ft <- ft[, .(iso3, family_ties)]
cat(sprintf("FamilyTies countries: %d\n", nrow(ft)))

cat("\n=== Merge ===\n")
panel <- data.table::CJ(iso3 = unique(c(qog$iso3, pwt_dt$iso3)), year = years_rep)
panel <- merge(panel, qog[, .(iso3, year, polity)], by = c("iso3", "year"), all.x = TRUE)
panel <- merge(panel, pwt_dt, by = c("iso3", "year"), all.x = TRUE)
panel <- merge(panel, schooling_annual, by = c("iso3", "year"), all.x = TRUE)
panel <- merge(panel, lang, by = "iso3", all.x = TRUE)
panel <- merge(panel, ft, by = "iso3", all.x = TRUE)

cat(sprintf("Final covariate panel: %d rows | %d countries\n", nrow(panel), data.table::uniqueN(panel$iso3)))
cat(sprintf("  Non-NA polity: %d | national_gdp: %d | schooling: %d | language: %d | family_ties: %d\n",
    panel[!is.na(polity), .N], panel[!is.na(national_gdp), .N], panel[!is.na(schooling), .N],
    panel[!is.na(language), .N], panel[!is.na(family_ties), .N]))

data.table::fwrite(panel, here::here("01_datasets/processed/table5_covariates.csv"))
cat("\nSaved: 01_datasets/processed/table5_covariates.csv\n")
