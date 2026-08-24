# Purpose: Decompose HR 2014-style "regional favoritism" into its regional
# (literal birth-region) and ethnic (co-ethnic homeland) components,
# something neither HR 2014 nor DHR (2025/2026) do -- both use only the
# leader's literal birth region (PLAD) and explicitly frame their
# contribution as showing regional favoritism is not just an
# ethnically-fractionalized-Africa phenomenon (see HR 2014 body text,
# "our article differs... by establishing that regional favoritism is not
# just common in some ethnically fractionalized sub-Saharan African
# countries"). This script asks the question they deliberately set aside:
# within the same sample and specification, does the effect track the
# leader's specific birthplace, or the leader's broader ethnic homeland?
#
# Data:
#   NTL/birth-region panel: data/processed/analysis_panel.csv (our own
#     DMSP GEE extraction, Track2 -- same source as
#     07_regression/table2/02_track2_own.R, 1993-2013 window).
#   Ethnic homeland flag: data/processed/ethnic_homeland_adm2.csv (built by
#     05_covariates/08_ethnic_homeland.R from EPR Core + GeoEPR v2021,
#     ETH Zurich). Positive-match-only file -- left-joined, non-matches
#     treated as FALSE, same convention as is_birthregion itself.
#
# Sample restriction: EPR/GeoEPR only covers 94 of the 148 PLAD countries
# (see 05_covariates/08_ethnic_homeland.R output). Restricting to this
# 94-country subsample for every column below (including the
# birth-region-only baseline) keeps all three specifications on an
# identical sample, so differences in coefficients reflect the variable
# definition, not sample composition.
library(data.table)
library(fixest)
library(haven)
library(countrycode)

cat("=== Load our own DMSP analysis panel (Track2, 1993-2013) ===\n")
d <- fread("data/processed/analysis_panel.csv")
d <- d[year %between% c(1993L, 2013L)]

cat("=== Merge ethnic homeland flag ===\n")
eth <- fread("data/processed/ethnic_homeland_adm2_largest.csv", select = c("GID_2", "GID_0", "year", "is_ethnic_homeland"))
setnames(eth, c("GID_2", "GID_0"), c("gid_2", "gid_0_eth"))
# A single (gid_2, year) can match more than one qualifying ruling group
# (e.g. two SENIOR PARTNER groups both settled in the same region) -- the
# raw file keeps one row per matching group for transparency, but for this
# merge we only need a single TRUE/FALSE flag per region-year.
eth_flag <- unique(eth[, .(gid_2, year, is_ethnic_homeland = TRUE)])
d <- merge(d, eth_flag, by = c("gid_2", "year"), all.x = TRUE)
d[is.na(is_ethnic_homeland), is_ethnic_homeland := FALSE]

eth_countries <- unique(eth$gid_0_eth)
cat(sprintf("Countries with any ethnic-homeland data: %d\n", length(eth_countries)))
d_full <- copy(d)
d <- d[iso3 %in% eth_countries]
cat(sprintf("Restricted panel: %d obs | %d regions | %d countries (was %d obs / %d countries before restriction)\n",
    nrow(d), uniqueN(d$gid_2), uniqueN(d$iso3), nrow(d_full), uniqueN(d_full$iso3)))
cat(sprintf("Positive is_ethnic_homeland flags in restricted panel: %d (%.2f%% of obs)\n",
    sum(d$is_ethnic_homeland), 100 * mean(d$is_ethnic_homeland)))
cat(sprintf("Positive is_birthregion flags in restricted panel: %d (%.2f%% of obs)\n",
    sum(d$is_birthregion), 100 * mean(d$is_birthregion)))

cat("\n=== Build Archigos leader-spell clusters (HR-window convention) ===\n")
arch <- as.data.table(haven::read_dta("data/raw/archigos/Archigos_4.1.dta"))
arch[, startyear := as.integer(substr(startdate, 1, 4))]
arch[, endyear   := as.integer(substr(enddate,   1, 4))]
arch <- arch[!is.na(startyear) & !is.na(endyear)]
arch[, iso3 := suppressWarnings(countrycode::countrycode(ccode, "cown", "iso3c",
  custom_match = c("260" = "DEU", "340" = "SRB", "345" = "SRB", "678" = "YEM")))]
arch <- arch[!is.na(iso3)]

arch_yr <- arch[, {
  lo <- max(startyear, 1993L)
  hi <- min(endyear, 2013L)
  yrs <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yrs, iso3 = iso3)
}, by = .(obsid)]
arch_yr <- arch_yr[year %between% c(1993L, 2013L)]
setorder(arch_yr, iso3, year, obsid)
arch_yr <- unique(arch_yr, by = c("iso3", "year"))
setorder(arch_yr, iso3, year)
arch_yr[, spell_cluster := shift(obsid, 1L), by = iso3]
arch_yr[is.na(spell_cluster), spell_cluster := obsid]

d <- merge(d, arch_yr[, .(iso3, year, spell_cluster)], by = c("iso3", "year"), all.x = TRUE)
d[is.na(spell_cluster), spell_cluster := iso3]

setorder(d, gid_2, year)

cat("\n=== Regressions: Leader_t-1, region + country-year FE, Archigos clustering ===\n")
d_fe <- fixest::panel(d[!is.na(is_birthregion) & !is.na(is_ethnic_homeland)], ~gid_2 + year)

cat("Col(A): birth-region only (baseline, restricted sample)\n")
mA <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

cat("Col(B): ethnic-homeland only\n")
mB <- fixest::feols(ln_ntl ~ fixest::l(is_ethnic_homeland) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

cat("Col(C): both together (horse race)\n")
mC <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) + fixest::l(is_ethnic_homeland) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

cat("\n=== Results ===\n")
fixest::etable(mA, mB, mC,
  digits  = 3,
  keep    = c("is_birthregion", "is_ethnic_homeland"),
  headers = c("(A) Region only", "(B) Ethnicity only", "(C) Both")
)

cat("\n=== Comparison: full-sample birth-region baseline vs. restricted-sample versions ===\n")
d_full <- merge(d_full, arch_yr[, .(iso3, year, spell_cluster)], by = c("iso3", "year"), all.x = TRUE)
d_full[is.na(spell_cluster), spell_cluster := iso3]
d_full_fe <- fixest::panel(d_full[!is.na(is_birthregion)], ~gid_2 + year)
m_full_baseline <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
                                  data = d_full_fe, vcov = ~spell_cluster)
report <- function(m, label) {
  cn <- grep("is_birthregion|is_ethnic_homeland", names(coef(m)), value = TRUE)
  for (v in cn) {
    cf <- coef(m)[v]; se <- sqrt(diag(vcov(m)))[v]
    cat(sprintf("  %-45s %-25s %.3f (%.3f), N=%d\n", label, v, cf, se, nobs(m)))
  }
}
report(m_full_baseline, "Full 148-country sample, region only:")
report(mA, "94-country restricted, region only:")
report(mB, "94-country restricted, ethnicity only:")
report(mC, "94-country restricted, both together:")

saveRDS(list(mA = mA, mB = mB, mC = mC, m_full_baseline = m_full_baseline),
        "data/processed/ntl/ethnic_vs_regional_models.rds")
cat("\nSaved: data/processed/ntl/ethnic_vs_regional_models.rds\n")
