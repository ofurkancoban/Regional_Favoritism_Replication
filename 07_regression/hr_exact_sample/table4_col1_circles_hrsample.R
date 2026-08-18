# 07_regression/table4/00_col1_circles.R
# HR 2014 Table IV Col(1): "very narrow geographical areas around the
# birthplace of each political leader" -- 5km-radius circles around each
# leader's birthplace point, clipped to national borders/coastlines
# (p. 1017). See 03_geometry/03_build_birthplace_circles.R for the geometry
# and 04_extraction/06_dmsp_birthplace_circles.R for the NTL extraction.
#
# HR 2014 exact-sample restriction test (2026-08-20): drop countries with
# avg population < 500,000 (HR's 126-country list) and circles whose
# centroid latitude is above 65N, matching HR's own stated exclusion
# criteria (p. 1001) -- same restriction already applied to the other
# hr_exact_sample/ scripts. Circles carry no gid_2/gid_1 of their own (they
# are built directly from PLAD birthplace point coordinates, not tied to an
# ADM2 polygon), so the latitude cutoff is computed directly from each
# circle's own centroid in birthplace_circles_5km.gpkg rather than reused
# from the ADM2/ADM1 exclusion lists.
#
# Spec: ln_ntl ~ l(is_birthregion_circle) | circle_id + gid_0^year,
#       vcov = ~spell_cluster -- identical structure to Table II Col(1),
#       just at the circle level instead of ADM2.
#
# HR 2014 Table IV Col(1): Leader_ict-1 = 0.049** (0.024), N=520 circles,
# 9,134 observations (126-country sample, 1992-2009).

library(data.table)
library(sf)
library(fixest)
library(haven)
library(countrycode)

years_rep <- 1992:2009

cat("=== Load birthplace-circle lookup and NTL panel ===\n")
lookup <- data.table::fread("data/processed/birthplace_circles_lookup.csv")
ntl <- data.table::fread("data/processed/ntl/dmsp_circles_panel.csv")
ntl <- ntl[year %in% years_rep]
cat(sprintf("Circles with NTL data: %d | country-years in lookup: %d\n",
    data.table::uniqueN(ntl$circle_id), nrow(lookup)))

cat("\n=== HR exact-sample restriction: 126-country list + >65N circles ===\n")
hr126 <- data.table::fread("data/raw/plad/hr2014_126_countries.csv")
sf::sf_use_s2(FALSE)
circ_geom <- sf::st_read("data/processed/birthplace_circles_5km.gpkg", quiet = TRUE)
cent <- suppressWarnings(sf::st_coordinates(sf::st_centroid(circ_geom)))
circ_above65n <- circ_geom$circle_id[cent[, 2] > 65]
cat(sprintf("Circles above 65N: %d\n", length(circ_above65n)))

ntl <- ntl[gid_0 %in% hr126$iso3]
ntl <- ntl[!circle_id %in% circ_above65n]
lookup <- lookup[iso3 %in% hr126$iso3]

cat("\n=== Expand lookup to country-year birth-circle map ===\n")
lookup[, spell_row := .I]
lookup_yr <- lookup[, {
  yr_seq <- seq(max(startyear, min(years_rep)), min(endyear, max(years_rep)))
  if (length(yr_seq) == 0) yr_seq <- integer(0)
  .(year = yr_seq, iso3 = iso3, circle_id = circle_id)
}, by = .(spell_row)]
lookup_yr <- lookup_yr[year %in% years_rep]
data.table::setorder(lookup_yr, iso3, year)
lookup_yr <- unique(lookup_yr, by = c("iso3", "year"))
data.table::setnames(lookup_yr, "circle_id", "birth_circle_id")
cat(sprintf("Country-years with a birth circle: %d (%d countries)\n",
    nrow(lookup_yr), data.table::uniqueN(lookup_yr$iso3)))

cat("\n=== Build circle-year panel (own-country circles only, leader-country-years only) ===\n")
panel <- ntl[, .(circle_id, gid_0, year, dmsp_ntl)]
panel <- merge(panel, lookup_yr[, .(iso3, year, birth_circle_id)],
               by.x = c("gid_0", "year"), by.y = c("iso3", "year"), all.x = TRUE)
panel <- panel[!is.na(birth_circle_id)]  # has_leader == 1 restriction, matching Col(1)-(3)

panel[, is_birthregion_circle := circle_id == birth_circle_id]
cat(sprintf("Panel: %d rows | %d circles | %d countries\n",
    nrow(panel), data.table::uniqueN(panel$circle_id), data.table::uniqueN(panel$gid_0)))
cat(sprintf("is_birthregion_circle = TRUE: %d circle-years\n", panel[is_birthregion_circle == TRUE, .N]))

panel[, ln_ntl := log(pmax(dmsp_ntl, 0) + 0.01)]

cat("\n=== Build Archigos leader-spell clusters ===\n")
arch <- data.table::as.data.table(haven::read_dta("data/raw/archigos/Archigos_4.1.dta"))
arch[, startyear := as.integer(substr(startdate, 1, 4))]
arch[, endyear   := as.integer(substr(enddate,   1, 4))]
arch <- arch[!is.na(startyear) & !is.na(endyear)]
arch[, iso3 := suppressWarnings(countrycode::countrycode(ccode, "cown", "iso3c",
  custom_match = c("260" = "DEU", "340" = "SRB", "345" = "SRB", "678" = "YEM")))]
arch <- arch[!is.na(iso3)]

arch_yr <- arch[, {
  lo <- max(startyear, min(years_rep))
  hi <- min(endyear, max(years_rep))
  yrs <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yrs, iso3 = iso3)
}, by = .(obsid)]
arch_yr <- arch_yr[year %in% years_rep]
data.table::setorder(arch_yr, iso3, year, obsid)
arch_yr <- unique(arch_yr, by = c("iso3", "year"))
data.table::setorder(arch_yr, iso3, year)
arch_yr[, spell_cluster := data.table::shift(obsid, 1L), by = iso3]
arch_yr[is.na(spell_cluster), spell_cluster := obsid]

panel <- merge(panel, arch_yr[, .(gid_0 = iso3, year, spell_cluster)], by = c("gid_0", "year"), all.x = TRUE)
panel[is.na(spell_cluster), spell_cluster := gid_0]

cat("\n=== Regression ===\n")
data.table::setorder(panel, circle_id, year)
d_fe <- fixest::panel(panel[is.finite(ln_ntl)], ~circle_id + year)
m1 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion_circle) | circle_id + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

fixest::etable(m1, digits = 3, headers = c("(1) 5km birthplace circles -- HRexact"))

cat("\n=== Comparison with HR 2014 Table IV ===\n")
cat("HR 2014 Col(1): Leader_t-1 = 0.049** (0.024), N=520 circles, 9,134 obs (126-country, 1992-2009 sample)\n")
cf1 <- stats::coef(m1)[1]; se1 <- sqrt(diag(stats::vcov(m1)))[1]
cat(sprintf("Our Col(1) 5km circles:  Leader_t-1 = %.3f (%.3f), N=%d circles, %d obs (%d-country, %d-%d sample)\n",
    cf1, se1, data.table::uniqueN(panel$circle_id), nobs(m1), data.table::uniqueN(panel$gid_0), min(years_rep), max(years_rep)))

out_dir <- "data/processed/ntl"
saveRDS(m1, file.path(out_dir, "table4_col1_circles_model_hrsample.rds"))
cat(sprintf("\nModel saved: %s\n", file.path(out_dir, "table4_col1_circles_model_hrsample.rds")))
