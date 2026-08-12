# Purpose: Flag GADM 3.6 ADM2 regions as the settlement homeland of the
# ethnic group holding executive power in a given country-year, using EPR
# (Ethnic Power Relations, Core v2021) + GeoEPR (v2021) from ETH Zurich's
# International Conflict Research group.
#
# Motivation: HR 2014 and DHR (2025/2026) both measure "regional favoritism"
# using only the leader's literal birth region (PLAD). Neither decomposes
# whether the effect is really about the specific birthplace or about the
# leader's broader co-ethnic homeland -- a distinction the wider
# distributive-politics literature (Franck & Rainer 2012; Kramon & Posner
# 2012, 2013) treats as a genuinely open, debated question. This script
# builds the ethnic-homeland side of that comparison so a later regression
# script can include both `is_birthregion` (existing) and
# `is_ethnic_homeland` (new) in the same specification.
#
# Data:
#   EPR core (data/raw/epr/EPR-2021.csv): group-period rows with `status`
#     (MONOPOLY/DOMINANT/SENIOR PARTNER/JUNIOR PARTNER/POWERLESS/
#     DISCRIMINATED/IRRELEVANT/SELF-EXCLUSION/STATE COLLAPSE), keyed by
#     gwid (Gleditsch-Ward country code) + gwgroupid + from/to year range.
#   GeoEPR (data/raw/epr/GeoEPR-2021.geojson): matching group-period
#     polygons (settlement area), same gwgroupid + from/to keys, plus a
#     `type` field (Statewide/Regionally based/Regional & urban/Urban/
#     Aggregate/Dispersed/Migrant).
#
# "Ruling group" definition: status %in% c("MONOPOLY","DOMINANT",
# "SENIOR PARTNER") -- i.e., groups with meaningful access to executive
# power, not just token/junior inclusion. This mirrors EPR's own
# conventional threshold used in the ethnic-power-relations literature.
#
# "Homeland" definition: GeoEPR polygons with type %in% c("Regionally
# based","Regional & urban","Urban","Aggregate") -- excludes "Statewide"
# (group present nationwide -- would trivially flag every ADM2 as
# homeland) and "Dispersed"/"Migrant" (no bounded settlement area).
#
# Output: data/processed/ethnic_homeland_adm2.csv
#   Columns: GID_2, GID_0, year, is_ethnic_homeland, ruling_group, ruling_status
library(data.table)
library(sf)
library(countrycode)

sf::sf_use_s2(FALSE)

cat("=== Load EPR core (group status by country-year) ===\n")
epr <- fread("data/raw/epr/EPR-2021.csv")
epr[, iso3 := suppressWarnings(countrycode::countrycode(gwid, "gwn", "iso3c"))]
cat(sprintf("EPR core: %d group-periods | %d unmatched gwid (dropped)\n",
    nrow(epr), sum(is.na(epr$iso3))))
epr <- epr[!is.na(iso3)]

ruling_status <- c("MONOPOLY", "DOMINANT", "SENIOR PARTNER")
epr_ruling <- epr[status %in% ruling_status]
cat(sprintf("Ruling-status group-periods (%s): %d\n",
    paste(ruling_status, collapse = "/"), nrow(epr_ruling)))

# Expand to annual rows.
epr_ruling_yr <- epr_ruling[, .(year = from:to, iso3, gwgroupid, group, status, size),
                             by = .(row = seq_len(nrow(epr_ruling)))]
epr_ruling_yr[, row := NULL]

# Multiple groups can hold ruling status in the same country-year (e.g.
# several SENIOR PARTNERs in a power-sharing coalition), and even a single
# DOMINANT group can be demographically widespread rather than
# geographically concentrated -- both inflate the "homeland" flag to cover
# most of a country (median ~70% of ADM2 regions, tested 2026-08-21),
# leaving too little within-country variation to identify off. Restrict to
# only the single LARGEST ruling group per country-year (by EPR's own
# `size`, population share) -- the closest available proxy for "the
# group a given leader is most likely to belong to," analogous to how
# is_birthregion picks one specific point, not every region the leader
# has ever visited.
setorder(epr_ruling_yr, iso3, year, -size)
epr_ruling_yr <- epr_ruling_yr[, .SD[1], by = .(iso3, year)]
cat(sprintf("After keeping only the largest ruling group per country-year: %d rows\n", nrow(epr_ruling_yr)))
cat(sprintf("Expanded to %d country-group-year rows\n", nrow(epr_ruling_yr)))

cat("\n=== Load GeoEPR (group settlement polygons) ===\n")
geo <- sf::st_read("data/raw/epr/GeoEPR-2021.geojson", quiet = TRUE)
homeland_types <- c("Regionally based", "Regional & urban", "Urban", "Aggregate")
geo <- geo[geo$type %in% homeland_types, ]
cat(sprintf("GeoEPR polygons with a bounded homeland type: %d / %d (excluded: Statewide/Dispersed/Migrant)\n",
    nrow(geo), nrow(sf::st_read("data/raw/epr/GeoEPR-2021.geojson", quiet = TRUE))))

# Expand GeoEPR polygons to annual rows too, so they can be matched to
# epr_ruling_yr on (gwgroupid, year) even when the two datasets' from/to
# periods don't align exactly (GeoEPR's own periods reflect settlement
# stability, EPR core's periods reflect political status changes).
geo_dt <- as.data.table(sf::st_drop_geometry(geo))
geo_dt[, geo_row := .I]
geo_yr <- geo_dt[, .(year = from:to, gwgroupid, geo_row), by = .(row = seq_len(nrow(geo_dt)))]
geo_yr[, row := NULL]

cat("\n=== Match ruling groups to their settlement polygon by year ===\n")
matched <- merge(epr_ruling_yr, geo_yr, by = c("gwgroupid", "year"))
cat(sprintf("Ruling-group-years with a homeland polygon: %d / %d (%.1f%%)\n",
    uniqueN(matched, by = c("iso3", "year", "gwgroupid")), nrow(epr_ruling_yr),
    100 * uniqueN(matched, by = c("iso3", "year", "gwgroupid")) / nrow(epr_ruling_yr)))

cat("\n=== Load GADM 3.6 ADM2, compute centroids ===\n")
adm <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
adm <- adm[, c("GID_0", "GID_1", "GID_2")]
adm_cent <- sf::st_centroid(adm)

cat("\n=== Point-in-polygon: ADM2 centroid inside ruling group's homeland? ===\n")
# Process year by year to keep each spatial join small; within a year,
# union all matched countries' ruling-group polygons for that year so one
# st_join covers every country at once.
years_all <- sort(unique(matched$year))
cat(sprintf("Years to process: %d (%d-%d)\n", length(years_all), min(years_all), max(years_all)))

geo_sf <- geo[, c("gwgroupid")]
geo_sf$geo_row <- geo_dt$geo_row

results <- vector("list", length(years_all))
t0 <- Sys.time()
for (i in seq_along(years_all)) {
  yr <- years_all[i]
  m_yr <- matched[year == yr]
  if (nrow(m_yr) == 0) next

  polys_yr <- geo_sf[geo_sf$geo_row %in% m_yr$geo_row, ]
  if (nrow(polys_yr) == 0) next

  hit <- sf::st_join(adm_cent, polys_yr, join = sf::st_within, left = FALSE)
  if (nrow(hit) == 0) next

  hit_dt <- as.data.table(sf::st_drop_geometry(hit))
  hit_dt <- merge(hit_dt, m_yr[, .(geo_row, iso3, group, status)], by = "geo_row")
  hit_dt[, year := yr]
  results[[i]] <- unique(hit_dt[, .(GID_2, GID_0, year, ruling_group = group, ruling_status = status)])

  if (i %% 10 == 0) {
    cat(sprintf("[%d/%d years] elapsed %.1f min\n", i, length(years_all),
        as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  }
}
panel <- rbindlist(results, fill = TRUE)
panel[, is_ethnic_homeland := TRUE]

cat(sprintf("\nMatched ADM2-year rows: %d | %d regions | %d countries | years %d-%d\n",
    nrow(panel), uniqueN(panel$GID_2), uniqueN(panel$GID_0),
    min(panel$year), max(panel$year)))

fwrite(panel, "data/processed/ethnic_homeland_adm2_largest.csv")
cat("Saved: data/processed/ethnic_homeland_adm2_largest.csv\n")
cat("Note: this file lists only POSITIVE matches (is_ethnic_homeland = TRUE).\n")
cat("Downstream code should left-join onto the full panel and treat\n")
cat("non-matches as FALSE, the same convention used for is_birthregion.\n")
