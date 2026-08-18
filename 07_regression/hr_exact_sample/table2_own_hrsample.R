# 07_regression/table2/02_track2_own.R
# Full replication of HR 2014 Table II using our own data sources.
# NTL:        GEE DMSP composite (our pipeline, R/07*)
# Birthregion: PLAD + spatial join (our pipeline, R/05*)
# Population: GPWv4 CIESIN via geodata (R/06b_gpw_population.R)
# RegGDP:     G-Econ 4.0 Nordhaus et al. 2006 (R/06_gecon_regional_gdp.R)
# Clusters:   Archigos 4.1 leader-spell (lagged 1 period, per HR 2014)
# Window:     1993-2013 (GEE DMSP availability)
#
# NOTE -- Col(8) data source deviation:
#   HR 2014 use Gennaioli et al. (2014) regional GDP, not publicly available.
#   Substituted with G-Econ 4.0 aggregated to ADM2. See project_col8_note.md.

library(data.table)
library(fixest)
library(haven)
library(countrycode)

cat("=== Load GEE analysis panel ===\n")
d <- data.table::fread("data/processed/analysis_panel.csv")
# HR 2014 exact-sample restriction test (2026-08-17): drop countries with
# avg population < 500,000 and ADM2 regions entirely above 65N latitude,
# matching HR's own stated exclusion criteria (p. 1001).
hr126 <- data.table::fread("data/raw/plad/hr2014_126_countries.csv")
hr_65n <- data.table::fread("data/processed/hr_excluded_above65n_regions.csv")
d <- d[iso3 %in% hr126$iso3]
d <- d[!gid_2 %in% hr_65n$gid_2]
d <- d[year %between% c(1992L, 2009L)]
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    nrow(d), uniqueN(d$gid_2), uniqueN(d$iso3)))

cat("\n=== Build Archigos leader-spell clusters ===\n")
arch <- data.table::as.data.table(haven::read_dta("data/raw/archigos/Archigos_4.1.dta"))
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
cat(sprintf("Spell clusters: %d\n", uniqueN(d$spell_cluster)))

cat("\n=== Prepare variables ===\n")
data.table::setorder(d, gid_2, year)

# ln_ntl already = log(dmsp_ntl + 0.01) -- Light_ict
# ln_ntl_00 = log(dmsp_ntl) -- Light0_ict (extensive margin, NA when dmsp_ntl=0)
# ln_ntlpc already = log(dmsp_ntl / exp(lnpop) + 0.01) -- Lightpc_ict

d[, leader_t0  := is_birthregion]
d[, leader_t2  := data.table::shift(is_birthregion, 2L), by = gid_2]
d[, ln_ntl_lag := data.table::shift(ln_ntl, 1L), by = gid_2]

cat("\n=== Col(1): Baseline -- Leader_t-1, region + country-year FE ===\n")
d_fe <- fixest::panel(d[!is.na(is_birthregion)], ~gid_2 + year)
m1 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
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
  d[!is.na(is_birthregion) & !is.na(ln_ntl_lag)], ~gid_2 + year)
m4 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) + ln_ntl_lag | gid_2 + gid_0^year,
  data = d_fe4, vcov = ~spell_cluster
)

cat("=== Col(5): OLS -- lagged light, NO region FE ===\n")
d_fe5 <- fixest::panel(
  d[!is.na(is_birthregion) & !is.na(ln_ntl_lag)], ~gid_2 + year)
m5 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) + ln_ntl_lag | gid_0^year,
  data = d_fe5, vcov = ~spell_cluster
)

cat("=== Col(6): Extensive margin Light0 (drops zero-light obs) ===\n")
d_fe6 <- fixest::panel(
  d[!is.na(is_birthregion) & is.finite(ln_ntl_00)], ~gid_2 + year)
m6 <- fixest::feols(
  ln_ntl_00 ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
  data = d_fe6, vcov = ~spell_cluster
)

cat("=== Col(7): Per capita light + pop control ===\n")
d_fe7 <- fixest::panel(
  d[!is.na(is_birthregion) & !is.na(ln_ntlpc) & !is.na(lnpop)], ~gid_2 + year)
m7 <- fixest::feols(
  ln_ntlpc ~ fixest::l(is_birthregion) + lnpop | gid_2 + gid_0^year,
  data = d_fe7, vcov = ~spell_cluster
)

cat("=== Col(8): Regional GDP (G-Econ 4.0 proxy) ===\n")
gdp <- data.table::fread("data/processed/regional_gdp_panel.csv")
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
  d[, .(gid_base, gid_2, gid_0 = iso3, year, is_birthregion, lnpop, spell_cluster)],
  by = c("gid_base", "year"), all.x = TRUE
)
gdp_d <- gdp_d[!is.na(is_birthregion) & !is.na(lnpop)]
gdp_d <- merge(gdp_d, arch_yr[, .(iso3, year, spell_cluster_arch = spell_cluster)],
               by.x = c("gid_0","year"), by.y = c("iso3","year"), all.x = TRUE)
gdp_d[is.na(spell_cluster), spell_cluster := gid_0]
d_fe8 <- fixest::panel(gdp_d, ~GID_2 + year)
m8 <- fixest::feols(
  ln_rgdppc ~ fixest::l(is_birthregion) + lnpop | GID_2 + GID_0^year,
  data = d_fe8, vcov = ~spell_cluster
)

cat("\n=== OUR DATA -- HR 2014 TABLE II REPLICATION (all 8 columns) ===\n")
fixest::etable(m1, m2, m3, m4, m5, m6, m7, m8,
  digits  = 3,
  keep    = c("is_birthregion", "leader_t0", "leader_t2", "ln_ntl_lag", "lnpop"),
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
  sig <- ifelse(pv<0.001,"***",ifelse(pv<0.01,"**",ifelse(pv<0.05,"*",ifelse(pv<0.1,".",""))))
  same_dir <- sign(cf) == sign(b$hr_b)
  cat(sprintf("%-22s  %.3f (%.3f)***    %.3f (%.3f)%-3s  %s\n",
      b$col, b$hr_b, b$hr_se, cf, se, sig,
      ifelse(same_dir & sig != "", "OK", "CHECK")))
}
cat("\n* Col(8) deviation: G-Econ 4.0 proxy used instead of Gennaioli et al. (2014).\n")
