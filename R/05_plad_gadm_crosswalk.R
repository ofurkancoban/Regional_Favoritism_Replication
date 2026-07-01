# R/05_plad_gadm_crosswalk.R
# Purpose: build PLAD-GADM ADM1 crosswalk using direct GID code matching.
# PLAD stores birthplace as GADM 3.6 GID codes (e.g. TUR.40_1).
# GADM 4.1 uses the same GID scheme with minor version differences.
# Strategy: exact GID match first, then name-based fallback for mismatches.
# Output: data/processed/plad_gadm_crosswalk.csv

library(data.table)
library(sf)
library(stringdist)

plad   <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
gb_dir <- "data/raw/gadm_4.1/global/geoboundaries"

# Unique birthplace records
bp <- unique(plad[!is.na(gid_1) & gid_1 != ".", .(gid_0, gid_1, adm1)])
cat("Unique (country, ADM1) birthplace combinations in PLAD:", nrow(bp), "\n")
cat("Unique countries:", uniqueN(bp$gid_0), "\n")

# Build crosswalk per country
rows <- data.table::rbindlist(lapply(unique(bp$gid_0), function(iso3) {
  plad_sub <- bp[gid_0 == iso3]

  # Load GADM ADM1 for this country (prefer ADM1 file)
  adm1_path <- file.path(gb_dir, paste0(iso3, "_ADM1.geojson"))
  adm2_path <- file.path(gb_dir, paste0(iso3, "_ADM2.geojson"))
  geo_path  <- if (file.exists(adm1_path)) adm1_path else if (file.exists(adm2_path)) adm2_path else NA_character_

  if (is.na(geo_path)) {
    return(plad_sub[, .(gid_0, gid_1, adm1_plad = adm1,
                        gadm_gid1 = NA_character_, gadm_name1 = NA_character_,
                        match_type = "no_file")])
  }

  gadm <- tryCatch(sf::st_read(geo_path, quiet = TRUE), error = function(e) NULL)
  if (is.null(gadm)) {
    return(plad_sub[, .(gid_0, gid_1, adm1_plad = adm1,
                        gadm_gid1 = NA_character_, gadm_name1 = NA_character_,
                        match_type = "read_error")])
  }

  # Determine GID and name columns (GADM: GID_1/NAME_1; geoBoundaries: shapeID/shapeName)
  gid_col  <- if ("GID_1"     %in% names(gadm)) "GID_1"     else
              if ("GID_2"     %in% names(gadm)) "GID_2"     else
              if ("shapeID"   %in% names(gadm)) "shapeID"   else NA
  name_col <- if ("NAME_1"    %in% names(gadm)) "NAME_1"    else
              if ("NAME_2"    %in% names(gadm)) "NAME_2"    else
              if ("shapeName" %in% names(gadm)) "shapeName" else NA

  gadm_dt <- data.table::as.data.table(sf::st_drop_geometry(gadm))

  data.table::rbindlist(lapply(seq_len(nrow(plad_sub)), function(j) {
    pg  <- plad_sub$gid_1[j]
    pn  <- plad_sub$adm1[j]

    # 1. Exact GID match (only possible for GADM files)
    idx <- if (!is.na(gid_col)) which(gadm_dt[[gid_col]] == pg) else integer(0)
    if (length(idx) > 0) {
      return(data.table(gid_0 = iso3, gid_1 = pg, adm1_plad = pn,
                        gadm_gid1  = gadm_dt[[gid_col]][idx[1]],
                        gadm_name1 = if (!is.na(name_col)) gadm_dt[[name_col]][idx[1]] else NA_character_,
                        match_type = "exact_gid"))
    }

    # 2. Exact name match (handles GID version differences between GADM 3.6 and 4.1)
    if (!is.na(name_col)) {
      idx2 <- which(tolower(gadm_dt[[name_col]]) == tolower(pn))
      if (length(idx2) > 0) {
        return(data.table(gid_0 = iso3, gid_1 = pg, adm1_plad = pn,
                          gadm_gid1  = gadm_dt[[gid_col]][idx2[1]],
                          gadm_name1 = gadm_dt[[name_col]][idx2[1]],
                          match_type = "exact_name"))
      }

      # 3. Fuzzy name match (Jaro-Winkler >= 0.92)
      dists <- stringdist::stringdist(tolower(pn), tolower(gadm_dt[[name_col]]), method = "jw")
      best  <- which.min(dists)
      if (dists[best] <= 0.08) {
        return(data.table(gid_0 = iso3, gid_1 = pg, adm1_plad = pn,
                          gadm_gid1  = gadm_dt[[gid_col]][best],
                          gadm_name1 = gadm_dt[[name_col]][best],
                          match_type = "fuzzy_name"))
      }
    }

    data.table(gid_0 = iso3, gid_1 = pg, adm1_plad = pn,
               gadm_gid1 = NA_character_, gadm_name1 = NA_character_,
               match_type = "unmatched")
  }))
}), fill = TRUE)

cat("\nCrosswalk match summary:\n")
print(rows[, .N, by = match_type][order(-N)])

matched_types <- c("exact_gid", "exact_name", "fuzzy_name")
n_matched <- rows[match_type %in% matched_types, .N]
cat(sprintf("\nMatch rate: %.1f%%  (%d / %d)\n", n_matched / nrow(rows) * 100, n_matched, nrow(rows)))

unmatched <- rows[match_type == "unmatched"]
if (nrow(unmatched) > 0) {
  cat("\nUnmatched (", nrow(unmatched), "):\n")
  print(unmatched[, .(gid_0, gid_1, adm1_plad)])
}

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
data.table::fwrite(rows, "data/processed/plad_gadm_crosswalk.csv")
cat("\nSaved: data/processed/plad_gadm_crosswalk.csv (", nrow(rows), "rows)\n")
