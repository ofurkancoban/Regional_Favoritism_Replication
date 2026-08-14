# 07_regression/table4/01_col23_holepunch.R
# HR 2014 Table IV Col(2)-(3): SN1 (ADM1) regions, full-area and with NTL
# averaged only over the SN2 sub-regions that were NEVER the birth region
# of any leader in our PLAD sample ("we omit all SN2 regions in which a
# political leader from our sample was ever born", p. 1018).
#
# Both NTL sources are local extractions (exactextractr, no GEE) --
# 04_extraction/02_dmsp_adm1_full.R (Col 2 baseline) and
# 04_extraction/03_dmsp_adm1_holepunched.R (Col 3, hole-punched geometry
# from 03_geometry/02_build_holepunched_adm1.R: birth ADM2 sub-polygons
# geometrically removed via st_difference, full precision, no simplification).
#
# Only 556 of 3,153 ADM1 regions actually contain an ever-birth ADM2 and
# needed hole-punching; all others are identical to the Col(2) full-area
# value and are taken directly from data/processed/ntl/dmsp_adm1_panel.csv.

library(data.table)
library(fixest)
library(haven)
library(countrycode)

cat("=== Load canonical ADM2 panel (for birth-region flags and gid_1 universe) ===\n")
d2 <- data.table::fread("data/processed/analysis_panel.csv")
d2 <- d2[year %between% c(1992L, 2013L)]
d2[, birth_gid1 := data.table::fcase(
  grepl("^[A-Z]{3}\\.[0-9]+\\.[0-9]+_[0-9]+$", birth_gid2),
  sub("(\\.[0-9]+)\\.[0-9]+_[0-9]+$", "\\1_1", birth_gid2),
  grepl("^[A-Z]{3}\\.[0-9]+_[0-9]+$", birth_gid2),
  birth_gid2,
  default = NA_character_
)]
n_before <- nrow(d2)
d2 <- d2[gid_1 != ""]
cat(sprintf("Dropped %d rows with malformed gid_1 (out of %d)\n", n_before - nrow(d2), n_before))

cat("\n=== Load Col(2) full-area ADM1 stable_lights (baseline for unaffected regions) ===\n")
adm1_full <- data.table::fread("data/processed/ntl/dmsp_adm1_panel.csv")
adm1_full <- adm1_full[year %between% c(1992L, 2013L)]
data.table::setnames(adm1_full, c("GID_1", "iso3"), c("gid_1", "gid_0"))
adm1_full <- unique(adm1_full[, .(gid_1, gid_0, year, dmsp_ntl_full = dmsp_ntl)], by = c("gid_1", "year"))

cat("\n=== Load hole-punched extraction (real Col(3) values for the 556 affected ADM1s) ===\n")
holed <- data.table::fread("data/processed/ntl/dmsp_adm1_holepunched_panel.csv")
data.table::setnames(holed, "iso3", "gid_0")
holed <- unique(holed[, .(gid_1 = GID_1, gid_0, year, dmsp_ntl_holed = dmsp_stable_lights_holepunched)], by = c("gid_1", "year"))
cat(sprintf("Hole-punched values: %d rows | %d regions\n", nrow(holed), uniqueN(holed$gid_1)))

cat("\n=== Assemble Col(3) NTL: hole-punched value where available, else full-area value ===\n")
sn1_ntl <- merge(adm1_full, holed, by = c("gid_1", "gid_0", "year"), all.x = TRUE)
sn1_ntl[, dmsp_ntl_sn1_excl := data.table::fcase(
  !is.na(dmsp_ntl_holed), dmsp_ntl_holed,
  default = dmsp_ntl_full
)]
cat(sprintf("Regions using real hole-punched value: %d\n", uniqueN(sn1_ntl[!is.na(dmsp_ntl_holed), gid_1])))

cat("\n=== Build SN1-level is_birthregion (country-year) ===\n")
sn1_birth <- unique(d2[has_leader == 1, .(gid_0, year, birth_gid1)])
data.table::setorder(sn1_birth, gid_0, year)
sn1_birth <- unique(sn1_birth, by = c("gid_0", "year"))

cat("\n=== Build SN1 region universe and assemble panel ===\n")
sn1_regions <- unique(d2[, .(gid_1, gid_0)])
years_rep <- 1992:2013
sn1 <- sn1_regions[, .(year = years_rep), by = .(gid_1, gid_0)]
sn1 <- merge(sn1, sn1_ntl[, .(gid_1, gid_0, year, dmsp_ntl_sn1 = dmsp_ntl_full, dmsp_ntl_sn1_excl)],
             by = c("gid_1", "gid_0", "year"), all.x = TRUE)
sn1 <- merge(sn1, sn1_birth, by = c("gid_0", "year"), all.x = TRUE)

sn1[, is_birthregion_sn1 := !is.na(birth_gid1) & gid_1 == birth_gid1]
sn1 <- sn1[gid_0 %in% unique(d2[has_leader == 1, gid_0])]

cat(sprintf("SN1 panel: %d rows | %d regions | %d countries\n",
    nrow(sn1), uniqueN(sn1$gid_1), uniqueN(sn1$gid_0)))
cat(sprintf("is_birthregion_sn1 = TRUE: %d region-years\n", sn1[is_birthregion_sn1 == TRUE, .N]))

cat("\n=== Log-transform NTL ===\n")
sn1[, ln_ntl_sn1      := log(pmax(dmsp_ntl_sn1, 0) + 0.01)]
sn1[, ln_ntl_sn1_excl := log(pmax(dmsp_ntl_sn1_excl, 0) + 0.01)]

cat("\n=== Build Archigos leader-spell clusters ===\n")
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

sn1 <- merge(sn1, arch_yr[, .(gid_0 = iso3, year, spell_cluster)], by = c("gid_0", "year"), all.x = TRUE)
sn1[is.na(spell_cluster), spell_cluster := gid_0]

cat("\n=== Regressions ===\n")
data.table::setorder(sn1, gid_1, year)

d_fe2 <- fixest::panel(sn1[!is.na(is_birthregion_sn1) & is.finite(ln_ntl_sn1)], ~gid_1 + year)
m2 <- fixest::feols(
  ln_ntl_sn1 ~ fixest::l(is_birthregion_sn1) | gid_1 + gid_0^year,
  data = d_fe2, vcov = ~spell_cluster
)

d_fe3 <- fixest::panel(sn1[!is.na(is_birthregion_sn1) & is.finite(ln_ntl_sn1_excl)], ~gid_1 + year)
m3 <- fixest::feols(
  ln_ntl_sn1_excl ~ fixest::l(is_birthregion_sn1) | gid_1 + gid_0^year,
  data = d_fe3, vcov = ~spell_cluster
)

cat("\n=== TABLE IV REPLICATION (FINAL, exact hole-punch): Col(2)-(3) ===\n")
fixest::etable(m2, m3,
  digits  = 3,
  headers = c("(2) SN1 full-area", "(3) SN1 excl. birth-SN2 (exact)")
)

cat("\n=== Comparison with HR 2014 Table IV ===\n")
cat("HR 2014 body text: Col(2) coefficient 'drops by around one third' from Col(1) but remains significant.\n")
cat("HR 2014 body text: Col(3) coefficient 'becomes again slightly smaller but remains statistically significant.'\n")
cf2 <- stats::coef(m2)[1]; se2 <- sqrt(diag(stats::vcov(m2)))[1]
cf3 <- stats::coef(m3)[1]; se3 <- sqrt(diag(stats::vcov(m3)))[1]
cat(sprintf("Col(2) our SN1 full-area:            %.3f (%.3f)\n", cf2, se2))
cat(sprintf("Col(3) our SN1 excl. birth-SN2 exact: %.3f (%.3f)\n", cf3, se3))
