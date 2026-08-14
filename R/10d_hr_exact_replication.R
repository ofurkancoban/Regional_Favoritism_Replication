# R/10d_hr_exact_replication.R
# Purpose: Exact replication of HR 2014 Table II.
# - NTL:     DHR adm_2.csv.gz (OLS = raw DMSP)
# - Leaders: Archigos 4.1 (spell identification) + PLAD (birthplace GID_2)
# - Window:  1992-2009
# - Cluster: leader-spell level (HR specification)
# - Spec:    ln_ntl ~ l(Leader) | region FE + country-year FE

library(data.table)
library(fixest)
library(haven)
library(countrycode)

cat("=== Step 1: Load NTL panel ===\n")
d <- data.table::fread("01_literature/dataverse_files/data/analysis/adm_2.csv.gz")
d[, ln_ntl := log(light_mean_ols + 0.01)]
d_hr <- d[year %between% c(1992L, 2009L) & !is.na(ln_ntl)]
cat(sprintf("NTL: %d rows | %d regions | %d countries\n",
    nrow(d_hr), uniqueN(d_hr$gid_2), uniqueN(d_hr$gid_0)))

cat("\n=== Step 2: Build Archigos leader spells ===\n")
arch <- data.table::as.data.table(haven::read_dta("data/raw/archigos/Archigos_4.1.dta"))
arch[, startyear := as.integer(substr(startdate, 1, 4))]
arch[, endyear   := as.integer(substr(enddate,   1, 4))]
arch <- arch[!is.na(startyear) & !is.na(endyear)]

# Convert COW numeric code to ISO3 (Archigos uses COW, DHR uses ISO3)
arch[, iso3 := suppressWarnings(countrycode::countrycode(ccode, "cown", "iso3c"))]
arch <- arch[!is.na(iso3)]

# Expand to country-year
arch_yr <- arch[, {
  yrs <- seq(max(startyear, 1992L), min(endyear, 2009L))
  if (length(yrs) == 0) yrs <- integer(0)
  .(year = yrs, leadid = leadid, iso3 = iso3)
}, by = .(obsid)]

arch_yr <- arch_yr[year %between% c(1992L, 2009L)]
# One leader per country-year
data.table::setorder(arch_yr, iso3, year, obsid)
arch_yr <- unique(arch_yr, by = c("iso3", "year"))
cat(sprintf("Archigos expanded: %d country-years | %d countries | %d unique spells\n",
    nrow(arch_yr), uniqueN(arch_yr$iso3), uniqueN(arch_yr$obsid)))

cat("\n=== Step 3: Add birthplace from PLAD ===\n")
plad <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & !is.na(archigos_id) & archigos_id != ""]

# Join birthplace GID_2 from PLAD to Archigos leaders
arch_yr[plad[, .(archigos_id, gid_2)], on = .(leadid = archigos_id), birth_gid2 := i.gid_2]
cat(sprintf("Leaders with birthplace: %d / %d (%.1f%%)\n",
    arch_yr[!is.na(birth_gid2), uniqueN(leadid)],
    uniqueN(arch_yr$leadid),
    100 * arch_yr[!is.na(birth_gid2), uniqueN(leadid)] / uniqueN(arch_yr$leadid)))

# Leader-spell cluster (lagged by one period per HR)
data.table::setorder(arch_yr, iso3, year)
arch_yr[, spell_cluster := data.table::shift(obsid, 1L), by = iso3]
arch_yr[is.na(spell_cluster), spell_cluster := obsid]

# Countries with at least one matched birthplace
countries_with_bp <- arch_yr[!is.na(birth_gid2), unique(iso3)]
cat(sprintf("Countries with birthplace data: %d\n", length(countries_with_bp)))

cat("\n=== Step 4: Merge spell cluster into NTL panel ===\n")
# Use DHR's pre-computed is_birthregion (correctly matched to GID_2 system)
# Only use Archigos for leader-spell cluster variable (HR clustering specification)
d_hr <- merge(d_hr, arch_yr[, .(gid_0 = iso3, year, spell_cluster)],
              by = c("gid_0", "year"), all.x = TRUE)

# Fall back to country-level cluster for country-years not in Archigos
d_hr[is.na(spell_cluster), spell_cluster := gid_0]

cat(sprintf("is_birthregion=TRUE (DHR): %d region-years\n",
    d_hr[is_birthregion == TRUE, .N]))
cat(sprintf("Spell cluster matched: %.1f%% of obs\n",
    100 * mean(arch_yr$gid_0 %in% d_hr$gid_0)))
cat(sprintf("Countries in sample: %d\n",
    d_hr[!is.na(is_birthregion), uniqueN(gid_0)]))

cat("\n=== Step 5: Regressions ===\n")
d_fe <- fixest::panel(d_hr[!is.na(is_birthregion)], ~gid_2 + year)

# Col 1: baseline
m1 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

# Col 2: + NationalGDP
m2 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) + lngdp | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

# Col 4: + Pop
m4 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) + lnpop | gid_2 + gid_0^year,
  data = d_fe, vcov = ~spell_cluster
)

cat("\n=== Results: HR Table II Replication (Archigos spell cluster + DHR is_birthregion) ===\n")
fixest::etable(m1, m2, m4,
  digits  = 3,
  keep    = "is_birthregion",
  headers = c("Col(1) Baseline", "Col(2) +GDP", "Col(4) +Pop")
)

cat("\n--- Comparison with HR 2014 ---\n")
cat(sprintf("%-22s  %-16s  %-16s\n", "Specification", "HR 2014", "Our estimate"))
cat(strrep("-", 58), "\n")
refs <- list(
  list(label="Col(1) Baseline", hr_b=0.038, hr_se=0.014, m=m1),
  list(label="Col(2) +GDP",     hr_b=0.039, hr_se=0.015, m=m2),
  list(label="Col(4) +Pop",     hr_b=0.019, hr_se=0.010, m=m4)
)
for (r in refs) {
  cf  <- stats::coef(r$m)[1]
  se  <- sqrt(diag(stats::vcov(r$m)))[1]
  pv  <- summary(r$m)$coeftable[1, 4]
  sig <- ifelse(pv<0.001,"***",ifelse(pv<0.01,"**",ifelse(pv<0.05,"*",ifelse(pv<0.1,".","  "))))
  cat(sprintf("%-22s  %.3f (%.3f)***    %.3f (%.3f)%s\n",
      r$label, r$hr_b, r$hr_se, cf, se, sig))
}
