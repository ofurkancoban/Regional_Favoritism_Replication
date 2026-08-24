# Purpose: HR 2014 Table V (Determinants of Regional Favoritism) analog,
# extended to 1992-2023 using the harmonized DMSP/VIIRS panel, country-level
# clustering (extension convention), and the extended covariate set built
# by 05_covariates/11_table5_covariates_extension.R (QoG Standard
# Time-Series jan26 vintage, same file DHR uses, substituting WDI GDP per
# capita for PWT 7.1 and QoG's own extended/interpolated Barro-Lee
# schooling series for the raw Barro-Lee CSV -- both HR-window-only
# sources that stop around 2010-2013). Adds vdem_libdem (V-Dem Liberal
# Democracy Index) as a 6th determinant not in the original HR-window
# Table V, since it extends cleanly through 2023 and DHR itself uses it
# as a democracy-quality robustness alongside Polity2.
library(data.table)
library(fixest)

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

cat("\n=== Build birthplace flag from PLAD (+ Wikidata supplement) ===\n")
plad <- fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]
plad <- plad[is.na(foreign_leader) | foreign_leader != 1]
plad[, birth_gid2 := gid_2]
spells <- unique(plad[, .(gid_0, leader, birth_gid2, startyear, endyear)])
spells[, spell_row := .I]

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
cat(sprintf("Panel (leader-country-years): %d obs | %d regions | %d countries\n",
    nrow(ntl), uniqueN(ntl$gid_2), uniqueN(ntl$iso3)))

cat("\n=== Clustering: country-level (extension convention) ===\n")
ntl[, country_cluster := gid_0]

cat("\n=== Merge extended Table V covariates ===\n")
cov <- fread("data/processed/table5_covariates_extension.csv")
ntl <- merge(ntl, cov, by = c("iso3", "year"), all.x = TRUE)
cat(sprintf("Non-NA: polity=%d vdem_libdem=%d national_gdp=%d schooling=%d language=%d family_ties=%d\n",
    ntl[!is.na(polity), .N], ntl[!is.na(vdem_libdem), .N], ntl[!is.na(national_gdp), .N],
    ntl[!is.na(schooling), .N], ntl[!is.na(language), .N], ntl[!is.na(family_ties), .N]))

setorder(ntl, gid_2, year)
d_fe <- fixest::panel(ntl, ~gid_2 + year)

cat("\n=== Regressions ===\n")
m1 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(polity) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~country_cluster)
m2 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(schooling) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~country_cluster)
m3 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(national_gdp) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~country_cluster)
m4 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * language | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~country_cluster)
m5 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * family_ties | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~country_cluster)
m6 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * fixest::l(vdem_libdem) | gid_2 + gid_0^year,
                     data = d_fe, vcov = ~country_cluster)
m7 <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) * (fixest::l(polity) + fixest::l(schooling) +
                       fixest::l(national_gdp) + language + family_ties + fixest::l(vdem_libdem))
                     | gid_2 + gid_0^year, data = d_fe, vcov = ~country_cluster)

cat("\n=== TABLE V EXTENSION (1992-2023, harmonized panel, country-level clustering) ===\n")
fixest::etable(m1, m2, m3, m4, m5, m6, m7,
  digits  = 3,
  keep    = c("is_birthregion", "polity", "schooling", "national_gdp", "language", "family_ties", "vdem_libdem"),
  headers = c("(1) Polity", "(2) Schooling", "(3) NationalGDP", "(4) Language",
              "(5) FamilyTies", "(6) V-Dem LibDem", "(7) Combined")
)

saveRDS(list(m1 = m1, m2 = m2, m3 = m3, m4 = m4, m5 = m5, m6 = m6, m7 = m7),
        "data/processed/ntl/extension_table5_determinants_models.rds")
cat("\nSaved: data/processed/ntl/extension_table5_determinants_models.rds\n")
