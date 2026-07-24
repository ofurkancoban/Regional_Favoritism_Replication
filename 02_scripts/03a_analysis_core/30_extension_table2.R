# ==============================================================================
# File:          30_extension_table2.R
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
# Description:   Re-estimates HR 2014 Table II Columns (1)-(7) over the full 1992-2023 harmonized DMSP/VIIRS panel, using this project's own GHS-POP population source throughout.
#
# Inputs:        01_datasets/processed/ntl/harmonized_dmsp_viirs_adm2_panel.csv, population_adm2_ghspop_interpolated.csv
# Outputs:       01_datasets/processed/extension_table2_coefs.csv, extension_table2_summary.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

years_rep <- 1992:2023

cat("=== Load harmonized NTL panel ===\n")
ntl <- data.table::fread(here::here("01_datasets/processed/ntl/harmonized_dmsp_viirs_adm2_panel.csv"))
ntl <- ntl[year %in% years_rep]
ntl_adm2 <- ntl[adm_level == "ADM2"]
ntl_adm1 <- ntl[adm_level == "ADM1" & !iso3 %in% ntl_adm2$iso3]
ntl <- rbind(ntl_adm2, ntl_adm1)
ntl[, gid_2 := region_id]
cat(sprintf("NTL: %d rows | %d regions | %d countries | years %d-%d\n",
    nrow(ntl), data.table::uniqueN(ntl$gid_2), data.table::uniqueN(ntl$iso3), min(ntl$year), max(ntl$year)))

cat("\n=== Expand PLAD (+ Wikidata supplement) to country-year, full 1992-2023 range ===\n")
plad <- data.table::fread(here::here("01_datasets/raw/plad/PLAD_April_2024.tab"), sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]
plad <- plad[is.na(foreign_leader) | foreign_leader != 1]

plad_yr <- plad[, {
  lo <- max(startyear, min(years_rep))
  hi <- min(endyear, max(years_rep))
  yr_seq <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yr_seq, gid_0 = gid_0, birth_gid2 = gid_2)
}, by = .(leader, plad_id)]
plad_yr <- plad_yr[year %in% years_rep]
cat(sprintf("PLAD leader-year rows: %d | countries: %d | max year: %d\n",
    nrow(plad_yr), data.table::uniqueN(plad_yr$gid_0), max(plad_yr$year)))

cat("\n=== Build birthplace flags (t0, t-1 via fixest::l(), t-2) ===\n")
birth_ry <- unique(plad_yr[, .(gid_2 = birth_gid2, iso3 = gid_0, year)])
ntl[, is_birthregion := FALSE]
ntl[birth_ry, on = .(gid_2, iso3, year), is_birthregion := TRUE]
ntl[plad_yr, on = .(iso3 = gid_0, year), has_leader := 1L]
ntl[is.na(has_leader), has_leader := 0L]
ntl <- unique(ntl, by = c("gid_2", "year"))
ntl[, gid_0 := iso3]

data.table::setorder(ntl, gid_2, year)
ntl[, ln_ntl    := log(pmax(harmonized_ntl, 0) + 0.01)]
ntl[, ln_ntl_00 := data.table::fifelse(harmonized_ntl > 0, log(harmonized_ntl), NA_real_)]
ntl[, leader_t0 := is_birthregion]
ntl[, leader_t2 := data.table::shift(is_birthregion, 2L), by = gid_2]
ntl[, ln_ntl_lag := data.table::shift(ln_ntl, 1L), by = gid_2]

cat("\n=== Merge our own GHS-POP lnpop (VPS-computed, DHR-style interpolated) ===\n")
pop <- data.table::fread(here::here("01_datasets/processed/population_adm2_ghspop_interpolated.csv"),
             select = c("GID_2", "year", "pop_count", "lnpop"))
data.table::setnames(pop, "GID_2", "gid_2")
pop <- pop[is.finite(lnpop)]
ntl <- merge(ntl, pop, by = c("gid_2", "year"), all.x = TRUE)
# UNIT FIX (2026-09-04): population_adm2_ghspop_interpolated.csv is
# internally inconsistent -- `pop_count` is in PERSONS (median ~24,700)
# while `lnpop` is already in THOUSANDS (median 3.21, i.e. ~25). Dividing
# light by pop_count in persons made the ratio ~1e-4, which the +0.01
# additive constant then swamped: the dependent variable's sd collapsed
# from 1.81 to 0.26 and Col(7) was driven to 0.0005 (p=0.49). HR 2014
# define Pop_ict as regional population in THOUSANDS, and the replication
# panel (analysis_panel.csv) follows that convention, which is why its
# own Col(7) was unaffected. Dividing by pop_count/1000 restores the
# intended scale and makes the ratio consistent with the lnpop control
# used alongside it.
ntl[, ln_ntlpc := log(pmax(harmonized_ntl, 0) / (pop_count / 1000) + 0.01)]
cat(sprintf("Rows with non-missing lnpop: %d / %d (%.1f%%)\n",
    sum(!is.na(ntl$lnpop)), nrow(ntl), 100 * mean(!is.na(ntl$lnpop))))

d <- ntl[has_leader == 1]
cat(sprintf("Panel: %d obs | %d regions | %d countries | years %d-%d\n",
    nrow(d), data.table::uniqueN(d$gid_2), data.table::uniqueN(d$iso3), min(d$year), max(d$year)))

cat("\n=== Clustering: country-level (matching the extension convention) ===\n")
d[, country_cluster := gid_0]

cat("\n=== Col(1): Baseline -- Leader_t-1, region + country-year FE ===\n")
d_fe <- fixest::panel(d[!is.na(is_birthregion)], ~gid_2 + year)
m1 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
  data = d_fe, vcov = ~country_cluster
)

cat("=== Col(2): Contemporaneous Leader_t ===\n")
m2 <- fixest::feols(
  ln_ntl ~ leader_t0 | gid_2 + gid_0^year,
  data = d_fe, vcov = ~country_cluster
)

cat("=== Col(3): 2-period lag Leader_t-2 ===\n")
m3 <- fixest::feols(
  ln_ntl ~ leader_t2 | gid_2 + gid_0^year,
  data = d_fe, vcov = ~country_cluster
)

cat("=== Col(4): + lagged light (dynamic panel), no population control ===\n")
# Matches HR 2014's own Table II Col(4): Pop_ict is blank in that column
# (see table2/02_track2_own.R's own verification note on this).
d_fe4 <- fixest::panel(d[!is.na(is_birthregion) & !is.na(ln_ntl_lag)], ~gid_2 + year)
m4 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) + ln_ntl_lag | gid_2 + gid_0^year,
  data = d_fe4, vcov = ~country_cluster
)

cat("=== Col(5): OLS -- lagged light, NO region FE ===\n")
d_fe5 <- fixest::panel(d[!is.na(is_birthregion) & !is.na(ln_ntl_lag)], ~gid_2 + year)
m5 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) + ln_ntl_lag | gid_0^year,
  data = d_fe5, vcov = ~country_cluster
)

cat("=== Col(6): Extensive margin Light0 (drops zero-light obs) ===\n")
d_fe6 <- fixest::panel(d[!is.na(is_birthregion) & is.finite(ln_ntl_00)], ~gid_2 + year)
m6 <- fixest::feols(
  ln_ntl_00 ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
  data = d_fe6, vcov = ~country_cluster
)

cat("=== Col(7): Per capita light + population control ===\n")
d_fe7 <- fixest::panel(d[!is.na(is_birthregion) & is.finite(ln_ntlpc) & !is.na(lnpop)], ~gid_2 + year)
m7 <- fixest::feols(
  ln_ntlpc ~ fixest::l(is_birthregion) + lnpop | gid_2 + gid_0^year,
  data = d_fe7, vcov = ~country_cluster
)

cat("\n=== EXTENSION -- TABLE II, COLUMNS (1)-(7), FULL 1992-2023 WINDOW ===\n")
fixest::etable(m1, m2, m3, m4, m5, m6, m7,
  digits  = 3,
  keep    = c("is_birthregion", "leader_t0", "leader_t2", "ln_ntl_lag", "lnpop"),
  headers = c("(1) Light", "(2) Light", "(3) Light", "(4) Light",
              "(5) Light", "(6) Light0", "(7) Lightpc")
)

saveRDS(list(m1 = m1, m2 = m2, m3 = m3, m4 = m4, m5 = m5, m6 = m6, m7 = m7),
        here::here("01_datasets/processed/ntl/extension_table2_cols1_7_models.rds"))
cat("\nSaved: data/processed/ntl/extension_table2_cols1_7_models.rds\n")

cat("\n=== Region-only-baseline within R2 (matching the deck's own convention) ===\n")
# fixest's own default within-R2 (demeaning by both region AND
# country-year FE) reports near-zero for these single-dummy specs, same
# issue already documented for the HR-window Table II/IV slides. Convention
# used throughout this deck: 1 - RSS(full model) / TSS(region-FE-only null),
# i.e. how much of the region-demeaned variance the full model explains.
# Column (5) has no region FE, so its own reported R2 (full model R2) is
# used instead, matching the existing convention.
region_only_r2 <- function(dd, yvar, region_var = "gid_2") {
  f <- as.formula(sprintf("%s ~ 1 | %s", yvar, region_var))
  null_m <- fixest::feols(f, data = dd)
  1 - deviance(null_m)
}

wr2 <- function(m, dd, yvar) {
  null_dev <- {
    f <- as.formula(sprintf("%s ~ 1 | gid_2", yvar))
    deviance(fixest::feols(f, data = dd))
  }
  1 - deviance(m) / null_dev
}

cat(sprintf("Col(1) within R2: %.3f\n", wr2(m1, d_fe[!is.na(is_birthregion)], "ln_ntl")))
cat(sprintf("Col(2) within R2: %.3f\n", wr2(m2, d_fe[!is.na(is_birthregion)], "ln_ntl")))
cat(sprintf("Col(3) within R2: %.3f\n", wr2(m3, d_fe[!is.na(is_birthregion) & !is.na(leader_t2)], "ln_ntl")))
cat(sprintf("Col(4) within R2: %.3f\n", wr2(m4, d_fe4[!is.na(is_birthregion) & !is.na(ln_ntl_lag)], "ln_ntl")))
cat(sprintf("Col(5) full R2 (no region FE): %.3f\n", fixest::r2(m5, "r2")))
cat(sprintf("Col(6) within R2: %.3f\n", wr2(m6, d_fe6[!is.na(is_birthregion) & is.finite(ln_ntl_00)], "ln_ntl_00")))
cat(sprintf("Col(7) within R2: %.3f\n", wr2(m7, d_fe7[!is.na(is_birthregion) & is.finite(ln_ntlpc) & !is.na(lnpop)], "ln_ntlpc")))

cat("\n=== Region counts per column ===\n")
cat(sprintf("Col(1) regions: %d\n", fixest::fixef(m1)$gid_2 |> length()))
cat(sprintf("Col(2) regions: %d\n", fixest::fixef(m2)$gid_2 |> length()))
cat(sprintf("Col(3) regions: %d\n", fixest::fixef(m3)$gid_2 |> length()))
cat(sprintf("Col(4) regions: %d\n", fixest::fixef(m4)$gid_2 |> length()))
cat(sprintf("Col(6) regions: %d\n", fixest::fixef(m6)$gid_2 |> length()))
cat(sprintf("Col(7) regions: %d\n", fixest::fixef(m7)$gid_2 |> length()))
cat(sprintf("Col(5) regions (no region FE, distinct gid_2 in sample): %d\n", data.table::uniqueN(d_fe5[!is.na(is_birthregion) & !is.na(ln_ntl_lag)]$gid_2)))

cat("\n=== Export coefs + summary CSVs (feeds paper.qmd's @tbl-extension) ===\n")
# n_regions here is data.table::uniqueN(gid_2) over each column's own estimation
# sample, the same convention as table2_own_hrsample.R's summary_rows --
# not fixest::fixef()'s post-fit level count (cat()'d above for reference
# only), which is far smaller because it reflects the fixed-effect levels
# fixest actually retains, not the sample's own region universe.
sig_of <- function(pv) ifelse(pv < 0.01, "***", ifelse(pv < 0.05, "**", ifelse(pv < 0.10, "*", "")))
extract_row <- function(m, var, col, row_label) {
  cft <- summary(m)$coeftable
  if (!var %in% rownames(cft)) return(NULL)
  data.table::data.table(
    row = row_label, col = col,
    b = cft[var, 1], se = cft[var, 2], sig = sig_of(cft[var, 4])
  )
}
coef_rows <- data.table::rbindlist(list(
  extract_row(m1, "fixest::l(is_birthregion)TRUE", 1, "Leader_t-1"),
  extract_row(m2, "leader_t0TRUE",                 2, "Leader_t"),
  extract_row(m3, "leader_t2TRUE",                 3, "Leader_t-2"),
  extract_row(m4, "fixest::l(is_birthregion)TRUE", 4, "Leader_t-1"),
  extract_row(m4, "ln_ntl_lag",                    4, "Light_t-1"),
  extract_row(m5, "fixest::l(is_birthregion)TRUE", 5, "Leader_t-1"),
  extract_row(m5, "ln_ntl_lag",                    5, "Light_t-1"),
  extract_row(m6, "fixest::l(is_birthregion)TRUE", 6, "Leader_t-1"),
  extract_row(m7, "fixest::l(is_birthregion)TRUE", 7, "Leader_t-1"),
  extract_row(m7, "lnpop",                         7, "Pop")
))
data.table::fwrite(coef_rows, here::here("01_datasets/processed/ntl/extension_table2_coefs.csv"))

summary_rows <- data.table::data.table(
  col = 1:7,
  b = coef_rows[row %in% c("Leader_t-1", "Leader_t", "Leader_t-2")][order(col)]$b,
  se = coef_rows[row %in% c("Leader_t-1", "Leader_t", "Leader_t-2")][order(col)]$se,
  sig = coef_rows[row %in% c("Leader_t-1", "Leader_t", "Leader_t-2")][order(col)]$sig,
  n_regions = c(
    data.table::uniqueN(d_fe[!is.na(is_birthregion)]$gid_2),
    data.table::uniqueN(d_fe[!is.na(is_birthregion)]$gid_2),
    data.table::uniqueN(d_fe[!is.na(is_birthregion) & !is.na(leader_t2)]$gid_2),
    data.table::uniqueN(d_fe4[!is.na(is_birthregion) & !is.na(ln_ntl_lag)]$gid_2),
    data.table::uniqueN(d_fe5[!is.na(is_birthregion) & !is.na(ln_ntl_lag)]$gid_2),
    data.table::uniqueN(d_fe6[!is.na(is_birthregion) & is.finite(ln_ntl_00)]$gid_2),
    data.table::uniqueN(d_fe7[!is.na(is_birthregion) & is.finite(ln_ntlpc) & !is.na(lnpop)]$gid_2)
  ),
  n_obs = c(nobs(m1), nobs(m2), nobs(m3), nobs(m4), nobs(m5), nobs(m6), nobs(m7)),
  within_r2 = round(c(
    wr2(m1, d_fe[!is.na(is_birthregion)], "ln_ntl"),
    wr2(m2, d_fe[!is.na(is_birthregion)], "ln_ntl"),
    wr2(m3, d_fe[!is.na(is_birthregion) & !is.na(leader_t2)], "ln_ntl"),
    wr2(m4, d_fe4[!is.na(is_birthregion) & !is.na(ln_ntl_lag)], "ln_ntl"),
    fixest::r2(m5, "r2"),
    wr2(m6, d_fe6[!is.na(is_birthregion) & is.finite(ln_ntl_00)], "ln_ntl_00"),
    wr2(m7, d_fe7[!is.na(is_birthregion) & is.finite(ln_ntlpc) & !is.na(lnpop)], "ln_ntlpc")
  ), 3)
)
data.table::fwrite(summary_rows, here::here("01_datasets/processed/ntl/extension_table2_summary.csv"))
cat("Saved: data/processed/ntl/extension_table2_coefs.csv, extension_table2_summary.csv\n")

cat("\n=== Export browsable HTML view (full table, matching paper.qmd's layout) ===\n")
ext_coefs <- coef_rows[, .(row, col, b, se, sig, source = "own")]

build_full_table_gt(
  coefs = ext_coefs,
  row_order = c("Leader_t-1", "Leader_t", "Leader_t-2", "Light_t-1", "Pop"),
  row_labels = c(
    "Leader_t-1" = "Leader<sub>ict-1</sub>", "Leader_t" = "Leader<sub>ict</sub>",
    "Leader_t-2" = "Leader<sub>ict-2</sub>", "Light_t-1" = "Light<sub>ict-1</sub>",
    "Pop" = "Pop<sub>ict</sub>"
  ),
  n_cols = 7,
  dv_spans = c("Light<sub>ict</sub>" = 5, "Light0<sub>ict</sub>" = 1, "Lightpc<sub>ict</sub>" = 1),
  shaded_cols = c(2, 4, 6),
  footer_rows = list(
    "Number of regions" = formatC(summary_rows$n_regions, format = "d", big.mark = ","),
    "Observations" = formatC(summary_rows$n_obs, format = "d", big.mark = ","),
    "Within R2" = sprintf("%.3f", summary_rows$within_r2)
  ),
  region_fe = c("Yes", "Yes", "Yes", "Yes", "No", "Yes", "Yes"),
  single_panel = TRUE,
  title = "Extension: Table II over 1992-2023",
  subtitle = "HR 2014's Table II Columns (1)-(7), re-estimated on the harmonized DMSP/VIIRS panel through 2023. Column (8) is not extended (G-Econ regional GDP does not cover the later window).",
  notes = "Standard errors, in parentheses, are clustered by country. *** p<0.01, ** p<0.05, * p<0.10.",
  file_name = "extension_table2.html"
)
