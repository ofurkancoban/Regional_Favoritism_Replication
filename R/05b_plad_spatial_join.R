# R/05b_plad_spatial_join.R
# Purpose: resolve remaining unmatched PLAD entries via point-in-polygon spatial join.
# Uses PLAD lat/lon coordinates to find the geoBoundaries ADM1 polygon that contains
# each birthplace point. This bypasses all name/encoding issues.

library(data.table)
library(sf)

cw     <- data.table::fread("data/processed/plad_gb_crosswalk.csv")
plad   <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
gb_dir <- "data/raw/gadm_4.1/global/geoboundaries"

unm <- cw[match_type == "unmatched"]

# Attach coordinates from PLAD (unique gid_0 + gid_1 + coordinates)
coords_plad <- unique(plad[!is.na(latitude) & !is.na(longitude) & latitude != 0,
                            .(gid_0, gid_1, latitude, longitude)])
unm_coords  <- merge(unm[, .(gid_0, gid_1, adm1_plad)], coords_plad,
                     by = c("gid_0", "gid_1"))
unm_coords  <- unique(unm_coords, by = c("gid_0", "gid_1"))
cat("Unmatched entries with coordinates:", nrow(unm_coords), "/", nrow(unm), "\n")

# Point-in-polygon per country
pip_results <- data.table::rbindlist(lapply(unique(unm_coords$gid_0), function(iso3) {
  rows <- unm_coords[gid_0 == iso3]
  dest <- file.path(gb_dir, paste0(iso3, "_ADM1.geojson"))
  if (!file.exists(dest)) {
    rows[, `:=`(gb_shapeName = NA_character_, gb_shapeISO = NA_character_,
                match_type = "no_gb_file")]
    return(rows[, .(gid_0, gid_1, adm1_plad, gb_shapeName, gb_shapeISO, match_type)])
  }
  gb_sf <- tryCatch(sf::st_read(dest, quiet = TRUE), error = function(e) NULL)
  if (is.null(gb_sf)) {
    rows[, `:=`(gb_shapeName = NA_character_, gb_shapeISO = NA_character_,
                match_type = "read_error")]
    return(rows[, .(gid_0, gid_1, adm1_plad, gb_shapeName, gb_shapeISO, match_type)])
  }
  gb_sf <- sf::st_make_valid(gb_sf)

  pts <- sf::st_as_sf(rows, coords = c("longitude", "latitude"), crs = 4326)
  joined <- sf::st_join(pts, gb_sf[, c("shapeName", "shapeISO")], join = sf::st_within)

  result <- data.table::as.data.table(joined)
  result[, .(gid_0, gid_1, adm1_plad,
             gb_shapeName = shapeName,
             gb_shapeISO  = shapeISO,
             match_type   = data.table::fifelse(!is.na(shapeName), "spatial_join", "spatial_nomatch"))]
}), fill = TRUE)

cat("Spatial join results:\n")
print(pip_results[, .N, by = match_type])

# Update crosswalk
cw_new <- copy(cw)
for (i in seq_len(nrow(pip_results))) {
  if (pip_results$match_type[i] == "spatial_join") {
    idx <- which(cw_new$gid_0 == pip_results$gid_0[i] &
                 cw_new$gid_1 == pip_results$gid_1[i])
    if (length(idx)) {
      cw_new[idx, gb_shapeName := pip_results$gb_shapeName[i]]
      cw_new[idx, gb_shapeISO  := pip_results$gb_shapeISO[i]]
      cw_new[idx, match_type   := "spatial_join"]
    }
  }
}

all_matched <- c("exact", "partial", "fuzzy", "translit_exact", "translit_fuzzy",
                 "manual_override", "spatial_join")
cat("\nFinal crosswalk summary:\n")
print(cw_new[, .N, by = match_type][order(-N)])
n_matched <- cw_new[match_type %in% all_matched, .N]
cat("Overall match rate:", round(n_matched / 710 * 100, 1), "%  (", n_matched, "/ 710 )\n")

# Remaining unmatched
still_unm <- cw_new[match_type == "unmatched"]
if (nrow(still_unm) > 0) {
  cat("\nStill unmatched (", nrow(still_unm), "):\n")
  print(still_unm[, .(gid_0, gid_1, adm1_plad)])
}

data.table::fwrite(cw_new, "data/processed/plad_gb_crosswalk.csv")
cat("\nCrosswalk saved: data/processed/plad_gb_crosswalk.csv\n")
