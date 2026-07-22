# ==============================================================================
# File:          36_table3_dynamics.R
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
# Description:   Full replication of HR 2014 Table III (The Dynamics of
#                Regional Favoritism, p. 1014-1015) on the authors' exact
#                126-country, 1992-2009 sample. Column layout verified
#                directly against HR 2014's own Table III: Column (1) is
#                Leader_t-1 + a one-year placebo window (Future1, Past1);
#                Column (2) is Leader_t-1 + a three-year window (Future3,
#                Past3, Pretrend, Posttrend); Columns (3)-(5) add Leader x
#                Experience and/or Leader x TotalTenure interactions on
#                top of Column (2)'s specification.
#                Experience_ct = years the leader has been in power until
#                year t; TotalTenure_ct = total years the leader was/will
#                be in power (endyear - startyear + 1).
#
# Inputs:        01_datasets/processed/analysis_panel.csv,
#                01_datasets/raw/plad/hr2014_126_countries.csv,
#                01_datasets/processed/hr_excluded_above65n_regions.csv,
#                01_datasets/raw/archigos/Archigos_4.1.dta,
#                01_datasets/raw/plad/PLAD_April_2024.tab
# Outputs:       01_datasets/processed/ntl/table3_dynamics_models.rds,
#                01_datasets/processed/ntl/table3_dynamics_summary.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

years_hr <- 1992:2009

cat("=== Load analysis panel (canonical, stable_lights) ===\n")
d <- data.table::fread(here::here("01_datasets/processed/analysis_panel.csv"))
# HR 2014 exact-sample restriction: drop countries with avg population
# < 500,000 and ADM2 regions entirely above 65N latitude, matching HR's
# own stated exclusion criteria (p. 1001).
hr126 <- data.table::fread(here::here("01_datasets/raw/plad/hr2014_126_countries.csv"))
hr_65n <- data.table::fread(here::here("01_datasets/processed/hr_excluded_above65n_regions.csv"))
d <- d[iso3 %in% hr126$iso3]
d <- d[!gid_2 %in% hr_65n$gid_2]
d <- d[year %in% years_hr]
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    data.table::uniqueN(d$gid_2), nrow(d), data.table::uniqueN(d$iso3)))

cat("\n=== Build Archigos leader-spell clusters (same as Table II) ===\n")
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

cat("\n=== Load PLAD leader spells ===\n")
plad <- data.table::fread(here::here("01_datasets/raw/plad/PLAD_April_2024.tab"), sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]
# PLAD's own gid_2 field is native GADM 3.6, the same vintage the analysis
# panel's own gid_2 uses (Stage 10), so no crosswalk is needed here.
plad[, birth_gid2 := gid_2]

spells <- unique(plad[, .(gid_0, leader, birth_gid2, startyear, endyear)])
spells[, totaltenure := endyear - startyear + 1L]
cat(sprintf("Spells: %d | countries: %d\n", nrow(spells), data.table::uniqueN(spells$gid_0)))

cat("\n=== Build country-year current-leader table (Experience, TotalTenure) ===\n")
spells[, spell_row := .I]
cur_leader <- spells[, {
  lo <- max(startyear, 1992L)
  hi <- min(endyear, 2009L)
  yrs <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yrs, startyear = startyear, endyear = endyear, totaltenure = totaltenure)
}, by = .(gid_0, spell_row)]
cur_leader <- cur_leader[year %between% c(1992L, 2009L)]
data.table::setorder(cur_leader, gid_0, year)
cur_leader <- unique(cur_leader, by = c("gid_0", "year"))
cur_leader[, experience := year - startyear]

d <- merge(d, cur_leader[, .(gid_0, year, experience, totaltenure)],
           by = c("gid_0", "year"), all.x = TRUE)

cat("\n=== Build Future/Past placebo dummies (region-year level) ===\n")
data.table::setorder(spells, gid_0, startyear)

future_rows <- spells[, {
  yrs <- (startyear - 3L):(startyear - 1L)
  .(gid_2 = birth_gid2, gid_0 = gid_0, year = yrs,
    future3 = 1L, future1 = as.integer(yrs == startyear - 1L),
    pretrend = startyear - yrs)
}, by = .(spell_row)]
future_rows <- future_rows[year %between% c(1992L, 2009L)]
future_rows[, spell_row := NULL]
future_rows <- unique(future_rows, by = c("gid_2", "gid_0", "year"))

past_rows <- spells[, {
  yrs <- (endyear + 1L):(endyear + 3L)
  .(gid_2 = birth_gid2, gid_0 = gid_0, year = yrs,
    past3 = 1L, past1 = as.integer(yrs == endyear + 1L),
    posttrend = yrs - endyear)
}, by = .(spell_row)]
past_rows <- past_rows[year %between% c(1992L, 2009L)]
past_rows[, spell_row := NULL]
past_rows <- unique(past_rows, by = c("gid_2", "gid_0", "year"))

d <- merge(d, future_rows, by = c("gid_2", "gid_0", "year"), all.x = TRUE)
d <- merge(d, past_rows,   by = c("gid_2", "gid_0", "year"), all.x = TRUE)

for (v in c("future1", "future3", "pretrend", "past1", "past3", "posttrend")) {
  d[is.na(get(v)), (v) := 0]
}

# Per HR's definition, "but not in t": zero out placebo dummies where the
# region actually IS the birth region of the sitting leader that year.
d[is_birthregion == TRUE, `:=`(future1 = 0L, future3 = 0L, pretrend = 0,
                                 past1 = 0L, past3 = 0L, posttrend = 0)]

cat(sprintf("Future3=1: %d | Past3=1: %d region-years\n",
    d[future3 == 1, .N], d[past3 == 1, .N]))

cat("\n=== Build lags ===\n")
data.table::setorder(d, gid_2, year)
d[, experience_lag  := data.table::shift(experience, 1L), by = gid_2]
d[, totaltenure_lag := data.table::shift(totaltenure, 1L), by = gid_2]

cat("\n=== Regressions ===\n")
d_fe <- fixest::panel(d[!is.na(is_birthregion)], ~gid_2 + year)

# Col(1): Leader_t-1 + Future1 + Past1 (one-year placebo window)
m1 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) + future1 + past1
  | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

# Col(2): Leader_t-1 + Future3 + Past3 (three-year placebo window)
m2 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) + future3 + past3
  | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

# Col(3): + Leader_t-1 x Experience_t-1
d_fe3 <- fixest::panel(d[!is.na(is_birthregion) & !is.na(experience_lag)], ~gid_2 + year)
m3 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) * experience_lag +
    future3 + pretrend + past3 + posttrend
  | gid_2 + gid_0^year,
  data = d_fe3, vcov = ~spell_cluster
)

# Col(4): + Leader_t-1 x TotalTenure_t-1
d_fe4 <- fixest::panel(d[!is.na(is_birthregion) & !is.na(totaltenure_lag)], ~gid_2 + year)
m4 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) * totaltenure_lag +
    future3 + pretrend + past3 + posttrend
  | gid_2 + gid_0^year,
  data = d_fe4, vcov = ~spell_cluster
)

# Col(5): combined -- both interactions
d_fe5 <- fixest::panel(
  d[!is.na(is_birthregion) & !is.na(experience_lag) & !is.na(totaltenure_lag)], ~gid_2 + year)
m5 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) * experience_lag +
    fixest::l(is_birthregion) * totaltenure_lag +
    future3 + pretrend + past3 + posttrend
  | gid_2 + gid_0^year,
  data = d_fe5, vcov = ~spell_cluster
)

cat("\n=== TABLE III REPLICATION: THE DYNAMICS OF REGIONAL FAVORITISM ===\n")
fixest::etable(m1, m2, m3, m4, m5,
  digits  = 3,
  headers = c("(1) 1yr placebo", "(2) 3yr placebo", "(3) x Experience", "(4) x TotalTenure", "(5) combined")
)

cat("\n=== Summary stats (Number of regions, HR/Stata-convention Within R2) ===\n")
# HR/Stata xtreg-fe convention: 1 - deviance(m) / deviance(a null model
# with only the region fixed effect). NOT fixest::r2(m, "wr2"), which
# nets out region AND country-year FE from both model and null and is
# mechanically near-zero for a single binary regressor here.
wr2 <- function(m, dd) {
  null_dev <- stats::deviance(fixest::feols(ln_ntl ~ 1 | gid_2, data = dd))
  1 - stats::deviance(m) / null_dev
}
summary_rows <- data.table::data.table(
  col = 1:5,
  n_regions = c(
    data.table::uniqueN(d_fe$gid_2), data.table::uniqueN(d_fe$gid_2),
    data.table::uniqueN(d_fe3$gid_2), data.table::uniqueN(d_fe4$gid_2), data.table::uniqueN(d_fe5$gid_2)
  ),
  n_obs = c(stats::nobs(m1), stats::nobs(m2), stats::nobs(m3), stats::nobs(m4), stats::nobs(m5)),
  within_r2 = round(c(
    wr2(m1, d_fe), wr2(m2, d_fe), wr2(m3, d_fe3), wr2(m4, d_fe4), wr2(m5, d_fe5)
  ), 3)
)
print(summary_rows)

out_dir <- here::here("01_datasets/processed/ntl")
saveRDS(list(m1 = m1, m2 = m2, m3 = m3, m4 = m4, m5 = m5),
        file.path(out_dir, "table3_dynamics_models.rds"))
data.table::fwrite(summary_rows, file.path(out_dir, "table3_dynamics_summary.csv"))
cat(sprintf("\nModels saved: %s\n", file.path(out_dir, "table3_dynamics_models.rds")))
cat(sprintf("Summary saved: %s\n", file.path(out_dir, "table3_dynamics_summary.csv")))
