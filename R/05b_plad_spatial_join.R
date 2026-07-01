# R/05b_plad_spatial_join.R
# Purpose: resolve unmatched PLAD entries via point-in-polygon spatial join.
# Uses PLAD lat/lon coordinates to find the GADM polygon containing the birthplace.
# Updates data/processed/plad_gadm_crosswalk.csv in-place.

library(data.table)
library(sf)

cw     <- data.table::fread("data/processed/plad_gadm_crosswalk.csv")
plad   <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
gb_dir <- "data/raw/gadm_4.1/global/geoboundaries"

unm <- cw[match_type == "unmatched"]
cat("Unmatched entries:", nrow(unm), "\n")

# Attach coordinates from PLAD
coords <- unique(plad[!is.na(latitude) & !is.na(longitude) & latitude != 0,
                      .(gid_0, gid_1, latitude, longitude)])
unm_c  <- merge(unm[, .(gid_0, gid_1, adm1_plad)], coords, by = c("gid_0", "gid_1"))
unm_c  <- unique(unm_c, by = c("gid_0", "gid_1"))
cat("With coordinates:", nrow(unm_c), "/", nrow(unm), "\n")

pip_results <- data.table::rbindlist(lapply(unique(unm_c$gid_0), function(iso3) {
  rows <- unm_c[gid_0 == iso3]

  # Try ADM2 first, then ADM1
  geo_file <- NULL
  for (suf in c("_ADM2.geojson", "_ADM1.geojson")) {
    p <- file.path(gb_dir, paste0(iso3, suf))
    if (file.exists(p)) { geo_file <- p; break }
  }
  if (is.null(geo_file)) {
    rows[, `:=`(gadm_gid1 = NA_character_, gadm_name1 = NA_character_, match_type = "no_file")]
    return(rows[, .(gid_0, gid_1, adm1_plad, gadm_gid1, gadm_name1, match_type)])
  }

  gadm <- tryCatch(sf::st_read(geo_file, quiet = TRUE), error = function(e) NULL)
  if (is.null(gadm)) {
    rows[, `:=`(gadm_gid1 = NA_character_, gadm_name1 = NA_character_, match_type = "read_error")]
    return(rows[, .(gid_0, gid_1, adm1_plad, gadm_gid1, gadm_name1, match_type)])
  }
  gadm <- sf::st_make_valid(gadm)

  gid_col  <- if ("GID_1"     %in% names(gadm)) "GID_1"     else
              if ("GID_2"     %in% names(gadm)) "GID_2"     else
              if ("shapeID"   %in% names(gadm)) "shapeID"   else names(gadm)[1]
  name_col <- if ("NAME_1"    %in% names(gadm)) "NAME_1"    else
              if ("NAME_2"    %in% names(gadm)) "NAME_2"    else
              if ("shapeName" %in% names(gadm)) "shapeName" else NA

  pts    <- sf::st_as_sf(rows, coords = c("longitude", "latitude"), crs = 4326)
  joined <- sf::st_join(pts, gadm[, c(gid_col, if (!is.na(name_col)) name_col)],
                        join = sf::st_within)
  res <- data.table::as.data.table(joined)

  res[, .(gid_0, gid_1, adm1_plad,
          gadm_gid1  = get(gid_col),
          gadm_name1 = if (!is.na(name_col)) get(name_col) else NA_character_,
          match_type = data.table::fifelse(!is.na(get(gid_col)), "spatial_join", "spatial_nomatch"))]
}), fill = TRUE)

cat("\nSpatial join results:\n")
print(pip_results[, .N, by = match_type])

# Update crosswalk
cw_new <- data.table::copy(cw)
for (i in seq_len(nrow(pip_results))) {
  if (pip_results$match_type[i] == "spatial_join") {
    idx <- which(cw_new$gid_0 == pip_results$gid_0[i] &
                 cw_new$gid_1 == pip_results$gid_1[i])
    if (length(idx)) {
      cw_new[idx, gadm_gid1  := pip_results$gadm_gid1[i]]
      cw_new[idx, gadm_name1 := pip_results$gadm_name1[i]]
      cw_new[idx, match_type := "spatial_join"]
    }
  }
}

matched <- c("exact_gid", "exact_name", "fuzzy_name", "spatial_join")
n_matched <- cw_new[match_type %in% matched, .N]
cat(sprintf("\nFinal match rate: %.1f%%  (%d / %d)\n", n_matched / nrow(cw_new) * 100, n_matched, nrow(cw_new)))
cat("\nFinal summary:\n")
print(cw_new[, .N, by = match_type][order(-N)])

still_unm <- cw_new[match_type %in% c("unmatched", "spatial_nomatch")]
if (nrow(still_unm) > 0) {
  cat("\nStill unmatched (", nrow(still_unm), "):\n")
  print(still_unm[, .(gid_0, gid_1, adm1_plad)])
}

data.table::fwrite(cw_new, "data/processed/plad_gadm_crosswalk.csv")
cat("\nCrosswalk updated: data/processed/plad_gadm_crosswalk.csv\n")
