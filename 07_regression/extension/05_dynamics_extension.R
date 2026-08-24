# Purpose: HR 2014 Table III (Dynamics of Regional Favoritism) analog,
# extended to the full 1992-2023 window using the harmonized DMSP/VIIRS
# panel (Li et al. 2020) instead of the HR-window-only DMSP composite, and
# country-level clustering (per the project's formal convention for any
# work past Archigos 4.1's 2015 spell-coverage limit -- see
# RESEARCH_JOURNAL.md "Extension: harmonized panel... clustering
# convention decided").
#
# Same variable definitions as 07_regression/table3/01_dynamics.R
# (Experience, TotalTenure, Future1/Future3/Pretrend, Past1/Past3/
# Posttrend), just built over the extended year range and merged onto the
# harmonized-panel outcome instead of the HR-window-only DMSP composite.
library(data.table)
library(fixest)
library(haven)
library(countrycode)

years_rep <- 1992:2023

cat("=== Load harmonized NTL panel ===\n")
ntl <- fread("data/processed/ntl/harmonized_dmsp_viirs_adm2_panel.csv")
ntl <- ntl[year %in% years_rep]
ntl_adm2 <- ntl[adm_level == "ADM2"]
ntl_adm1 <- ntl[adm_level == "ADM1" & !iso3 %in% ntl_adm2$iso3]
ntl <- rbind(ntl_adm2, ntl_adm1)
ntl[, gid_2 := region_id]
ntl[, gid_0 := iso3]
ntl[, ln_ntl := log(pmax(harmonized_ntl, 0) + 0.01)]
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    nrow(ntl), uniqueN(ntl$gid_2), uniqueN(ntl$iso3)))

cat("\n=== Build birthplace flag from PLAD (+ Wikidata supplement) ===\n")
plad <- fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]
plad <- plad[is.na(foreign_leader) | foreign_leader != 1]
plad[, birth_gid2 := gid_2]

spells <- unique(plad[, .(gid_0, leader, birth_gid2, startyear, endyear)])
spells[, totaltenure := endyear - startyear + 1L]
spells[, spell_row := .I]
cat(sprintf("Spells: %d | countries: %d\n", nrow(spells), uniqueN(spells$gid_0)))

# Group by spell_row (one row per spell), not by (gid_0, leader) -- a
# leader can have multiple non-contiguous spells in PLAD, and grouping by
# (gid_0, leader) collapsed each such group's startyear/endyear/birth_gid2
# via implicit max/min recycling, silently producing empty or wrong
# year sequences for any leader with >1 spell row (root cause of Future3/
# Past3 both coming out entirely zero on the first attempt).
birth_ry <- spells[, {
  lo <- max(startyear, min(years_rep)); hi <- min(endyear, max(years_rep))
  yr_seq <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yr_seq, gid_2 = birth_gid2)
}, by = .(spell_row, gid_0)]
birth_ry <- unique(birth_ry[year %in% years_rep, .(gid_0, gid_2, year)])

ntl[, is_birthregion := FALSE]
ntl[birth_ry, on = .(gid_2, gid_0, year), is_birthregion := TRUE]

has_leader_cy <- spells[, {
  lo <- max(startyear, min(years_rep)); hi <- min(endyear, max(years_rep))
  yr_seq <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yr_seq)
}, by = .(spell_row, gid_0)]
has_leader_cy <- unique(has_leader_cy[year %in% years_rep, .(gid_0, year)])
ntl[has_leader_cy, on = .(gid_0, year), has_leader := 1L]
ntl[is.na(has_leader), has_leader := 0L]
ntl <- ntl[has_leader == 1]

cat("\n=== Experience / TotalTenure (current sitting leader per country-year) ===\n")
spells[, spell_row := .I]
cur_leader <- spells[, {
  lo <- max(startyear, min(years_rep)); hi <- min(endyear, max(years_rep))
  yrs <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yrs, startyear = startyear, totaltenure = totaltenure)
}, by = .(gid_0, spell_row)]
cur_leader <- cur_leader[year %in% years_rep]
setorder(cur_leader, gid_0, year)
cur_leader <- unique(cur_leader, by = c("gid_0", "year"))
cur_leader[, experience := year - startyear]

ntl <- merge(ntl, cur_leader[, .(gid_0, year, experience, totaltenure)], by = c("gid_0", "year"), all.x = TRUE)

cat("\n=== Future/Past placebo dummies ===\n")
setorder(spells, gid_0, startyear)
future_rows <- spells[, {
  yrs <- (startyear - 3L):(startyear - 1L)
  .(gid_2 = birth_gid2, gid_0 = gid_0, year = yrs,
    future3 = 1L, future1 = as.integer(yrs == startyear - 1L),
    pretrend = startyear - yrs)
}, by = .(spell_row)]
future_rows <- future_rows[year %in% years_rep]
future_rows[, spell_row := NULL]
future_rows <- unique(future_rows, by = c("gid_2", "gid_0", "year"))

past_rows <- spells[, {
  yrs <- (endyear + 1L):(endyear + 3L)
  .(gid_2 = birth_gid2, gid_0 = gid_0, year = yrs,
    past3 = 1L, past1 = as.integer(yrs == endyear + 1L),
    posttrend = yrs - endyear)
}, by = .(spell_row)]
past_rows <- past_rows[year %in% years_rep]
past_rows[, spell_row := NULL]
past_rows <- unique(past_rows, by = c("gid_2", "gid_0", "year"))

ntl <- merge(ntl, future_rows, by = c("gid_2", "gid_0", "year"), all.x = TRUE)
ntl <- merge(ntl, past_rows,   by = c("gid_2", "gid_0", "year"), all.x = TRUE)
for (v in c("future1", "future3", "pretrend", "past1", "past3", "posttrend")) {
  ntl[is.na(get(v)), (v) := 0]
}
ntl[is_birthregion == TRUE, `:=`(future1 = 0L, future3 = 0L, pretrend = 0,
                                   past1 = 0L, past3 = 0L, posttrend = 0)]
cat(sprintf("Future3=1: %d | Past3=1: %d region-years\n", ntl[future3 == 1, .N], ntl[past3 == 1, .N]))

cat("\n=== Clustering: country-level (extension convention) ===\n")
ntl[, country_cluster := gid_0]

setorder(ntl, gid_2, year)
ntl[, experience_lag  := shift(experience, 1L), by = gid_2]
ntl[, totaltenure_lag := shift(totaltenure, 1L), by = gid_2]

cat("\n=== Regressions ===\n")
d_fe <- fixest::panel(ntl[!is.na(is_birthregion)], ~gid_2 + year)

m1 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~country_cluster)

m2 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) + future1 + future3 + past1 + past3
                     | gid_2 + gid_0^year, data = d_fe, vcov = ~country_cluster)

d_fe3 <- fixest::panel(ntl[!is.na(is_birthregion) & !is.na(experience_lag)], ~gid_2 + year)
m3 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * experience_lag +
                       future3 + pretrend + past3 + posttrend
                     | gid_2 + gid_0^year, data = d_fe3, vcov = ~country_cluster)

d_fe4 <- fixest::panel(ntl[!is.na(is_birthregion) & !is.na(totaltenure_lag)], ~gid_2 + year)
m4 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * totaltenure_lag +
                       future3 + pretrend + past3 + posttrend
                     | gid_2 + gid_0^year, data = d_fe4, vcov = ~country_cluster)

d_fe5 <- fixest::panel(
  ntl[!is.na(is_birthregion) & !is.na(experience_lag) & !is.na(totaltenure_lag)], ~gid_2 + year)
m5 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * experience_lag +
                       fixest::l(is_birthregion) * totaltenure_lag +
                       future3 + pretrend + past3 + posttrend
                     | gid_2 + gid_0^year, data = d_fe5, vcov = ~country_cluster)

cat("\n=== TABLE III EXTENSION (1992-2023, harmonized panel, country-level clustering) ===\n")
fixest::etable(m1, m2, m3, m4, m5,
  digits  = 3,
  headers = c("(1) baseline", "(2) placebo", "(3) x Experience", "(4) x TotalTenure", "(5) combined")
)

saveRDS(list(m1 = m1, m2 = m2, m3 = m3, m4 = m4, m5 = m5),
        "data/processed/ntl/extension_table3_dynamics_models.rds")
cat("\nSaved: data/processed/ntl/extension_table3_dynamics_models.rds\n")
