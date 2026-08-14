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

plad_yr <- plad[, {
  yr_seq <- seq(max(startyear, min(years_rep)), min(endyear, max(years_rep)))
  if (length(yr_seq) == 0) yr_seq <- integer(0)
  .(year = yr_seq, gid_0 = gid_0, birth_gid2 = gid_2)
}, by = .(leader, plad_id)]

plad_yr <- plad_yr[year %in% years_rep]
data.table::setorder(plad_yr, gid_0, year, plad_id)
plad_yr <- unique(plad_yr, by = c("gid_0", "year"))
cat(sprintf("PLAD: %d country-year rows | %d countries\n",
    nrow(plad_yr), uniqueN(plad_yr$gid_0)))

cat("\n=== Step 3: Create birthplace flag (GID_2 level, with 3.6->4.1 crosswalk) ===\n")

# Apply GADM 3.6 -> 4.1 crosswalk to PLAD birth GIDs
cw36 <- data.table::fread("data/processed/gadm36_41_crosswalk.csv")
plad_yr[cw36, on = .(birth_gid2 = gid2_36), birth_gid2_41 := i.gid2_41]
# Use 4.1 GID if crosswalk found, else keep original (already 4.1 for 92.3% of cases)
plad_yr[, birth_gid2_final := data.table::fcase(
  !is.na(birth_gid2_41), birth_gid2_41,
  default = birth_gid2
)]

ntl[plad_yr, on = .(iso3 = gid_0, year), birth_gid2 := i.birth_gid2_final]
ntl[, is_birthregion := !is.na(birth_gid2) & gid_2 == birth_gid2]
ntl[plad_yr, on = .(iso3 = gid_0, year), has_leader := 1L]
ntl[is.na(has_leader), has_leader := 0L]

cat(sprintf("is_birthregion = TRUE: %d region-years\n", ntl[is_birthregion == TRUE, .N]))
cat(sprintf("Countries with leader data: %d\n", ntl[has_leader == 1, uniqueN(iso3)]))

cat("\n=== Step 3b: Remove duplicates ===\n")
ntl <- unique(ntl, by = c("gid_2", "year"))
cat(sprintf("After dedup: %d rows\n", nrow(ntl)))

cat("\n=== Step 4: Merge GPWv4 population (lnpop, ln_ntlpc) ===\n")
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
