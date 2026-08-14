# 07_regression/table3/01_dynamics.R
# Replication of HR 2014 Table III: The Dynamics of Regional Favoritism.
# Data: our own GEE stable_lights panel (data/processed/analysis_panel.csv, canonical
#       since 2026-08-07) + PLAD leader spells + Archigos leader-spell clusters.
#
# HR 2014 Table III variables (see paper p. 1014, table notes):
#   Experience_ct     = years the political leader has been in power until year t
#   TotalTenure_ct    = total years the political leader was/will be in power
#   Future1_ict       = 1 if region i is birth region of the leader in t+1, but not in t
#   Future3_ict       = 1 if region i is birth region of the leader in t+1, t+2, or t+3, but not in t
#   Pretrend_ict      = time trend for years in which Future3_ict = 1
#   Past1_ict         = 1 if region i is birth region of the leader in t-1, but not in t
#   Past3_ict         = 1 if region i is birth region of the leader in t-1, t-2, or t-3, but not in t
#   Posttrend_ict     = time trend for years in which Past3_ict = 1
#
# NOTE on ambiguous column layout: HR's Table III text (5 columns) has some cell
# values that could not be unambiguously assigned to columns from the extracted
# PDF text. We reconstruct 5 columns with an interpretation consistent with the
# paper's narrative (placebo/pretrend test in col 2, Experience interaction in
# col 3, TotalTenure interaction in col 4, a combined specification in col 5):
#   (1) Leader_t-1 only (baseline)
#   (2) + Future3/Pretrend/Past3/Posttrend (placebo/pretrend test)
#   (3) + Leader_t-1 x Experience_t-1
#   (4) + Leader_t-1 x TotalTenure_t-1
#   (5) Leader_t-1 + placebo vars + Experience interaction (combined)
# TotalTenure convention: endyear - startyear + 1 (inclusive year count).

library(data.table)
library(fixest)
library(haven)
library(countrycode)

cat("=== Load analysis panel (canonical, stable_lights) ===\n")
d <- data.table::fread("data/processed/analysis_panel.csv")
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    nrow(d), uniqueN(d$gid_2), uniqueN(d$iso3)))

cat("\n=== Build Archigos leader-spell clusters (same as Table II tracks) ===\n")
arch <- data.table::as.data.table(haven::read_dta("data/raw/archigos/Archigos_4.1.dta"))
arch[, startyear := as.integer(substr(startdate, 1, 4))]
arch[, endyear   := as.integer(substr(enddate,   1, 4))]
arch <- arch[!is.na(startyear) & !is.na(endyear)]
arch[, iso3 := suppressWarnings(countrycode::countrycode(ccode, "cown", "iso3c"))]
arch <- arch[!is.na(iso3)]

arch_yr <- arch[, {
  yrs <- seq(max(startyear, 1992L), min(endyear, 2013L))
  if (length(yrs) == 0L) yrs <- integer(0)
  .(year = yrs, iso3 = iso3)
}, by = .(obsid)]
arch_yr <- arch_yr[year %between% c(1992L, 2013L)]
data.table::setorder(arch_yr, iso3, year, obsid)
arch_yr <- unique(arch_yr, by = c("iso3", "year"))
data.table::setorder(arch_yr, iso3, year)
arch_yr[, spell_cluster := data.table::shift(obsid, 1L), by = iso3]
arch_yr[is.na(spell_cluster), spell_cluster := obsid]

d <- merge(d, arch_yr[, .(iso3, year, spell_cluster)], by = c("iso3", "year"), all.x = TRUE)
d[is.na(spell_cluster), spell_cluster := iso3]

cat("\n=== Load PLAD leader spells ===\n")
plad <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]

# Apply GADM 3.6 -> 4.1 crosswalk (birth GIDs in PLAD are 3.6-flavored in some cases)
cw36 <- data.table::fread("data/processed/gadm36_41_crosswalk.csv")
plad[cw36, on = .(gid_2 = gid2_36), gid_2_41 := i.gid2_41]
plad[, birth_gid2 := data.table::fcase(!is.na(gid_2_41), gid_2_41, default = gid_2)]

spells <- unique(plad[, .(gid_0, leader, birth_gid2, startyear, endyear)])
spells[, totaltenure := endyear - startyear + 1L]
cat(sprintf("Spells: %d | countries: %d\n", nrow(spells), uniqueN(spells$gid_0)))

cat("\n=== Build country-year current-leader table (Experience, TotalTenure) ===\n")
spells[, spell_row := .I]
cur_leader <- spells[, {
  yrs <- seq(max(startyear, 1992L), min(endyear, 2013L))
  if (length(yrs) == 0L) yrs <- integer(0)
  .(year = yrs, startyear = startyear, endyear = endyear, totaltenure = totaltenure)
}, by = .(gid_0, spell_row)]
cur_leader <- cur_leader[year %between% c(1992L, 2013L)]
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
future_rows <- future_rows[year %between% c(1992L, 2013L)]
future_rows[, spell_row := NULL]
future_rows <- unique(future_rows, by = c("gid_2", "gid_0", "year"))

past_rows <- spells[, {
  yrs <- (endyear + 1L):(endyear + 3L)
  .(gid_2 = birth_gid2, gid_0 = gid_0, year = yrs,
    past3 = 1L, past1 = as.integer(yrs == endyear + 1L),
    posttrend = yrs - endyear)
}, by = .(spell_row)]
past_rows <- past_rows[year %between% c(1992L, 2013L)]
past_rows[, spell_row := NULL]
past_rows <- unique(past_rows, by = c("gid_2", "gid_0", "year"))

d <- merge(d, future_rows, by = c("gid_2", "gid_0", "year"), all.x = TRUE)
d <- merge(d, past_rows,   by = c("gid_2", "gid_0", "year"), all.x = TRUE)

for (v in c("future1", "future3", "pretrend", "past1", "past3", "posttrend")) {
  d[is.na(get(v)), (v) := 0]
}

# Per HR's definition: "but not in t" -- zero out placebo dummies where the
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

# Col(1): baseline
m1 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

# Col(2): + placebo/pretrend test
m2 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) + future3 + pretrend + past3 + posttrend
  | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

# Col(3): + Leader_t-1 x Experience_t-1
d_fe3 <- fixest::panel(d[!is.na(is_birthregion) & !is.na(experience_lag)], ~gid_2 + year)
m3 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) * experience_lag | gid_2 + gid_0^year,
  data = d_fe3, vcov = ~spell_cluster
)

# Col(4): + Leader_t-1 x TotalTenure_t-1
d_fe4 <- fixest::panel(d[!is.na(is_birthregion) & !is.na(totaltenure_lag)], ~gid_2 + year)
m4 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) * totaltenure_lag | gid_2 + gid_0^year,
  data = d_fe4, vcov = ~spell_cluster
)

# Col(5): combined -- Leader_t-1 + placebo vars + Experience interaction
d_fe5 <- fixest::panel(d[!is.na(is_birthregion) & !is.na(experience_lag)], ~gid_2 + year)
m5 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) * experience_lag +
    future3 + pretrend + past3 + posttrend
  | gid_2 + gid_0^year,
  data = d_fe5, vcov = ~spell_cluster
)

cat("\n=== TABLE III REPLICATION: THE DYNAMICS OF REGIONAL FAVORITISM ===\n")
fixest::etable(m1, m2, m3, m4, m5,
  digits  = 3,
  headers = c("(1) baseline", "(2) placebo", "(3) x Experience", "(4) x TotalTenure", "(5) combined")
)

cat("\n=== Comparison with HR 2014 Table III ===\n")
cat(sprintf("%-30s  %-18s  %-18s\n", "Coefficient", "HR 2014", "Our GEE"))
cat(strrep("-", 70), "\n")

get_coef <- function(m, term) {
  cf <- tryCatch(stats::coef(m)[term], error = function(e) NA)
  se <- tryCatch(sqrt(diag(stats::vcov(m)))[term], error = function(e) NA)
  if (is.na(cf)) return("--")
  sprintf("%.3f (%.3f)", cf, se)
}

cat(sprintf("%-30s  %-18s  %-18s\n", "Col1 Leader_t-1",
    "0.038** (0.016)", get_coef(m1, "fixest::l(is_birthregion)TRUE")))
cat(sprintf("%-30s  %-18s  %-18s\n", "Col2 Leader_t-1",
    "0.039* (0.021)", get_coef(m2, "fixest::l(is_birthregion)TRUE")))
cat(sprintf("%-30s  %-18s  %-18s\n", "Col3 Leader_t-1",
    "0.006 (0.024)", get_coef(m3, "fixest::l(is_birthregion)TRUE")))
cat(sprintf("%-30s  %-18s  %-18s\n", "Col3 Leader x Experience",
    "0.007*** (0.002)", get_coef(m3, "fixest::l(is_birthregion)TRUE:experience_lag")))
cat(sprintf("%-30s  %-18s  %-18s\n", "Col4 Leader_t-1",
    "0.003 (0.028)", get_coef(m4, "fixest::l(is_birthregion)TRUE")))
cat(sprintf("%-30s  %-18s  %-18s\n", "Col4 Leader x TotalTenure",
    "0.005*** (0.002)", get_coef(m4, "fixest::l(is_birthregion)TRUE:totaltenure_lag")))
cat(sprintf("%-30s  %-18s  %-18s\n", "Col5 Leader_t-1",
    "0.017 (0.028)", get_coef(m5, "fixest::l(is_birthregion)TRUE")))
cat(sprintf("%-30s  %-18s  %-18s\n", "Col5 Leader x Experience",
    "0.009*** (0.003)", get_coef(m5, "fixest::l(is_birthregion)TRUE:experience_lag")))
