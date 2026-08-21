# 07_regression/table7/01_aid_oil.R
# HR 2014 Table VII: Aid, Oil, and Regional Favoritism.
# Spec (p.1024): ln_ntl ~ l(is_birthregion) * X [* Polity] | gid_2 + gid_0^year
#   Col(1): X = Aid
#   Col(2): X = Oil
#   Col(3): X = Aid, plus triple interaction with Polity
#   Col(4): X = Oil, plus triple interaction with Polity
#
# Covariates: 05_covariates/05_aid_oil.R (Aid = OECD-DAC gross ODA per
# capita via QoG `gcdf_groda`/`wdi_pop`, IHS-transformed per Levy-Yeyati,
# Panizza & Stein (2007) exactly as HR specify; Oil = oil rents per capita
# via QoG `wdi_oilrent` x `wdi_gdpcapcur`, log1p-transformed; Polity =
# Polity2 rescaled 0-1, same construction as Table V).

library(data.table)
library(fixest)
library(haven)
library(countrycode)

cat("=== Load analysis panel ===\n")
d <- data.table::fread("data/processed/analysis_panel.csv")
d <- d[year %between% c(1992L, 2013L)]
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    nrow(d), data.table::uniqueN(d$gid_2), data.table::uniqueN(d$iso3)))

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
  hi <- min(endyear, 2013L)
  yrs <- if (lo > hi) integer(0) else seq(lo, hi)
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

cat("\n=== Merge Aid/Oil/Polity covariates ===\n")
cov <- data.table::fread("data/processed/table7_covariates.csv")
d <- merge(d, cov, by = c("iso3", "year"), all.x = TRUE)
cat(sprintf("Non-NA: aid=%d oil=%d polity=%d\n",
    d[!is.na(aid), .N], d[!is.na(oil), .N], d[!is.na(polity), .N]))

data.table::setorder(d, gid_2, year)
d_fe <- fixest::panel(d, ~gid_2 + year)

cat("\n=== Table VII regressions ===\n")
# HR's notation is Leader_ict-1 x Aid_ct-1 / Oil_ct-1 / Polity_ct-1 -- all
# time-varying covariates are lagged one period, same as Table V.
m1 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(aid) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m2 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(oil) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m3 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(aid) * fixest::l(polity) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)
m4 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(oil) * fixest::l(polity) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~spell_cluster)

fixest::etable(m1, m2, m3, m4,
  digits  = 3,
  headers = c("(1) Aid", "(2) Oil", "(3) Aid x Polity", "(4) Oil x Polity")
)

cat("\n=== Comparison with HR 2014 Table VII ===\n")
cat("Col(1) HR: Leader -0.019 (0.015), Leader x Aid 0.008*** (0.002)\n")
cat("Col(2) HR: Leader  0.020 (0.022), Leader x Oil 0.000 (0.002)\n")
cat("Col(3) HR: Leader  0.086 (0.073), Leader x Aid 0.019** (0.009), Leader x Polity -0.121 (0.074), Leader x Aid x Polity -0.019* (0.010)\n")
cat("Col(4) HR: Leader  0.118 (0.084), Leader x Oil 0.010 (0.008), Leader x Polity -0.109 (0.094), Leader x Oil x Polity -0.014 (0.010)\n")

out_dir <- "data/processed/ntl"
saveRDS(list(m1 = m1, m2 = m2, m3 = m3, m4 = m4),
        file.path(out_dir, "table7_aid_oil_models.rds"))
cat(sprintf("\nModels saved: %s\n", file.path(out_dir, "table7_aid_oil_models.rds")))
