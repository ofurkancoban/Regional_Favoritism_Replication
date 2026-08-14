# 02_crosswalk/03_gadm36_41_crosswalk.R
# Purpose: Build a global GADM 3.6 -> 4.1 GID_2 crosswalk.
# Source: data/raw/gadm_3.6/gadm36_levels.gpkg (level2 layer)
# Method: centroid of each GADM 3.6 ADM2 -> spatial join to GADM 4.1 ADM2.

library(sf)
library(data.table)
sf::sf_use_s2(FALSE)

cat("=== Loading GADM 3.6 ADM2 ===\n")
sf36 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
sf36 <- sf::st_transform(sf36, 4326)
cat(sprintf("GADM 3.6 ADM2: %d regions\n", nrow(sf36)))
cat("Columns:", paste(names(sf36), collapse = ", "), "\n")

cat("\n=== Loading GADM 4.1 ADM2 from NTL panel ===\n")
# Load all GADM 4.1 GeoJSONs from geoboundaries folder
gb_dir <- "data/raw/gadm_4.1/global/geoboundaries"
adm2_files <- list.files(gb_dir, pattern = "_ADM2\\.geojson$", full.names = TRUE)
cat(sprintf("Found %d ADM2 files\n", length(adm2_files)))

sf41_list <- lapply(adm2_files, function(f) {
  x <- tryCatch(sf::st_read(f, quiet = TRUE), error = function(e) NULL)
  if (is.null(x)) return(NULL)
  # Standardize GID_2 column
  if ("GID_2" %in% names(x))    return(x[, "GID_2"])
  if ("shapeID" %in% names(x))  { x$GID_2 <- x$shapeID; return(x[, "GID_2"]) }
  NULL
})
sf41_list <- sf41_list[!sapply(sf41_list, is.null)]
sf41 <- do.call(rbind, sf41_list)
sf41 <- sf::st_transform(sf41, 4326)
cat(sprintf("GADM 4.1 ADM2: %d regions\n", nrow(sf41)))

cat("\n=== Centroid join: 3.6 -> 4.1 ===\n")
suppressWarnings({
  cents36 <- sf::st_centroid(sf36)
  cents36_sf <- sf::st_sf(
    gid2_36 = sf36$GID_2,
    gid0    = sf36$GID_0,
    geometry = sf::st_geometry(cents36)
  )
  joined <- sf::st_join(cents36_sf, sf41[, "GID_2"], join = sf::st_within, left = TRUE)
})

cw <- data.table::as.data.table(joined)[, .(
  gid2_36 = gid2_36,
  iso3    = gid0,
  gid2_41 = GID_2
)]

cat(sprintf("Total: %d | Matched: %d (%.1f%%)\n",
    nrow(cw), sum(!is.na(cw$gid2_41)), 100 * mean(!is.na(cw$gid2_41))))

data.table::fwrite(cw, "data/processed/gadm36_41_crosswalk.csv")
cat("Saved: data/processed/gadm36_41_crosswalk.csv\n")

# Summary by country
cat("\nUnmatched count by country (top 10):\n")
print(cw[is.na(gid2_41), .N, by = iso3][order(-N)][1:10])
