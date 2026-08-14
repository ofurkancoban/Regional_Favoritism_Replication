# R/14_table4_col23.R
# Replication of HR 2014 Table IV, Columns (2)-(3): The Geographic Extent of
# Regional Favoritism, using SN1 (ADM1) regions as units of observation.
#
# Col(2): SN1 regions, full-area stable_lights (direct GEE zonal extraction
#         via R/13_gee_adm1_stable.R -- data/processed/ntl/adm1_stable_global_panel.csv)
# Col(3): SN1 regions, but NTL is averaged only over the SN2 (ADM2) sub-regions
#         that were NEVER the birth region of any leader in our PLAD sample
#         ("we omit all SN2 regions in which a political leader from our
#         sample was ever born", HR 2014 p. 1018). This is approximated as
#         an unweighted mean of ADM2-level stable_lights zonal means within
#         each ADM1 (area weights not available), excluding any ADM2 that
#         is EVER a PLAD birth region for that country, across the full
#         leader-spell history (not just the current year). This is a
#         reasonable-effort approximation, not a fresh zonal extraction on
#         hole-punched geometry -- documented here and in RESEARCH_JOURNAL.md.

library(data.table)
library(fixest)
library(haven)
library(countrycode)

cat("=== Load canonical analysis panel (ADM2, stable_lights) ===\n")
d2 <- data.table::fread("data/processed/analysis_panel.csv")
d2 <- d2[year %between% c(1992L, 2013L)]

cat("=== Derive birth_gid1 from birth_gid2 (same stripping rule as gid_1) ===\n")
d2[, birth_gid1 := data.table::fcase(
  grepl("^[A-Z]{3}\\.[0-9]+\\.[0-9]+_[0-9]+$", birth_gid2),
  sub("(\\.[0-9]+)\\.[0-9]+_[0-9]+$", "\\1_1", birth_gid2),
  grepl("^[A-Z]{3}\\.[0-9]+_[0-9]+$", birth_gid2),
  birth_gid2,
  default = NA_character_
)]

cat("\n=== Build the set of SN2 regions EVER a birth region (any leader, any year) ===\n")
plad <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & gid_0 != "."]
cw36 <- data.table::fread("data/processed/gadm36_41_crosswalk.csv")
plad[cw36, on = .(gid_2 = gid2_36), gid_2_41 := i.gid2_41]
plad[, birth_gid2_final := data.table::fcase(!is.na(gid_2_41), gid_2_41, default = gid_2)]
ever_birth_gid2 <- unique(plad$birth_gid2_final)
cat(sprintf("SN2 regions ever a birth region: %d\n", length(ever_birth_gid2)))

cat("\n=== Col(3): aggregate ADM2 stable_lights to ADM1, excluding ever-birth ADM2s ===\n")
d2_excl <- d2[!(gid_2 %in% ever_birth_gid2)]
sn1_excl <- d2_excl[, .(dmsp_ntl_sn1_excl = mean(dmsp_ntl, na.rm = TRUE)),
                     by = .(gid_1, gid_0, year)]

cat("\n=== Col(2): load direct ADM1 GEE extraction ===\n")
adm1 <- data.table::fread("data/processed/ntl/adm1_stable_global_panel.csv")
adm1 <- adm1[year %between% c(1992L, 2013L)]
data.table::setnames(adm1, c("GID_1", "iso3"), c("gid_1", "gid_0"))
adm1 <- unique(adm1[, .(gid_1, gid_0, year, dmsp_ntl_sn1 = dmsp_stable_lights)], by = c("gid_1", "year"))

cat("\n=== Build SN1-level is_birthregion (country-year) + has_leader ===\n")
sn1_birth <- unique(d2[has_leader == 1, .(gid_0, year, birth_gid1)])
data.table::setorder(sn1_birth, gid_0, year)
sn1_birth <- unique(sn1_birth, by = c("gid_0", "year"))

cat("\n=== Build the SN1 region universe (all ADM1 gid_1 x gid_0 in our panel) ===\n")
# A small number of malformed GID_2 strings (missing separator, e.g. "GHA1.1_2")
# fail the gid_1-stripping regex and default to "" -- drop those before building
# the SN1 panel, since an empty gid_1 is not a valid panel identifier.
n_before <- nrow(d2)
d2 <- d2[gid_1 != ""]
cat(sprintf("Dropped %d rows with malformed gid_1 (out of %d)\n", n_before - nrow(d2), n_before))
sn1_regions <- unique(d2[, .(gid_1, gid_0)])

cat("\n=== Assemble SN1 panel: expand regions x years, merge NTL sources ===\n")
years_rep <- 1992:2013
sn1 <- sn1_regions[, .(year = years_rep), by = .(gid_1, gid_0)]
sn1 <- merge(sn1, adm1,     by = c("gid_1", "gid_0", "year"), all.x = TRUE)
sn1 <- merge(sn1, sn1_excl, by = c("gid_1", "gid_0", "year"), all.x = TRUE)
sn1 <- merge(sn1, sn1_birth, by = c("gid_0", "year"), all.x = TRUE)

sn1[, is_birthregion_sn1 := !is.na(birth_gid1) & gid_1 == birth_gid1]
sn1[, has_leader := as.integer(!is.na(birth_gid1) | gid_0 %in% sn1_birth$gid_0)]
sn1 <- sn1[gid_0 %in% unique(d2[has_leader == 1, gid_0])]

cat(sprintf("SN1 panel: %d rows | %d regions | %d countries\n",
    nrow(sn1), uniqueN(sn1$gid_1), uniqueN(sn1$gid_0)))
cat(sprintf("is_birthregion_sn1 = TRUE: %d region-years\n", sn1[is_birthregion_sn1 == TRUE, .N]))

cat("\n=== Log-transform NTL ===\n")
sn1[, ln_ntl_sn1      := log(pmax(dmsp_ntl_sn1, 0) + 0.01)]
sn1[, ln_ntl_sn1_excl := log(pmax(dmsp_ntl_sn1_excl, 0) + 0.01)]

cat("\n=== Build Archigos leader-spell clusters (same as Table II/III) ===\n")
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

cat("\n=== TABLE IV REPLICATION: Col(2)-(3), SN1-level ===\n")
fixest::etable(m2, m3,
  digits  = 3,
  headers = c("(2) SN1 full-area", "(3) SN1 excl. birth-SN2*")
)

cat("\n=== Comparison with HR 2014 Table IV ===\n")
cat("HR 2014 body text: Col(2) coefficient 'drops by around one third' from Col(1) but remains significant.\n")
cat("HR 2014 body text: Col(3) coefficient 'becomes again slightly smaller but remains statistically significant.'\n")
cat(sprintf("Col(1) SN2 baseline (from Table II/III): 0.043-0.044\n"))
cf2 <- stats::coef(m2)[1]; se2 <- sqrt(diag(stats::vcov(m2)))[1]
cf3 <- stats::coef(m3)[1]; se3 <- sqrt(diag(stats::vcov(m3)))[1]
cat(sprintf("Col(2) our SN1 full-area:       %.3f (%.3f)\n", cf2, se2))
cat(sprintf("Col(3) our SN1 excl. birth-SN2: %.3f (%.3f)\n", cf3, se3))
cat("\n* Col(3): unweighted mean of ADM2 stable_lights within each ADM1, excluding\n")
cat("  ADM2s that are ever a PLAD birth region -- approximation, see script header.\n")
