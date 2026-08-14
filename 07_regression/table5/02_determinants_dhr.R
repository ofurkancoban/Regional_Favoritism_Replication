# 07_regression/table5/02_determinants_dhr.R
# HR 2014 Table V, using the DHR replication dataset (adm_2.csv.gz) instead
# of our own PLAD-built panel -- same DHR track already used for Table II
# Col(1) (07_regression/table2/01_track1_dhr.R). Tests whether Table V's
# weaker significance on NationalGDP/FamilyTies (01_determinants.R) was
# driven by our narrower/different country sample, or is a genuine feature
# of the underlying data even under DHR's own larger, HR-methodology-
# matched panel (147 countries vs. our 148, but different construction).
#
# DHR's file already includes ready-made `schooling`, `p_polity2`, `lngdp`
# columns (their own versions of Schooling/Polity/NationalGDP, likely
# closer in vintage/construction to what HR 2014 actually used than our
# independently-assembled QoG/PWT/Barro-Lee versions). Only Language_c
# (Alesina et al. 2003) and FamilyTies_c (WVS, this session) are merged in
# from outside, since DHR's file doesn't include them.

library(data.table)
library(fixest)
library(haven)
library(countrycode)

cat("=== Load DHR replication panel ===\n")
d <- data.table::fread("01_literature/dataverse_files/data/analysis/adm_2.csv.gz")
d <- d[year %between% c(1992L, 2009L)]  # HR's own window
d[, ln_ntl := log(light_mean_ols + 0.01)]
d[, polity := (p_polity2 + 10) / 20]
data.table::setnames(d, "lngdp", "national_gdp")
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    nrow(d), data.table::uniqueN(d$gid_2), data.table::uniqueN(d$gid_0)))

cat("\n=== Build Archigos leader-spell clusters ===\n")
arch <- data.table::as.data.table(haven::read_dta("data/raw/archigos/Archigos_4.1.dta"))
arch[, startyear := as.integer(substr(startdate, 1, 4))]
arch[, endyear   := as.integer(substr(enddate,   1, 4))]
arch <- arch[!is.na(startyear) & !is.na(endyear)]
arch[, iso3 := suppressWarnings(countrycode::countrycode(ccode, "cown", "iso3c"))]
arch <- arch[!is.na(iso3)]

arch_yr <- arch[, {
  yrs <- seq(max(startyear, 1992L), min(endyear, 2009L))
  if (length(yrs) == 0L) yrs <- integer(0)
  .(year = yrs, iso3 = iso3)
}, by = .(obsid)]
arch_yr <- arch_yr[year %between% c(1992L, 2009L)]
data.table::setorder(arch_yr, iso3, year, obsid)
arch_yr <- unique(arch_yr, by = c("iso3", "year"))
data.table::setorder(arch_yr, iso3, year)
arch_yr[, spell_cluster := data.table::shift(obsid, 1L), by = iso3]
arch_yr[is.na(spell_cluster), spell_cluster := obsid]

d <- merge(d, arch_yr[, .(iso3, year, spell_cluster)], by.x = c("gid_0", "year"), by.y = c("iso3", "year"), all.x = TRUE)
d[is.na(spell_cluster), spell_cluster := gid_0]

cat("\n=== Merge Language + FamilyTies (only two not already in DHR file) ===\n")
qog <- data.table::fread("data/raw/qog/qog_std_ts_jan26.csv", select = c("ccodealp", "al_language2000"))
lang <- unique(qog[!is.na(al_language2000)], by = "ccodealp")
data.table::setnames(lang, c("ccodealp", "al_language2000"), c("gid_0", "language"))
d <- merge(d, lang, by = "gid_0", all.x = TRUE)

ft <- data.table::fread("data/processed/family_ties_country.csv")[, .(gid_0 = iso3, family_ties)]
d <- merge(d, ft, by = "gid_0", all.x = TRUE)

cat(sprintf("Non-NA: polity=%d national_gdp=%d schooling=%d language=%d family_ties=%d\n",
    d[!is.na(polity), .N], d[!is.na(national_gdp), .N], d[!is.na(schooling), .N],
    d[!is.na(language), .N], d[!is.na(family_ties), .N]))
cat(sprintf("Countries with FamilyTies in this panel: %d\n", d[!is.na(family_ties), data.table::uniqueN(gid_0)]))

data.table::setorder(d, gid_2, year)
d_fe <- fixest::panel(d, ~gid_2 + year)

cat("\n=== Table V regressions (DHR panel) ===\n")
m1 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * polity | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m2 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * schooling | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m3 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * national_gdp | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m4 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * language | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m5 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * family_ties | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m6 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * (polity + schooling + language + family_ties) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

fixest::etable(m1, m2, m3, m4, m5, m6,
  digits  = 3,
  headers = c("(1) Polity", "(2) Schooling", "(3) NationalGDP", "(4) Language", "(5) FamilyTies", "(6) Combined")
)

cat("\n=== Comparison with HR 2014 Table V ===\n")
cat("Col(1) HR: Leader 0.262*** (0.056), Leader x Polity -0.298*** (0.063)\n")
cat("Col(2) HR: Leader 0.119*** (0.040), Leader x Schooling -0.012*** (0.004)\n")
cat("Col(3) HR: Leader 0.196** (0.082), Leader x NationalGDP -0.019** (0.009)\n")
cat("Col(4) HR: Leader -0.008 (0.017), Leader x Language 0.120*** (0.040)\n")
cat("Col(5) HR: Leader 0.008 (0.012), Leader x FamilyTies 0.063** (0.032)\n")

out_dir <- "data/processed/ntl"
saveRDS(list(m1 = m1, m2 = m2, m3 = m3, m4 = m4, m5 = m5, m6 = m6),
        file.path(out_dir, "table5_determinants_dhr_models.rds"))
cat(sprintf("\nModels saved: %s\n", file.path(out_dir, "table5_determinants_dhr_models.rds")))
