# 06_panel/01_build_analysis_panel.R
# Purpose: Build the global analysis panel for HR 2014 replication following DHR methodology.
# Panel unit: ADM2 region-year.
# Spec: ln_ntl ~ l(birthplace) | gid_2 + gid_0^year, vcov = ~gid_0
# Country-year FE absorbs all country-level time-varying controls (GDP, polity, etc.)

library(data.table)

years_rep <- 1992:2013

cat("=== Step 1: Load NTL panel (ADM2 level) ===\n")
ntl <- data.table::fread("data/processed/ntl/dmsp_adm2_panel.csv")
ntl <- ntl[year %in% years_rep, .(region_id, iso3, adm_level, year, dmsp_ntl)]

# Keep ADM2 rows; for ADM1-only countries keep as is
ntl_adm2 <- ntl[adm_level == "ADM2"]
ntl_adm1 <- ntl[adm_level == "ADM1" & !iso3 %in% ntl_adm2$iso3]
ntl <- rbind(ntl_adm2, ntl_adm1)
rm(ntl_adm2, ntl_adm1)

# gid_2: for ADM2 rows region_id = GID_2; for ADM1 fallback = GID_1
ntl[, gid_2 := region_id]

# gid_1 (for birthplace matching): strip last segment from GID_2
ntl[, gid_1 := data.table::fcase(
  grepl("^[A-Z]{3}\\.[0-9]+\\.[0-9]+_[0-9]+$", region_id),
  sub("(\\.[0-9]+)\\.[0-9]+_[0-9]+$", "\\1_1", region_id),
  grepl("^[A-Z]{3}\\.[0-9]+_[0-9]+$", region_id),
  region_id,
  default = NA_character_
)]

cat(sprintf("NTL ADM2: %d rows | %d regions | %d countries\n",
    nrow(ntl), uniqueN(ntl$gid_2), uniqueN(ntl$iso3)))

cat("\n=== Step 2: Load and expand PLAD to country-year ===\n")
plad <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]

# Drop foreign-born leaders (PLAD's own foreign_leader flag, 74 leader-
# spell rows, e.g. Bouteflika of Algeria born in Morocco, Kocharian of
# Armenia born in disputed Nagorno-Karabakh territory that GADM draws as
# Azerbaijan). PLAD's gid_0 field records the birthplace's GADM host
# country, not the country the leader actually governed (a separate
# `country` field) -- the merge below joins is_birthregion into the NTL
# panel using gid_0 as the country key, so without this filter these rows
# spuriously flag a "leader birth region" inside a country whose
# government the leader never controlled and could not have favored.
# Matches HR 2014's own stated convention ("leaders born abroad are
# excluded," already applied to the Wikidata supplement below) and fixes
# a real discrepancy found 2026-08-19 by diffing against DHR's published
# adm_2.csv (Azerbaijan/Armenia case: our is_birthregion=TRUE for
# AZE.10.4_1 1998-2008/2008-2018, DHR's own panel has it FALSE).
n_before <- nrow(plad)
plad <- plad[is.na(foreign_leader) | foreign_leader != 1]
cat(sprintf("Dropped %d foreign-born-leader rows (PLAD foreign_leader flag)\n", n_before - nrow(plad)))

# Guard against R's seq(a, b) counting DOWNWARD when a > b instead of
# returning empty -- any leader whose tenure ended before years_rep's
# start (or began after its end) previously got a spurious phantom year
# injected (e.g. Kaifu, PM 1989-1991, produced a fake "1992" row via
# seq(max(1989,1992)=1992, min(1991,2013)=1991) = c(1992,1991)), which
# then randomly won or lost the dedup-by-(country,year) step below
# against the real sitting leader for that year. Found 2026-08-19 by
# diffing against DHR's published adm_2.csv (Japan 1992: our panel had
# Kaifu, not Miyazawa, who actually held office that year).
plad_yr <- plad[, {
  lo <- max(startyear, min(years_rep))
  hi <- min(endyear, max(years_rep))
  yr_seq <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yr_seq, gid_0 = gid_0, birth_gid2 = gid_2)
}, by = .(leader, plad_id)]

plad_yr <- plad_yr[year %in% years_rep]
# NOT deduped to one row per (country, year) here -- some countries have
# genuinely concurrent leaders in the same calendar year (e.g. Bosnia's
# rotating tripartite presidency, where a Bosniak/Croat/Serb member all
# hold office simultaneously, each with their own birth region). DHR's own
# dataprep (`plad.R`) confirms this: they dedup by (GID_0, GID_1, GID_2,
# year) -- i.e. by birth REGION-year, keeping the longest-tenured leader
# only when two leader-spells map to the exact same region in the exact
# same year -- never collapsing different regions within one country-year
# down to a single leader. Deduping by (country, year) here (as this
# script did until 2026-08-19) silently discarded 380 country-years'
# worth of legitimate concurrent/overlapping leader-birthregion pairs
# across 123 countries (confirmed by diffing against DHR's adm_2.csv).
# The actual (birth-region, year) dedup now happens in Step 3 below,
# where is_birthregion is computed directly against the full undeduped
# leader-year list rather than via a country-year keyed update join.
cat(sprintf("PLAD: %d leader-year rows | %d countries\n",
    nrow(plad_yr), uniqueN(plad_yr$gid_0)))

cat("\n=== Step 2b: Supplement PLAD gaps with Wikidata-geocoded birthplaces ===\n")
# 120 of 919 Archigos leader-spells (1992-2013) have no PLAD birthplace at
# all (see RESEARCH_JOURNAL.md, "PLAD coverage gap" analysis, 2026-08-17).
# 02_crosswalk/04_wikidata_missing_leaders.R looked these up via Wikidata's
# structured place-of-birth (P19) + coordinates (P625), point-in-polygon
# joined to GADM 3.6 (ADM2, ADM1 fallback for the handful of countries with
# no ADM2 breakdown) -- same spirit as HR 2014's own hand-collection method
# ("various Internet sites"), just automated. 33 of 120 resolved to a
# region within the leader's own country (the rest were either not found on
# Wikidata, ambiguous, or genuinely born abroad -- e.g. Levon Ter-Petrosyan
# was born in Aleppo, Syria, which correctly fails to match any Armenian
# polygon and is excluded, consistent with HR's own "leaders born abroad
# are excluded" convention).
wd_supp <- data.table::fread("data/processed/wikidata_supplement_birthplaces.csv")
wd_supp[, spell_row := .I]
wd_supp_yr <- wd_supp[, {
  lo <- max(startyear, min(years_rep))
  hi <- min(endyear, max(years_rep))
  yr_seq <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yr_seq, gid_0 = iso3, leader = leader, birth_gid2 = birth_gid2)
}, by = .(spell_row)]
wd_supp_yr <- wd_supp_yr[year %in% years_rep]
# Only fill country-years PLAD has no entry for at all -- PLAD stays the
# primary source wherever it has coverage.
wd_supp_yr <- wd_supp_yr[!plad_yr, on = .(gid_0, year)]
data.table::setorder(wd_supp_yr, gid_0, year)
wd_supp_yr <- unique(wd_supp_yr, by = c("gid_0", "year"))
cat(sprintf("Wikidata supplement: %d additional country-year rows | %d countries\n",
    nrow(wd_supp_yr), uniqueN(wd_supp_yr$gid_0)))

plad_yr <- rbind(plad_yr[, .(leader, gid_0, year, birth_gid2)],
                  wd_supp_yr[, .(leader, gid_0, year, birth_gid2)])
cat(sprintf("Combined (PLAD + Wikidata supplement): %d country-year rows | %d countries\n",
    nrow(plad_yr), uniqueN(plad_yr$gid_0)))

cat("\n=== Step 3: Create birthplace flag (GID_2 level, GADM 3.6 throughout) ===\n")

# NTL (04_extraction/01_dmsp_adm2.R), PLAD's own gid_2 field, and population
# (05_covariates/02_gpw_population.R) are now all GADM 3.6 natively -- no
# vintage crosswalk needed here (previously required because NTL extraction
# used GADM 4.1 geoboundaries; switched to GADM 3.6 directly to match
# HR 2014/DHR's original geometry exactly).
# is_birthregion is fundamentally a (region, year) flag, not a (country,
# year) one -- a country-year update join (`ntl[plad_yr, on=.(iso3=gid_0,
# year), birth_gid2 := ...]`) requires a single scalar per key and
# silently keeps only one arbitrary match when plad_yr has several rows
# per country-year (as it now legitimately does, see Step 2 above), so it
# is replaced with a direct membership join against the full (region,
# country, year) triple, which naturally allows multiple TRUE regions in
# the same country-year.
birth_ry <- unique(plad_yr[, .(gid_2 = birth_gid2, iso3 = gid_0, year)])
ntl[, is_birthregion := FALSE]
ntl[birth_ry, on = .(gid_2, iso3, year), is_birthregion := TRUE]
ntl[plad_yr, on = .(iso3 = gid_0, year), has_leader := 1L]
ntl[is.na(has_leader), has_leader := 0L]

cat(sprintf("is_birthregion = TRUE: %d region-years\n", ntl[is_birthregion == TRUE, .N]))
cat(sprintf("Countries with leader data: %d\n", ntl[has_leader == 1, uniqueN(iso3)]))

cat("\n=== Step 3b: Remove duplicates ===\n")
ntl <- unique(ntl, by = c("gid_2", "year"))
cat(sprintf("After dedup: %d rows\n", nrow(ntl)))

cat("\n=== Step 4: Merge GPWv4 population (lnpop, ln_ntlpc) ===\n")
# Population is built on GADM 3.6 ADM2 polygons (05_covariates/02_gpw_population.R),
# same vintage as NTL now -- direct GID_2 join, no crosswalk needed.
pop <- data.table::fread("data/processed/population_adm2.csv")
pop <- unique(pop[, .(gid_2 = GID_2, year, lnpop)], by = c("gid_2", "year"))
ntl <- merge(ntl, pop, by = c("gid_2", "year"), all.x = TRUE)
cat(sprintf("Matched population: %d / %d rows\n", ntl[!is.na(lnpop), .N], nrow(ntl)))

cat("\n=== Step 5: Log NTL ===\n")
data.table::setorder(ntl, gid_2, year)
ntl[, ln_ntl    := log(pmax(dmsp_ntl, 0) + 0.01)]
ntl[, ln_ntl_00 := log(pmax(dmsp_ntl, 0))]   # extensive margin (log 0 -> -Inf, filtered in reg)
ntl[, ln_ntlpc  := log(pmax(dmsp_ntl, 0) / exp(lnpop) + 0.01)]

# Country-year FE identifier
ntl[, gid_0      := iso3]
ntl[, gid_0year  := paste0(iso3, "_", year)]

cat("\n=== Step 6: Finalize ===\n")
panel <- ntl[has_leader == 1]

cat(sprintf("\nFinal panel:\n"))
cat(sprintf("  Rows:             %d\n", nrow(panel)))
cat(sprintf("  ADM2 regions:     %d\n", uniqueN(panel$gid_2)))
cat(sprintf("  Countries:        %d\n", uniqueN(panel$iso3)))
cat(sprintf("  Years:            %d-%d\n", min(panel$year), max(panel$year)))
cat(sprintf("  is_birthregion=T: %d (%.2f%%)\n",
    panel[is_birthregion == TRUE, .N],
    100 * panel[is_birthregion == TRUE, .N] / nrow(panel)))

data.table::fwrite(panel, "data/processed/analysis_panel.csv")
cat("\nSaved: data/processed/analysis_panel.csv\n")
