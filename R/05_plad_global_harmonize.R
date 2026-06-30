# R/05_plad_global_harmonize.R
# Purpose: Week 2 -- harmonize PLAD GID_1 birthplace codes with geoBoundaries ADM1.
# For each unique (gid_0, gid_1) in PLAD, find the matching geoBoundaries ADM1 polygon.
# Output: data/processed/plad_gb_crosswalk.csv
#
# Strategy: PLAD uses GADM 3.6 GID codes (e.g. TUR.40_1). geoBoundaries uses its own
# shapeID system. We match on ISO3 country code + province name string similarity.
# Exact name match first; fuzzy fallback for unmatched.

library(data.table)
library(sf)

plad_path <- "data/raw/plad/PLAD_April_2024.tab"
gb_dir    <- "data/raw/gadm_4.1/global/geoboundaries"

plad <- data.table::fread(plad_path, sep = "\t")

# Unique birthplace records needed
bp <- unique(plad[!is.na(gid_1) & gid_1 != ".", .(gid_0, gid_1, adm1)])
cat("Unique (country, ADM1) birthplace combinations in PLAD:", nrow(bp), "\n")
cat("Unique countries:", length(unique(bp$gid_0)), "\n")

# ---- Download geoBoundaries ADM1 per country (only countries in PLAD) ----
iso3_needed <- unique(bp$gid_0)
cat("Need geoBoundaries ADM1 for", length(iso3_needed), "countries.\n")

dir.create(gb_dir, showWarnings = FALSE, recursive = TRUE)

download_gb_adm1 <- function(iso3) {
  dest <- file.path(gb_dir, paste0(iso3, "_ADM1.geojson"))
  if (file.exists(dest)) return(invisible(dest))
  url <- paste0(
    "https://github.com/wmgeolab/geoBoundaries/raw/main/",
    "releaseData/gbOpen/", iso3, "/ADM1/geoBoundaries-", iso3, "-ADM1.geojson"
  )
  result <- tryCatch(
    utils::download.file(url, dest, mode = "wb", quiet = TRUE),
    error   = function(e) -1L,
    warning = function(w) -1L
  )
  if (result != 0 || !file.exists(dest) || file.size(dest) < 100) {
    file.remove(dest)
    return(invisible(NULL))
  }
  invisible(dest)
}

# Download with progress
failed_iso3 <- character(0)
for (i in seq_along(iso3_needed)) {
  iso3 <- iso3_needed[i]
  path <- download_gb_adm1(iso3)
  if (is.null(path)) {
    failed_iso3 <- c(failed_iso3, iso3)
    if (i %% 10 == 0 || is.null(path)) cat(sprintf("  [%d/%d] %s: FAILED\n", i, length(iso3_needed), iso3))
  } else if (i %% 20 == 0) {
    cat(sprintf("  [%d/%d] done\n", i, length(iso3_needed)))
  }
}
cat("Downloaded:", length(iso3_needed) - length(failed_iso3), "/ Failed:", length(failed_iso3), "\n")
if (length(failed_iso3)) cat("Failed ISO3:", paste(failed_iso3, collapse = ", "), "\n")

# ---- Build crosswalk by name matching ----
crosswalk_rows <- data.table::rbindlist(lapply(iso3_needed, function(iso3) {
  plad_sub <- bp[gid_0 == iso3]
  dest     <- file.path(gb_dir, paste0(iso3, "_ADM1.geojson"))
  if (!file.exists(dest)) {
    return(plad_sub[, .(gid_0, gid_1, adm1_plad = adm1, gb_shapeName = NA_character_,
                        gb_shapeISO = NA_character_, match_type = "no_gb_file")])
  }
  gb_sf  <- tryCatch(sf::st_read(dest, quiet = TRUE), error = function(e) NULL)
  if (is.null(gb_sf)) {
    return(plad_sub[, .(gid_0, gid_1, adm1_plad = adm1, gb_shapeName = NA_character_,
                        gb_shapeISO = NA_character_, match_type = "read_error")])
  }
  gb_names <- gb_sf$shapeName
  gb_iso   <- gb_sf$shapeISO

  data.table::rbindlist(lapply(seq_len(nrow(plad_sub)), function(j) {
    plad_name <- plad_sub$adm1[j]
    # Exact match (case-insensitive)
    idx <- which(tolower(gb_names) == tolower(plad_name))
    if (length(idx) > 0) {
      return(data.table(gid_0 = iso3, gid_1 = plad_sub$gid_1[j],
                        adm1_plad = plad_name, gb_shapeName = gb_names[idx[1]],
                        gb_shapeISO = gb_iso[idx[1]], match_type = "exact"))
    }
    # Partial match: plad_name contained in gb_name or vice versa
    idx2 <- which(grepl(plad_name, gb_names, ignore.case = TRUE) |
                  grepl(gb_names,  plad_name, ignore.case = TRUE))
    if (length(idx2) > 0) {
      return(data.table(gid_0 = iso3, gid_1 = plad_sub$gid_1[j],
                        adm1_plad = plad_name, gb_shapeName = gb_names[idx2[1]],
                        gb_shapeISO = gb_iso[idx2[1]], match_type = "partial"))
    }
    # No match
    data.table(gid_0 = iso3, gid_1 = plad_sub$gid_1[j],
               adm1_plad = plad_name, gb_shapeName = NA_character_,
               gb_shapeISO = NA_character_, match_type = "unmatched")
  }))
}), fill = TRUE)

# ---- Summary ----
cat("\nCrosswalk match summary:\n")
print(crosswalk_rows[, .N, by = match_type])

unmatched <- crosswalk_rows[match_type == "unmatched"]
cat("\nUnmatched entries (", nrow(unmatched), "):\n")
if (nrow(unmatched) > 0) print(unmatched[, .(gid_0, gid_1, adm1_plad)])

# ---- Save ----
data.table::fwrite(crosswalk_rows, "data/processed/plad_gb_crosswalk.csv")
cat("\nSaved: data/processed/plad_gb_crosswalk.csv (", nrow(crosswalk_rows), " rows)\n")
