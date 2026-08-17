# 07_regression/table2/00_track0_hr_original.R
# "Track 0": HR 2014's own raw nighttime-light extraction, matched to our
# PLAD-derived is_birthregion flag. Distinct from Track1 (DHR's 2025/2026
# re-replication panel, adm_2.csv) and Track2 (our own independent NTL
# extraction) -- this is the closest this project gets to HR 2014's
# literal original data, since neither Track1 nor Track2 use HR's actual
# 2013-vintage light+geometry output.
#
# Source: data/raw/hr2014_original/Lights_Pop_SN2v2_1990_2013.dta -- HR's
# own zonal light statistics (mean column, max=63 confirms raw DMSP-OLS DN,
# HR 2014 p.998's stable_lights band) over their own "SN2" (second
# subnational level) geometry. HR's Appendix A states this geometry comes
# from CIESIN's own subnational administrative boundaries product
# (CIESIN_SEDAC_GPWv3_SUBADBND) -- confirmed via NASA's own CMR catalog
# metadata to have NEVER been publicly released ("Due to copyright
# restrictions, only maps... are available, the underlying data cannot be
# released"), so we cannot use HR's original geometry directly. Instead we
# resolve each HR unit (id_2, GID_0, name_1, name_2, x, y) to a GADM 3.6
# gid_2 via a multi-tier name+space crosswalk, layering in several
# supplementary boundary sources for countries GADM's own ADM2 lacks.
#
# Crosswalk tiers (each requires stronger corroboration than a pure
# nearest-centroid snap, which was found 2026-08-20 to introduce enough
# false matches to visibly attenuate the Table II coefficient):
#   1. Clean 1:1 HASC_2 code match (GADM's own HASC_2 vs HR's hasc_2)
#   2. Exact normalized-name match (country + ADM1 + ADM2 name)
#   3. Fuzzy ADM2 name (edit distance <= 2) within an exact ADM1-name match
#   4. emdat (data/raw/emdat/admin_combined_0_to_4.pmtiles, WFP/OCHA-style
#      combined ADM0-4 boundaries) -- name+space corroborated fallback for
#      units Tier 1-3 couldn't resolve, snapped to nearest GADM gid_2
#   5. OCHA COD-AB (data/raw/global_admin_boundaries_matched_latest.gdb) --
#      same name+space method, for the 5 countries it covers among our
#      remaining deficits (Burkina Faso, Bhutan, Poland, Venezuela, South
#      Africa); most other GADM-deficit countries (Australia, Brazil,
#      Denmark, North Macedonia, Greece, Rwanda...) are outside OCHA's
#      humanitarian-response country list and not covered
#   6. Brazil: IBGE's own official municipal shapefile (BR_Municipios_2022,
#      5,572 municipalities, geoftp.ibge.gov.br) -- name+space matched;
#      GADM 3.6's own ADM2 for Brazil is far coarser than HR's SN2 (which
#      is genuinely municipality-level), the single largest country
#      deficit found this session (2,502 of 5,504 units, 45%)
#   7. Australia: ABS's official SA2 shapefile (Australian Statistical
#      Geography Standard Ed.3, abs.gov.au) -- name+space matched; GADM's
#      ADM2 for Australia is far coarser than HR's SN2 (which reaches
#      suburb/locality level in some states, e.g. Canberra's individual
#      suburbs Acton/Ainslie/Amaroo)
#   8. Brazil spatial-only fallback: ~713 of Brazil's remaining units have
#      permanently corrupted place names in HR's own .dta file (a genuine
#      byte-level encoding failure in the source file -- tested latin1,
#      windows-1252, macintosh, CP850, CP860, ISO-8859-1, and re-reading
#      via haven's own `encoding=` argument; none recover valid text,
#      confirming the damage is in the source bytes, not a decoding
#      mismatch we can fix). These units' x/y coordinates are intact, so
#      they're matched by nearest-centroid alone (no name verification) --
#      tested 2026-08-20 to add units with no measurable effect on the
#      Table II Col(1) coefficient or its standard error, confirming they
#      don't introduce meaningful additional noise despite the weaker
#      matching criterion.
#
# Coverage achieved: 34,470 / 38,929 HR units matched (88.6%; HR's own
# published Table II Col(1) N is 38,427 regions after their own country/
# latitude sample restriction). Country-code fixes applied for HR's use of
# several pre-2000s-vintage ISO3 codes no longer used by GADM: ZAR->COD,
# ROM->ROU, YUG->SRB, TMP->TLS.
#
# Result (Table II Col(1), Leader_ict-1): 0.044** (0.015) full sample /
# 0.046** (0.017) HR's exact 126-country 1992-2009 sample -- both close to
# HR 2014's own published 0.038*** (0.014), and this is the only track in
# this project built on HR's own light+geometry data rather than a fully
# independent re-extraction, making it the strongest direct replication
# evidence produced this session. Only Col(1) is implemented here (not the
# full 8-column table) -- extending to Col(4)-(8) would require merging
# lnpop/G-Econ RegionalGDP onto this same ad hoc crosswalk, not yet built.

library(data.table)
library(sf)
library(fixest)
library(haven)
library(countrycode)
library(stringdist)

sf::sf_use_s2(FALSE)

norm_name <- function(x) {
  x <- iconv(x, from = "UTF-8", to = "UTF-8", sub = "byte")
  x <- tolower(x)
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT", sub = "")
  x <- gsub("[^a-z0-9]", "", x)
  x
}

cache_path <- "data/processed/ntl/hr_original_light_panel.csv"

if (file.exists(cache_path)) {
  cat("=== Loading cached crosswalked light panel ===\n")
  hr_light <- fread(cache_path)
  if ("GID_2" %in% names(hr_light) && !"gid_2" %in% names(hr_light)) {
    setnames(hr_light, "GID_2", "gid_2")
  }
} else {
  cat("=== Building crosswalk from scratch (first run; will cache to disk) ===\n")

  cat("\n--- Load GADM 3.6 level2 ---\n")
  g_sf <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
  g <- as.data.table(sf::st_drop_geometry(g_sf))
  g[, name1_n := norm_name(NAME_1)]
  g[, name2_n := norm_name(NAME_2)]
  g_cent <- suppressWarnings(sf::st_coordinates(sf::st_centroid(g_sf)))
  g[, cx := g_cent[, 1]]
  g[, cy := g_cent[, 2]]

  cat("\n--- Load HR's raw file ---\n")
  hr_raw <- as.data.table(haven::read_dta("data/raw/hr2014_original/Lights_Pop_SN2v2_1990_2013.dta"))
  hr_raw <- hr_raw[year %between% c(1992, 2013)]
  iso3_fix <- c(ZAR = "COD", ROM = "ROU", YUG = "SRB", TMP = "TLS")
  hr_raw[, GID_0 := fifelse(countrycode %in% names(iso3_fix), iso3_fix[countrycode], countrycode)]
  hr_raw[, name1_n := norm_name(name_1)]
  hr_raw[, name2_n := norm_name(name_2)]

  cat("\n--- Tier 1: HASC_2 exact match ---\n")
  dup <- g[!is.na(HASC_2), .N, by = HASC_2][N > 1, HASC_2]
  g_hasc <- g[!is.na(HASC_2) & !HASC_2 %in% dup, .(HASC_2, GID_2)]
  hr_raw <- merge(hr_raw, g_hasc, by.x = "hasc_2", by.y = "HASC_2", all.x = TRUE)

  cat("--- Tier 2: exact normalized-name match ---\n")
  unmatched_units <- unique(hr_raw[is.na(GID_2), .(GID_0, name1_n, name2_n)])
  g_name_dup <- g[, .N, by = .(GID_0, name1_n, name2_n)][N > 1]
  g_name <- g[!g_name_dup, on = .(GID_0, name1_n, name2_n), .(GID_0, name1_n, name2_n, GID_2)]
  tier2 <- merge(unmatched_units, g_name, by = c("GID_0", "name1_n", "name2_n"))
  hr_raw <- merge(hr_raw, tier2, by = c("GID_0", "name1_n", "name2_n"), all.x = TRUE, suffixes = c("", "_t2"))
  hr_raw[is.na(GID_2) & !is.na(GID_2_t2), GID_2 := GID_2_t2]
  hr_raw[, GID_2_t2 := NULL]

  cat("--- Tier 3: fuzzy name within exact ADM1 name (edit dist <= 2) ---\n")
  still3 <- unique(hr_raw[is.na(GID_2), .(GID_0, name1_n, name2_n)])
  still3 <- still3[name2_n != "" & !is.na(name2_n)]
  fuzzy_within_adm1 <- function(gid0, n1, n2) {
    cand <- g[GID_0 == gid0 & name1_n == n1]
    if (nrow(cand) == 0) return(NA_character_)
    d <- stringdist::stringdist(n2, cand$name2_n, method = "lv")
    if (min(d) > 2 || sum(d == min(d)) > 1) return(NA_character_)
    cand$GID_2[which.min(d)]
  }
  still3[, GID_2_t3 := mapply(fuzzy_within_adm1, GID_0, name1_n, name2_n)]
  hr_raw <- merge(hr_raw, still3[, .(GID_0, name1_n, name2_n, GID_2_t3)],
                  by = c("GID_0", "name1_n", "name2_n"), all.x = TRUE)
  hr_raw[is.na(GID_2) & !is.na(GID_2_t3), GID_2 := GID_2_t3]
  hr_raw[, GID_2_t3 := NULL]

  n_tier13 <- uniqueN(hr_raw[!is.na(GID_2), .(id_2, GID_0)])
  n_total <- uniqueN(hr_raw[, .(id_2, GID_0)])
  cat(sprintf("Tier1-3 total: %d / %d (%.1f%%)\n", n_tier13, n_total, 100 * n_tier13 / n_total))

  hr_units_all <- unique(hr_raw[, .(id_2, GID_0, name1_n, name2_n, x, y)])
  hr_units_all <- hr_units_all[, .SD[1], by = .(id_2, GID_0)]
  matched_so_far <- unique(hr_raw[!is.na(GID_2), .(id_2, GID_0)])

  name_space_fallback <- function(units, cand) {
    # Requires BOTH name similarity >= 0.75 AND spatial proximity <= 1
    # degree -- corroborated fallback, not a pure nearest-centroid snap.
    out <- rep(NA_character_, nrow(units))
    for (j in seq_len(nrow(units))) {
      n2 <- units$name2_n[j]; px <- units$x[j]; py <- units$y[j]
      if (n2 == "" || is.na(n2) || is.na(px)) next
      namelen <- pmax(nchar(n2), nchar(cand$leaf_name_n))
      namesim <- 1 - stringdist::stringdist(n2, cand$leaf_name_n, method = "lv") / namelen
      spdist <- sqrt((cand$cx - px)^2 + (cand$cy - py)^2)
      ok <- namesim >= 0.75 & spdist <= 1.0
      if (!any(ok)) next
      cand_ok <- cand[ok]; namesim_ok <- namesim[ok]; spdist_ok <- spdist[ok]
      o <- order(-namesim_ok, spdist_ok)
      if (length(o) > 1 && namesim_ok[o[1]] - namesim_ok[o[2]] < 0.05 &&
          abs(spdist_ok[o[1]] - spdist_ok[o[2]]) < 0.05) next
      out[j] <- cand$cx_key[ok][o[1]]
    }
    out
  }

  nearest_gadm <- function(gid0, px, py) {
    cand <- g[GID_0 == gid0]
    if (nrow(cand) == 0 || is.na(px)) return(NA_character_)
    d <- sqrt((cand$cx - px)^2 + (cand$cy - py)^2)
    cand$GID_2[which.min(d)]
  }

  cat("\n--- Tier 4: emdat fallback ---\n")
  still_unmatched <- fsetdiff(hr_units_all[, .(id_2, GID_0)], matched_so_far)
  still_unmatched <- merge(still_unmatched, hr_units_all, by = c("id_2", "GID_0"))
  emdat_countries <- unique(still_unmatched$GID_0)
  emdat_results <- list()
  for (gid0 in emdat_countries) {
    units <- still_unmatched[GID_0 == gid0]
    bbox_g <- g[GID_0 == gid0]
    if (nrow(bbox_g) == 0) next
    bb <- sf::st_bbox(c(xmin = min(bbox_g$cx) - 1, xmax = max(bbox_g$cx) + 1,
                         ymin = min(bbox_g$cy) - 1, ymax = max(bbox_g$cy) + 1), crs = 4326)
    wkt <- sf::st_as_text(sf::st_transform(sf::st_as_sfc(bb), 3857))
    ed <- tryCatch(
      sf::st_read("data/raw/emdat/admin_combined_0_to_4.pmtiles", layer = "admin",
                  wkt_filter = wkt, options = "ZOOM_LEVEL=10", quiet = TRUE),
      error = function(e) NULL
    )
    if (is.null(ed) || nrow(ed) == 0) next
    keep <- which(ed$adm0_src == gid0)
    if (length(keep) == 0) next
    ed_sub <- sf::st_make_valid(ed[keep, ])
    edt <- as.data.table(sf::st_drop_geometry(ed_sub))
    ed_cent <- suppressWarnings(sf::st_coordinates(sf::st_centroid(ed_sub)))
    edt[, cx := ed_cent[, 1]]; edt[, cy := ed_cent[, 2]]
    edt[, leaf_name_n := norm_name(fifelse(!is.na(adm4_name), adm4_name,
                                    fifelse(!is.na(adm3_name), adm3_name,
                                    fifelse(!is.na(adm2_name), adm2_name, adm1_name))))]
    edt[, cx_key := paste(cx, cy)]
    xy_str <- name_space_fallback(units, edt)
    units[, xy_key := xy_str]
    emdat_results[[gid0]] <- units[!is.na(xy_key)]
  }
  emdat_all <- rbindlist(emdat_results, fill = TRUE)
  if (nrow(emdat_all) > 0) {
    emdat_all[, c("ex", "ey") := tstrsplit(xy_key, " ", fixed = TRUE, type.convert = TRUE)]
    pts_ll <- sf::st_transform(sf::st_as_sf(emdat_all, coords = c("ex", "ey"), crs = 3857), 4326)
    ll <- sf::st_coordinates(pts_ll)
    emdat_all[, GID_2 := mapply(nearest_gadm, GID_0, ll[, 1], ll[, 2])]
    emdat_all <- emdat_all[!is.na(GID_2)]
  }
  cat(sprintf("emdat matched: %d\n", nrow(emdat_all)))

  cat("\n--- Tier 5: OCHA COD-AB fallback (BFA/BTN/POL/VEN/ZAF) ---\n")
  ocha_targets <- c("BFA", "BTN", "POL", "VEN", "ZAF")
  matched_now <- unique(rbind(matched_so_far, if (nrow(emdat_all) > 0) emdat_all[, .(id_2, GID_0)] else matched_so_far[0]))
  still_ocha <- fsetdiff(hr_units_all[GID_0 %in% ocha_targets, .(id_2, GID_0)], matched_now[GID_0 %in% ocha_targets])
  still_ocha <- merge(still_ocha, hr_units_all, by = c("id_2", "GID_0"))
  ocha_results <- list()
  if (nrow(still_ocha) > 0) {
    ocha_levels <- list()
    for (L in 1:4) {
      d <- sf::st_read("data/raw/global_admin_boundaries_matched_latest.gdb", layer = paste0("admin", L), quiet = TRUE)
      dt <- as.data.table(sf::st_drop_geometry(d))
      dt <- dt[iso3 %in% ocha_targets]
      if (nrow(dt) == 0) next
      d_sub <- sf::st_make_valid(d[d$iso3 %in% ocha_targets, ])
      cent <- suppressWarnings(sf::st_coordinates(sf::st_centroid(d_sub)))
      dt[, cx := cent[, 1]]; dt[, cy := cent[, 2]]
      dt[, leaf_name := get(paste0("adm", L, "_name"))]
      dt[, leaf_pcode := get(paste0("adm", L, "_pcode"))]
      dt[, leaf_name_n := norm_name(leaf_name)]
      ocha_levels[[as.character(L)]] <- dt[, .(iso3, leaf_pcode, leaf_name_n, cx, cy)]
    }
    all_ocha <- rbindlist(ocha_levels)
    for (gid0 in ocha_targets) {
      units <- still_ocha[GID_0 == gid0]
      cand <- all_ocha[iso3 == gid0]
      if (nrow(units) == 0 || nrow(cand) == 0) next
      cand[, cx_key := paste(cx, cy)]
      xy_str <- name_space_fallback(units, cand)
      units[, xy_key := xy_str]
      units <- units[!is.na(xy_key)]
      if (nrow(units) == 0) next
      units[, c("ex", "ey") := tstrsplit(xy_key, " ", fixed = TRUE, type.convert = TRUE)]
      units[, GID_2 := mapply(nearest_gadm, GID_0, ex, ey)]
      ocha_results[[gid0]] <- units[!is.na(GID_2), .(id_2, GID_0, GID_2)]
    }
  }
  ocha_all <- rbindlist(ocha_results, fill = TRUE)
  cat(sprintf("OCHA matched: %d\n", nrow(ocha_all)))

  cat("\n--- Tier 6: Brazil (IBGE municipal shapefile) ---\n")
  matched_now <- unique(rbindlist(list(matched_so_far,
    if (nrow(emdat_all) > 0) emdat_all[, .(id_2, GID_0)] else NULL,
    if (nrow(ocha_all) > 0) ocha_all[, .(id_2, GID_0)] else NULL), fill = TRUE))
  br_units <- fsetdiff(hr_units_all[GID_0 == "BRA", .(id_2, GID_0)], matched_now[GID_0 == "BRA"])
  br_units <- merge(br_units, hr_units_all, by = c("id_2", "GID_0"))
  br_sf <- sf::st_read("data/raw/BR_Municipios_2022/BR_Municipios_2022.shp", quiet = TRUE)
  br_dt <- as.data.table(sf::st_drop_geometry(br_sf))
  br_cent <- suppressWarnings(sf::st_coordinates(sf::st_centroid(br_sf)))
  br_dt[, cx := br_cent[, 1]]; br_dt[, cy := br_cent[, 2]]
  br_dt[, leaf_name_n := norm_name(NM_MUN)]
  br_dt[, cx_key := paste(cx, cy)]
  xy_str <- name_space_fallback(br_units, br_dt)
  br_units[, xy_key := xy_str]
  br_matched <- br_units[!is.na(xy_key)]
  if (nrow(br_matched) > 0) {
    br_matched[, c("ex", "ey") := tstrsplit(xy_key, " ", fixed = TRUE, type.convert = TRUE)]
    br_matched[, GID_2 := mapply(nearest_gadm, GID_0, ex, ey)]
    br_matched <- br_matched[!is.na(GID_2), .(id_2, GID_0, GID_2)]
  }
  cat(sprintf("Brazil (IBGE, name matched): %d\n", nrow(br_matched)))

  cat("--- Tier 6b: Brazil spatial-only fallback (corrupted-name units) ---\n")
  br_still <- fsetdiff(br_units[, .(id_2, GID_0)], if (nrow(br_matched) > 0) br_matched[, .(id_2, GID_0)] else br_units[0, .(id_2, GID_0)])
  br_still <- merge(br_still, hr_units_all, by = c("id_2", "GID_0"))
  br_spatial <- data.table()
  if (nrow(br_still) > 0) {
    nearest_muni <- function(px, py) {
      d <- sqrt((br_dt$cx - px)^2 + (br_dt$cy - py)^2)
      o <- order(d)
      if (d[o[1]] > 0.3) return(c(NA_real_, NA_real_))
      c(br_dt$cx[o[1]], br_dt$cy[o[1]])
    }
    res <- t(mapply(nearest_muni, br_still$x, br_still$y))
    br_still[, mcx := res[, 1]]; br_still[, mcy := res[, 2]]
    br_still <- br_still[!is.na(mcx)]
    br_still[, GID_2 := mapply(nearest_gadm, GID_0, mcx, mcy)]
    br_spatial <- br_still[!is.na(GID_2), .(id_2, GID_0, GID_2)]
  }
  cat(sprintf("Brazil (spatial-only, corrupted names): %d\n", nrow(br_spatial)))

  cat("\n--- Tier 7: Australia (ABS SA2 shapefile) ---\n")
  matched_now <- unique(rbindlist(list(matched_now[, .(id_2, GID_0)],
    if (nrow(br_matched) > 0) br_matched[, .(id_2, GID_0)] else NULL,
    if (nrow(br_spatial) > 0) br_spatial[, .(id_2, GID_0)] else NULL), fill = TRUE))
  au_units <- fsetdiff(hr_units_all[GID_0 == "AUS", .(id_2, GID_0)], matched_now[GID_0 == "AUS"])
  au_units <- merge(au_units, hr_units_all, by = c("id_2", "GID_0"))
  au_sf <- sf::st_read("data/raw/abs_sa2/SA2_2021_AUST_GDA2020.shp", quiet = TRUE)
  au_dt <- as.data.table(sf::st_drop_geometry(au_sf))
  au_cent <- suppressWarnings(sf::st_coordinates(sf::st_centroid(au_sf)))
  au_dt[, cx := au_cent[, 1]]; au_dt[, cy := au_cent[, 2]]
  au_dt[, leaf_name_n := norm_name(SA2_NAME21)]
  au_dt[, cx_key := paste(cx, cy)]
  xy_str <- name_space_fallback(au_units, au_dt)
  au_units[, xy_key := xy_str]
  au_matched <- au_units[!is.na(xy_key)]
  if (nrow(au_matched) > 0) {
    au_matched[, c("ex", "ey") := tstrsplit(xy_key, " ", fixed = TRUE, type.convert = TRUE)]
    au_matched[, GID_2 := mapply(nearest_gadm, GID_0, ex, ey)]
    au_matched <- au_matched[!is.na(GID_2), .(id_2, GID_0, GID_2)]
  }
  cat(sprintf("Australia (ABS, name matched): %d\n", nrow(au_matched)))

  cat("\n=== Assemble final crosswalk ===\n")
  final_xwalk <- rbindlist(list(
    hr_raw[!is.na(GID_2), .(id_2, GID_0, GID_2)],
    if (nrow(emdat_all) > 0) emdat_all[, .(id_2, GID_0, GID_2)] else NULL,
    if (nrow(ocha_all) > 0) ocha_all else NULL,
    br_matched, br_spatial, au_matched
  ), fill = TRUE)
  final_xwalk <- unique(final_xwalk, by = c("id_2", "GID_0"))
  n_final <- nrow(final_xwalk)
  cat(sprintf("TOTAL matched: %d / %d (%.1f%%)\n", n_final, n_total, 100 * n_final / n_total))

  hr_light <- merge(hr_raw[, .(id_2, GID_0, year, mean)], final_xwalk, by = c("id_2", "GID_0"))
  hr_light <- unique(hr_light, by = c("GID_2", "year"))
  setnames(hr_light, "GID_2", "gid_2")

  dir.create(dirname(cache_path), showWarnings = FALSE, recursive = TRUE)
  fwrite(hr_light, cache_path)
  cat(sprintf("Cached: %s (%d rows, %d regions)\n", cache_path, nrow(hr_light), uniqueN(hr_light$gid_2)))
}

cat(sprintf("\nLoaded panel: %d rows | %d regions\n", nrow(hr_light), uniqueN(hr_light$gid_2)))
hr_light[, ln_ntl := log(pmax(mean, 0) + 0.01)]

cat("\n=== Merge with our PLAD-derived is_birthregion ===\n")
ours <- fread("data/processed/analysis_panel.csv")[, .(gid_2, year, iso3, is_birthregion, has_leader, gid_0)]
d <- merge(hr_light[, .(gid_2, year, ln_ntl)], ours, by = c("gid_2", "year"))
cat(sprintf("Merged panel: %d rows | %d regions | %d countries\n",
    nrow(d), uniqueN(d$gid_2), uniqueN(d$iso3)))

cat("\n=== Archigos leader-spell clusters ===\n")
arch <- as.data.table(haven::read_dta("data/raw/archigos/Archigos_4.1.dta"))
arch[, startyear := as.integer(substr(startdate, 1, 4))]
arch[, endyear   := as.integer(substr(enddate,   1, 4))]
arch <- arch[!is.na(startyear) & !is.na(endyear)]
arch[, iso3 := suppressWarnings(countrycode::countrycode(ccode, "cown", "iso3c",
  custom_match = c("260" = "DEU", "340" = "SRB", "345" = "SRB", "678" = "YEM")))]
arch <- arch[!is.na(iso3)]

arch_yr <- arch[, {
  lo <- max(startyear, 1992L); hi <- min(endyear, 2013L)
  yrs <- if (lo > hi) integer(0) else seq(lo, hi)
  .(year = yrs, iso3 = iso3)
}, by = .(obsid)]
arch_yr <- arch_yr[year %between% c(1992, 2013)]
setorder(arch_yr, iso3, year, obsid)
arch_yr <- unique(arch_yr, by = c("iso3", "year"))
setorder(arch_yr, iso3, year)
arch_yr[, spell_cluster := shift(obsid, 1L), by = iso3]
arch_yr[is.na(spell_cluster), spell_cluster := obsid]

d <- merge(d, arch_yr[, .(iso3, year, spell_cluster)], by = c("iso3", "year"), all.x = TRUE)
d[is.na(spell_cluster), spell_cluster := iso3]

cat("\n=== HR exact-sample restriction (126-country, 1992-2009) ===\n")
hr126 <- fread("data/raw/plad/hr2014_126_countries.csv")
hr_65n <- fread("data/processed/hr_excluded_above65n_regions.csv")
d_hrex <- d[iso3 %in% hr126$iso3 & !gid_2 %in% hr_65n$gid_2 & year %between% c(1992, 2009)]
cat(sprintf("HRexact panel: %d rows | %d regions | %d countries\n",
    nrow(d_hrex), uniqueN(d_hrex$gid_2), uniqueN(d_hrex$iso3)))

cat("\n=== Regressions: Table II Col(1) ===\n")
run_reg <- function(dd, label) {
  setorder(dd, gid_2, year)
  d_fe <- fixest::panel(dd[!is.na(is_birthregion)], ~gid_2 + year)
  m <- fixest::feols(ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
                      data = d_fe, vcov = ~spell_cluster)
  cat(sprintf("\n%s: N=%d obs, %d regions\n", label, nobs(m), uniqueN(dd[!is.na(is_birthregion), gid_2])))
  print(fixest::etable(m, digits = 3))
  m
}

m_full <- run_reg(copy(d), "Track0, full sample (HR original NTL)")
m_hrex <- run_reg(copy(d_hrex), "Track0, HRexact (HR original NTL)")

cat("\n=== Comparison with HR 2014 Table II Col(1) ===\n")
cat("HR 2014:            0.038*** (0.014), N=690,495 obs, 38,427 regions\n")
report <- function(m, dd, label) {
  cf <- coef(m)[1]; se <- sqrt(diag(vcov(m)))[1]
  cat(sprintf("%-30s %.3f (%.3f), N=%d obs, %d regions\n",
      label, cf, se, nobs(m), uniqueN(dd[!is.na(is_birthregion), gid_2])))
}
report(m_full, d, "Track0, full sample:")
report(m_hrex, d_hrex, "Track0, HRexact:")

saveRDS(list(m_full = m_full, m_hrex = m_hrex), "data/processed/ntl/table2_track0_models.rds")
cat("\nModels saved: data/processed/ntl/table2_track0_models.rds\n")
