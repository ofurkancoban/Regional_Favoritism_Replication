# 05_covariates/04_table5_covariates.R
# HR 2014 Table V (Determinants of Regional Favoritism) covariates:
#   Polity_ct:       Polity2 score, rescaled 0-1. Source: Polity IV/5.
#   Schooling_ct:    Average years of schooling, population 15+. Source:
#                     Barro & Lee (2013) -- data/raw/qog/BL2013_MF1599_v2.2.csv
#                     (already on disk, ages 15-99, 5-year intervals 1950-2010).
#   NationalGDP_ct:  log GDP per capita, PPP, 2005 constant prices. HR's
#                     exact source: Heston, Summers, Aten (2012) = Penn
#                     World Table 7.1. Used directly via CRAN's `pwt`
#                     package (`data(pwt7.1)`, variable `rgdpch` = "PPP
#                     Converted GDP Per Capita (Chain Series), at 2005
#                     constant prices" -- matches HR's Appendix A
#                     description verbatim), not a substitute/proxy.
#   Language_c:      Index of linguistic fractionalization (time-invariant).
#                     Source: Alesina et al. (2003), already in QoG as
#                     `al_language2000`.
#   FamilyTies_c:    Time-invariant. Built in 05_covariates/03_wvs_family_ties.R.
#
# Output: data/processed/table5_covariates.csv
#   Time-varying: iso3, year, polity, national_gdp, schooling
#   Time-invariant (repeated across years): language, family_ties

library(data.table)
library(pwt)

years_rep <- 1992:2013

cat("=== Polity, Language from QoG ===\n")
qog <- data.table::fread(
  "data/raw/qog/qog_std_ts_jan26.csv",
  select = c("ccodealp", "year", "p_polity2", "al_language2000")
)
data.table::setnames(qog, "ccodealp", "iso3")
qog <- qog[year %in% years_rep]
qog[, polity := (p_polity2 + 10) / 20]  # HR: rescaled to range from 0 to 1
lang <- unique(qog[!is.na(al_language2000), .(iso3, language = al_language2000)], by = "iso3")
cat(sprintf("Polity rows: %d | Language (time-invariant) countries: %d\n", nrow(qog), nrow(lang)))

cat("\n=== NationalGDP: Penn World Table 7.1 (HR's exact source) ===\n")
data(pwt7.1, package = "pwt")
pwt_dt <- data.table::as.data.table(pwt7.1)
# PWT 7.1 uses several non-ISO3166 legacy codes -- verified by diffing PWT's
# code list against our analysis panel's iso3 set: GER (not DEU) for
# Germany, ZAR (not COD, pre-1997 "Zaire" name) for DR Congo, ROM (not ROU)
# for Romania. Remap before merging so these three countries aren't
# silently dropped. Myanmar/North Korea/Kosovo are genuinely absent from
# PWT 7.1 (real coverage gaps, not a coding issue -- nothing to remap).
pwt_iso3_fix <- c(GER = "DEU", ZAR = "COD", ROM = "ROU")
pwt_dt[, iso3_raw := as.character(isocode)]
pwt_dt[, iso3 := data.table::fifelse(iso3_raw %in% names(pwt_iso3_fix), pwt_iso3_fix[iso3_raw], iso3_raw)]
pwt_dt <- pwt_dt[year %in% years_rep & !is.na(rgdpch), .(iso3, year, national_gdp = log(rgdpch))]
cat(sprintf("PWT 7.1 rows: %d | countries: %d\n", nrow(pwt_dt), data.table::uniqueN(pwt_dt$iso3)))

cat("\n=== Schooling: Barro-Lee (already on disk) ===\n")
bl <- data.table::fread("data/raw/qog/BL2013_MF1599_v2.2.csv")
bl <- bl[sex == "MF", .(iso3 = WBcode, year, schooling = yr_sch)]
bl <- bl[!is.na(iso3) & iso3 != ""]
cat(sprintf("Barro-Lee rows (5-year intervals, 1950-2010): %d | countries: %d\n",
    nrow(bl), data.table::uniqueN(bl$iso3)))

# Interpolate/extrapolate the 5-year Barro-Lee series to an annual
# 1992-2013 panel per country -- same approach already used for GPWv4
# population (stats::approx(..., rule=2), see 05_covariates/02_gpw_population.R).
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

cat("\n=== FamilyTies (WVS, time-invariant) ===\n")
ft <- data.table::fread("data/processed/family_ties_country.csv")
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

data.table::fwrite(panel, "data/processed/table5_covariates.csv")
cat("\nSaved: data/processed/table5_covariates.csv\n")
