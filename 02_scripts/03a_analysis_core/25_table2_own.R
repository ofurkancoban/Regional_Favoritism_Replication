# ==============================================================================
# File:          25_table2_own.R
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
# Description:   Full replication of HR 2014 Table II (all eight columns) on the authors' exact 126-country, 1992-2009 sample, with the boundary-lag fix applied to every lagged column.
#
# Inputs:        01_datasets/processed/analysis_panel.csv, reference_data/
# Outputs:       01_datasets/processed/table2_full_coefs_hrsample.csv, table2_full_summary_hrsample.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

cat("=== Load GEE analysis panel ===\n")
d <- data.table::fread(here::here("01_datasets/processed/analysis_panel.csv"))
# HR 2014 exact-sample restriction test (2026-08-17): drop countries with
# avg population < 500,000 and ADM2 regions entirely above 65N latitude,
# matching HR's own stated exclusion criteria (p. 1001).
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

d <- merge(d, arch_yr[, .(iso3, year, spell_cluster)],
           by = c("iso3", "year"), all.x = TRUE)
d[is.na(spell_cluster), spell_cluster := iso3]
cat(sprintf("Spell clusters: %d\n", data.table::uniqueN(d$spell_cluster)))

cat("\n=== Build 1991 birth-region flag (boundary-lag fix, 2026-09-03) ===\n")
# The 1992-2009 window's first year, 1992, needs 1991 to build Leader_ict-1.
# HR 2014 do not drop 1992 from any lagged column (their own Leaderict-1
# obs. count is identical to Lightict's, see Section 3.5), because Archigos
# and PLAD record leader tenure and birthplace for years before 1992 too, so
# the 1991 lag can be built without needing 1991 light data. This script
# previously left 1992's lag as NA (dropped), same bug class fixed in
# 02_track2_own.R's window filter, just at the other boundary (1992 itself,
# not 1993). Fixed the same way: build the 1991 birth-region flag
# independently from PLAD + the Wikidata supplement and use it to fill 1992.
plad_raw <- data.table::fread(here::here("01_datasets/raw/plad/PLAD_April_2024.tab"), sep = "\t")
plad_raw <- plad_raw[!is.na(gid_2) & gid_2 != "." & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]
plad_raw <- plad_raw[is.na(foreign_leader) | foreign_leader != 1]
plad_1991 <- plad_raw[startyear <= 1991 & endyear >= 1991,
                       .(gid_2 = gid_2, iso3 = gid_0)]
wd_supp <- data.table::fread(here::here("01_datasets/processed/wikidata_supplement_birthplaces.csv"))
wd_1991 <- wd_supp[startyear <= 1991 & endyear >= 1991,
                    .(gid_2 = birth_gid2, iso3)]
birth_1991 <- unique(rbind(plad_1991, wd_1991))
cat(sprintf("1991 birth regions: %d (across %d countries)\n",
    nrow(birth_1991), data.table::uniqueN(birth_1991$iso3)))

cat("\n=== Prepare variables ===\n")
data.table::setorder(d, gid_2, year)

# ln_ntl already = log(dmsp_ntl + 0.01) -- Light_ict
# ln_ntl_00 = log(dmsp_ntl) -- Light0_ict (extensive margin, NA when dmsp_ntl=0)
# ln_ntlpc already = log(dmsp_ntl / exp(lnpop) + 0.01) -- Lightpc_ict

d[, leader_t0  := is_birthregion]
d[, leader_t1  := data.table::shift(is_birthregion, 1L), by = gid_2]
d[year == 1992, leader_t1 := gid_2 %in% birth_1991$gid_2]
d[, leader_t2  := data.table::shift(is_birthregion, 2L), by = gid_2]
d[, ln_ntl_lag := data.table::shift(ln_ntl, 1L), by = gid_2]

n_before_fix <- sum(!is.na(d[, data.table::shift(is_birthregion, 1L), by = gid_2]$V1))
cat(sprintf("Leader_t-1 non-NA before fix (1992 left NA): %d | after fix: %d\n",
    n_before_fix, sum(!is.na(d$leader_t1))))

cat("\n=== Col(1): Baseline -- Leader_t-1, region + country-year FE ===\n")
d_fe <- fixest::panel(d[!is.na(is_birthregion)], ~gid_2 + year)
m1 <- fixest::feols(
  ln_ntl ~ leader_t1 | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

cat("=== Col(2): Contemporaneous Leader_t ===\n")
m2 <- fixest::feols(
  ln_ntl ~ leader_t0 | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

cat("=== Col(3): 2-period lag Leader_t-2 ===\n")
m3 <- fixest::feols(
  ln_ntl ~ leader_t2 | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

cat("=== Col(4): + lagged light (dynamic panel) ===\n")
# HR 2014 Table II (p. 1010): Pop_ict's row is blank under column (4) --
# verified by precise character-position alignment of the table's PDF text
# against the header row's column markers (Pop_ict's coefficient 0.958***
# aligns to column 7, not column 4). No population control here. This copy
# had fallen out of sync with the fix already applied to
# 07_regression/table2/02_track2_own.R -- synced 2026-08-20.
d_fe4 <- fixest::panel(
  d[!is.na(leader_t1) & !is.na(ln_ntl_lag)], ~gid_2 + year)
m4 <- fixest::feols(
  ln_ntl ~ leader_t1 + ln_ntl_lag | gid_2 + gid_0^year,
  data = d_fe4, vcov = ~spell_cluster
)

cat("=== Col(5): OLS -- lagged light, NO region FE ===\n")
d_fe5 <- fixest::panel(
  d[!is.na(leader_t1) & !is.na(ln_ntl_lag)], ~gid_2 + year)
m5 <- fixest::feols(
  ln_ntl ~ leader_t1 + ln_ntl_lag | gid_0^year,
  data = d_fe5, vcov = ~spell_cluster
)

cat("=== Col(6): Extensive margin Light0 (drops zero-light obs) ===\n")
d_fe6 <- fixest::panel(
  d[!is.na(leader_t1) & is.finite(ln_ntl_00)], ~gid_2 + year)
m6 <- fixest::feols(
  ln_ntl_00 ~ leader_t1 | gid_2 + gid_0^year,
  data = d_fe6, vcov = ~spell_cluster
)

cat("=== Col(7): Per capita light + pop control ===\n")
d_fe7 <- fixest::panel(
  d[!is.na(leader_t1) & !is.na(ln_ntlpc) & !is.na(lnpop)], ~gid_2 + year)
m7 <- fixest::feols(
  ln_ntlpc ~ leader_t1 + lnpop | gid_2 + gid_0^year,
  data = d_fe7, vcov = ~spell_cluster
)

cat("=== Col(8): Regional GDP (G-Econ 4.0 proxy) ===\n")
gdp <- data.table::fread(here::here("01_datasets/processed/regional_gdp_panel.csv"))
gdp <- gdp[!is.na(ln_rgdppc) & is.finite(ln_rgdppc)]
gdp[, gid_base := sub("_[0-9]+$", "", GID_2)]
d[,   gid_base := sub("_[0-9]+$", "", gid_2)]

# HR 2014 Table II (p. 1010): Pop_ict's row DOES have a coefficient under
# column (8) (0.201***) -- verified by the same character-position
# alignment check as Col(4) above. This copy had fallen out of sync with
# the fix already applied to 07_regression/table2/02_track2_own.R --
# synced 2026-08-20.
gdp_d <- merge(
  gdp[, .(gid_base = sub("_[0-9]+$","",GID_2), GID_2, GID_0, year, ln_rgdppc)],
  d[, .(gid_base, gid_2, gid_0 = iso3, year, leader_t1, lnpop, spell_cluster)],
  by = c("gid_base", "year"), all.x = TRUE
)
gdp_d <- gdp_d[!is.na(leader_t1) & !is.na(lnpop)]
gdp_d <- merge(gdp_d, arch_yr[, .(iso3, year, spell_cluster_arch = spell_cluster)],
               by.x = c("gid_0","year"), by.y = c("iso3","year"), all.x = TRUE)
gdp_d[is.na(spell_cluster), spell_cluster := gid_0]
d_fe8 <- fixest::panel(gdp_d, ~GID_2 + year)
m8 <- fixest::feols(
  ln_rgdppc ~ leader_t1 + lnpop | GID_2 + GID_0^year,
  data = d_fe8, vcov = ~spell_cluster
)

cat("\n=== OUR DATA -- HR 2014 TABLE II REPLICATION (all 8 columns) ===\n")
fixest::etable(m1, m2, m3, m4, m5, m6, m7, m8,
  digits  = 3,
  keep    = c("leader_t1", "leader_t0", "leader_t2", "ln_ntl_lag", "lnpop"),
  headers = c("(1) Light", "(2) Light", "(3) Light", "(4) Light",
              "(5) Light", "(6) Light0", "(7) Lightpc", "(8) RegGDP*")
)
cat("* Col(8): G-Econ 4.0 proxy (Nordhaus et al. 2006). HR 2014 used Gennaioli et al. (2014).\n")

cat("\n=== Comparison with HR 2014 Table II ===\n")
hr_bench <- list(
  list(col="(1) Leader_t-1",        hr_b=0.038, hr_se=0.014, m=m1, var=1),
  list(col="(2) Leader_t",          hr_b=0.039, hr_se=0.015, m=m2, var=1),
  list(col="(3) Leader_t-2",        hr_b=0.041, hr_se=0.013, m=m3, var=1),
  list(col="(4) +lag light      ",   hr_b=0.019, hr_se=0.010, m=m4, var=1),
  list(col="(5) OLS no region FE",  hr_b=0.061, hr_se=0.010, m=m5, var=1),
  list(col="(6) Extensive margin",  hr_b=0.029, hr_se=0.013, m=m6, var=1),
  list(col="(7) Per capita light",  hr_b=0.062, hr_se=0.024, m=m7, var=1),
  list(col="(8) Regional GDP*",     hr_b=0.021, hr_se=0.006, m=m8, var=1)
)

cat(sprintf("%-22s  %-16s  %-16s  %s\n", "Column", "HR 2014", "Our GEE", "Dir."))
cat(strrep("-", 72), "\n")
for (b in hr_bench) {
  cf  <- stats::coef(b$m)[b$var]
  se  <- sqrt(diag(stats::vcov(b$m)))[b$var]
  pv  <- summary(b$m)$coeftable[b$var, 4]
  sig <- ifelse(pv<0.01,"***",ifelse(pv<0.05,"**",ifelse(pv<0.10,"*","")))
  same_dir <- sign(cf) == sign(b$hr_b)
  cat(sprintf("%-22s  %.3f (%.3f)***    %.3f (%.3f)%-3s  %s\n",
      b$col, b$hr_b, b$hr_se, cf, se, sig,
      ifelse(same_dir & sig != "", "OK", "CHECK")))
}
cat("\n* Col(8) deviation: G-Econ 4.0 proxy used instead of Gennaioli et al. (2014).\n")

cat("\n=== Saving Table II comparison to CSV (HR-exact sample) ===\n")
out_rows <- lapply(hr_bench, function(b) {
  cf  <- stats::coef(b$m)[b$var]
  se  <- sqrt(diag(stats::vcov(b$m)))[b$var]
  pv  <- summary(b$m)$coeftable[b$var, 4]
  sig <- ifelse(pv<0.01,"***",ifelse(pv<0.05,"**",ifelse(pv<0.10,"*","")))
  data.table::data.table(
    col = b$col, hr_b = b$hr_b, hr_se = b$hr_se,
    our_b = unname(cf), our_se = unname(se), our_sig = sig, our_n = nobs(b$m)
  )
})
out_dt <- data.table::rbindlist(out_rows)
data.table::fwrite(out_dt, here::here("01_datasets/processed/ntl/table2_comparison_hrsample.csv"))

hr_full <- list(
  list(row = "Leader_t-1",  col = 1, b = 0.038, se = 0.014, sig = "***"),
  list(row = "Leader_t",    col = 2, b = 0.039, se = 0.015, sig = "***"),
  list(row = "Leader_t-2",  col = 3, b = 0.041, se = 0.013, sig = "***"),
  list(row = "Leader_t-1",  col = 4, b = 0.019, se = 0.010, sig = "***"),
  list(row = "Light_t-1",   col = 4, b = 0.400, se = 0.023, sig = "***"),
  list(row = "Leader_t-1",  col = 5, b = 0.061, se = 0.010, sig = "***"),
  list(row = "Light_t-1",   col = 5, b = 0.962, se = 0.004, sig = "***"),
  list(row = "Leader_t-1",  col = 6, b = 0.029, se = 0.013, sig = "***"),
  list(row = "Leader_t-1",  col = 7, b = 0.062, se = 0.024, sig = "***"),
  list(row = "Pop",         col = 7, b = 0.958, se = 0.066, sig = "***"),
  list(row = "Leader_t-1",  col = 8, b = 0.021, se = 0.006, sig = "***"),
  list(row = "Pop",         col = 8, b = 0.201, se = 0.049, sig = "***")
)
hr_full_dt <- data.table::rbindlist(lapply(hr_full, as.data.table))
hr_full_dt[, source := "hr"]

extract_row <- function(m, var, col, row_label) {
  cft <- summary(m)$coeftable
  if (!var %in% rownames(cft)) return(NULL)
  b <- cft[var, 1]; se <- cft[var, 2]; pv <- cft[var, 4]
  sig <- ifelse(pv<0.01,"***",ifelse(pv<0.05,"**",ifelse(pv<0.10,"*","")))
  data.table::data.table(row = row_label, col = col, b = round(b,3), se = round(se,3), sig = sig)
}
own_full <- data.table::rbindlist(list(
  extract_row(m1, "leader_t1TRUE", 1, "Leader_t-1"),
  extract_row(m2, "leader_t0TRUE",                 2, "Leader_t"),
  extract_row(m3, "leader_t2TRUE",                 3, "Leader_t-2"),
  extract_row(m4, "leader_t1TRUE", 4, "Leader_t-1"),
  extract_row(m4, "ln_ntl_lag",                    4, "Light_t-1"),
  extract_row(m5, "leader_t1TRUE", 5, "Leader_t-1"),
  extract_row(m5, "ln_ntl_lag",                    5, "Light_t-1"),
  extract_row(m6, "leader_t1TRUE", 6, "Leader_t-1"),
  extract_row(m7, "leader_t1TRUE", 7, "Leader_t-1"),
  extract_row(m7, "lnpop",                         7, "Pop"),
  extract_row(m8, "leader_t1TRUE", 8, "Leader_t-1"),
  extract_row(m8, "lnpop",                         8, "Pop")
))
own_full[, source := "own"]

coef_rows <- data.table::rbindlist(list(hr_full_dt, own_full), use.names = TRUE)
data.table::fwrite(coef_rows, here::here("01_datasets/processed/ntl/table2_full_coefs_hrsample.csv"))

# Within R2, HR/Stata xtreg-fe convention: 1 - deviance(m) / deviance(a null
# model with only the region fixed effect). This is NOT fixest::r2(m,"wr2"),
# which nets out every fixed effect (region AND country-year) from both the
# model and the null, and is mechanically near zero for a single binary
# regressor once the much larger country-year FE set already explains most
# of the variance. Matches the convention already used for the presentation
# and the extension script (07_regression/extension/07_table2_extension_cols1_7.R).
wr2 <- function(m, dd, yvar, unit = "gid_2") {
  null_dev <- {
    f <- as.formula(sprintf("%s ~ 1 | %s", yvar, unit))
    stats::deviance(fixest::feols(f, data = dd))
  }
  1 - stats::deviance(m) / null_dev
}

summary_rows <- data.table::data.table(
  col = 1:8,
  n_regions = c(data.table::uniqueN(d_fe$gid_2), data.table::uniqueN(d_fe$gid_2), data.table::uniqueN(d_fe$gid_2),
                data.table::uniqueN(d_fe4$gid_2), data.table::uniqueN(d_fe5$gid_2), data.table::uniqueN(d_fe6$gid_2),
                data.table::uniqueN(d_fe7$gid_2), data.table::uniqueN(d_fe8$GID_2)),
  n_obs = c(nobs(m1), nobs(m2), nobs(m3), nobs(m4), nobs(m5), nobs(m6), nobs(m7), nobs(m8)),
  within_r2 = round(c(
    wr2(m1, d_fe[!is.na(leader_t1)], "ln_ntl"),
    wr2(m2, d_fe[!is.na(leader_t0)], "ln_ntl"),
    wr2(m3, d_fe[!is.na(leader_t2)], "ln_ntl"),
    wr2(m4, d_fe4, "ln_ntl"),
    fixest::r2(m5, "r2"), # no region FE in Col(5); full R2 instead of within R2
    wr2(m6, d_fe6, "ln_ntl_00"),
    wr2(m7, d_fe7, "ln_ntlpc"),
    wr2(m8, d_fe8, "ln_rgdppc", unit = "GID_2")
  ), 3),
  region_fe = c("Yes","Yes","Yes","Yes","No","Yes","Yes","Yes")
)
data.table::fwrite(summary_rows, here::here("01_datasets/processed/ntl/table2_full_summary_hrsample.csv"))
cat("Saved: data/processed/ntl/table2_comparison_hrsample.csv, table2_full_coefs_hrsample.csv, table2_full_summary_hrsample.csv\n")

cat("\n=== Export browsable HTML view (full table, matching paper.qmd's layout) ===\n")
# HR 2014's own published footer numbers (p. 995-1033), the same reference
# values paper.qmd hardcodes in its own Table II chunk -- these have no
# source CSV of their own since they are the authors' fixed, published
# numbers, not something this pipeline computes.
hr_footer <- data.table::data.table(
  col = 1:8,
  n_regions = c(38427, 38427, 38427, 38427, 38427, 36591, 37475, 1207),
  n_obs     = c(690495, 690495, 689870, 652362, 652362, 619594, 673382, 14995),
  within_r2 = c(0.319, 0.319, 0.318, 0.412, 0.964, 0.393, 0.197, 0.653)
)
own_footer <- summary_rows[, .(col, n_regions, n_obs, within_r2)]

int_footer_row <- function(field) {
  data.table::data.table(
    col = hr_footer$col,
    hr = formatC(hr_footer[[field]], format = "d", big.mark = ","),
    own = formatC(own_footer[[field]], format = "d", big.mark = ",")
  )
}

build_full_table_gt(
  coefs = coef_rows,
  row_order = c("Leader_t-1", "Leader_t", "Leader_t-2", "Light_t-1", "Pop"),
  row_labels = c(
    "Leader_t-1" = "Leader<sub>ict-1</sub>", "Leader_t" = "Leader<sub>ict</sub>",
    "Leader_t-2" = "Leader<sub>ict-2</sub>", "Light_t-1" = "Light<sub>ict-1</sub>",
    "Pop" = "Pop<sub>ict</sub>"
  ),
  n_cols = 8,
  dv_spans = c("Light<sub>ict</sub>" = 5, "Light0<sub>ict</sub>" = 1,
               "Lightpc<sub>ict</sub>" = 1, "RegionalGDP<sub>ict</sub>" = 1),
  shaded_cols = c(2, 4, 6, 8),
  footer_rows = list(
    "Number of regions" = int_footer_row("n_regions"),
    "Observations" = int_footer_row("n_obs"),
    "Within R2" = data.table::data.table(
      col = hr_footer$col,
      hr = sprintf("%.3f", hr_footer$within_r2),
      own = sprintf("%.3f", own_footer$within_r2)
    )
  ),
  region_fe = c("Yes", "Yes", "Yes", "Yes", "No", "Yes", "Yes", "Yes"),
  title = "Table II Replication",
  subtitle = "HR 2014's Table II, all eight columns, on the authors' exact 126-country, 1992-2009 sample.",
  notes = "Fixed-effect regressions, except Column (5) (standard OLS). Standard errors, in parentheses, are clustered by leader spell, lagged one period. *** p<0.01, ** p<0.05, * p<0.10.",
  file_name = "table2_full_hrsample.html"
)
