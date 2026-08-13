# Purpose: Table V (determinants) covariates for the 1992-2023 extension
# window. The HR-window covariates (05_covariates/04_table5_covariates.R,
# Barro-Lee raw CSV + PWT 7.1) do not extend past ~2010-2013 -- both
# source files stop there. DHR (2025/2026)'s own covariate prep
# (01_literature/dataverse_files/code/dataprep/qog.R) solves this by
# pulling from a single recent QoG "Standard Time-Series" compilation
# (qog_std_ts_jan26.csv, already on disk at data/raw/qog/) instead of the
# original raw sources -- QoG's own team keeps extending/interpolating
# these indicators well past what Barro-Lee's or PWT's own public releases
# cover. This script follows DHR's exact same substitution:
#   - polity:      p_polity2 (same underlying Polity5 source as before,
#                  but coverage genuinely thins out after ~2018 -- this is
#                  a real limitation of the Polity project itself, not
#                  something DHR or we can work around; DHR still includes
#                  it in their regressions, same convention followed here)
#   - vdem_libdem: V-Dem Liberal Democracy Index, ADDED alongside polity
#                  (not in the original HR-window Table V) -- extends
#                  cleanly through 2023, matching DHR's own Panel B/C
#                  extension covariates. Included as an additional robustness
#                  column, not a replacement for polity.
#   - national_gdp: log(wdi_gdpcappppcon2021) -- World Bank WDI GDP per
#                  capita (PPP, constant 2021 USD) INSTEAD of PWT 7.1
#                  (HR's own source, discontinued after ~2013). Same
#                  substitution logic already applied to Table II Col(8)'s
#                  G-Econ deviation -- documented, not hidden.
#   - schooling:   bl_asymf (QoG's own extended/interpolated Barro-Lee
#                  schooling series) -- linearly interpolated to fill
#                  remaining gaps the same way 04_table5_covariates.R
#                  already interpolates the raw Barro-Lee series.
#   - language:    al_ethnic2000 (Alesina et al. 2003), time-invariant,
#                  identical source/definition to the HR-window version.
#   - family_ties: our own WVS-reconstructed measure
#                  (03_wvs_family_ties.R), time-invariant, unchanged.
#
# Output: data/processed/table5_covariates_extension.csv
#   Columns: iso3, year, polity, vdem_libdem, national_gdp, schooling,
#   language, family_ties (1992-2023).
library(data.table)

years_rep <- 1992:2023

cat("=== Load QoG Standard Time-Series (same file DHR uses) ===\n")
qog <- fread("data/raw/qog/qog_std_ts_jan26.csv",
             select = c("ccodealp", "year", "p_polity2", "vdem_libdem",
                        "wdi_gdpcappppcon2021", "bl_asymf", "al_ethnic2000"))
setnames(qog, "ccodealp", "iso3")
qog <- qog[year %in% years_rep]

qog[, polity := (p_polity2 + 10) / 20]  # HR's own 0-1 rescaling, same as HR-window script
qog[, national_gdp := log(wdi_gdpcappppcon2021)]

cat(sprintf("Coverage in %d-%d: polity=%d vdem_libdem=%d national_gdp=%d bl_asymf(raw)=%d\n",
    min(years_rep), max(years_rep),
    qog[!is.na(polity), .N], qog[!is.na(vdem_libdem), .N],
    qog[!is.na(national_gdp), .N], qog[!is.na(bl_asymf), .N]))

cat("\n=== Interpolate schooling (bl_asymf) to fill remaining annual gaps ===\n")
schooling_annual <- qog[, {
  if (all(is.na(bl_asymf))) {
    .(year = years_rep, schooling = NA_real_)
  } else {
    ap <- stats::approx(x = year, y = bl_asymf, xout = years_rep, rule = 2)
    .(year = ap$x, schooling = ap$y)
  }
}, by = iso3]
schooling_annual <- schooling_annual[!is.na(schooling)]
cat(sprintf("Schooling after interpolation: %d rows | %d countries\n",
    nrow(schooling_annual), uniqueN(schooling_annual$iso3)))

cat("\n=== Time-invariant: language (Alesina et al. 2003) ===\n")
lang <- qog[!is.na(al_ethnic2000), .SD[1], by = iso3, .SDcols = "al_ethnic2000"]
setnames(lang, "al_ethnic2000", "language")

cat("\n=== Time-invariant: family_ties (own WVS reconstruction) ===\n")
ft <- fread("data/processed/family_ties_country.csv")

cat("\n=== Assemble panel ===\n")
panel <- CJ(iso3 = unique(qog$iso3), year = years_rep)
panel <- merge(panel, qog[, .(iso3, year, polity, vdem_libdem, national_gdp)], by = c("iso3", "year"), all.x = TRUE)
panel <- merge(panel, schooling_annual, by = c("iso3", "year"), all.x = TRUE)
panel <- merge(panel, lang[, .(iso3, language)], by = "iso3", all.x = TRUE)
panel <- merge(panel, ft, by = "iso3", all.x = TRUE)

cat(sprintf("Panel: %d rows | %d countries\n", nrow(panel), uniqueN(panel$iso3)))
cat(sprintf("Non-NA: polity=%d vdem_libdem=%d national_gdp=%d schooling=%d language=%d family_ties=%d\n",
    panel[!is.na(polity), .N], panel[!is.na(vdem_libdem), .N], panel[!is.na(national_gdp), .N],
    panel[!is.na(schooling), .N], panel[!is.na(language), .N], panel[!is.na(family_ties), .N]))

fwrite(panel, "data/processed/table5_covariates_extension.csv")
cat("Saved: data/processed/table5_covariates_extension.csv\n")
