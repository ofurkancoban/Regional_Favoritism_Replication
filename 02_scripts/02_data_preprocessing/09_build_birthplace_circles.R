# ==============================================================================
# File:          09_build_birthplace_circles.R
# Project:       Regional Favoritism: A Replication and Extension of
#                Hodler & Raschky (2014)
# Author:        Ömer Furkan Çoban
#
# University:    Carl von Ossietzky University of Oldenburg
# Department:    Applied Economics and Data Science
# Course:        Applied Econometrics Using GIS Techniques
# Semester:      SoSe 2026
# Lecturer:      Prof. Dr. Erkan Gören
#
# Category:      Data Preprocessing
#
# Description:   Builds 5km-radius circles around each leader's birthplace, clipped to national borders/coastlines, for Table IV Column (1).
#
# Inputs:        01_datasets/raw/plad/PLAD_April_2024.tab
# Outputs:       01_datasets/processed/birthplace_circles_5km.gpkg
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

sf::sf_use_s2(FALSE)
EQUAL_AREA_CRS <- "ESRI:54034"
RADIUS_M <- 5000

cat("=== Step 1: Collect birthplace points (PLAD + Wikidata supplement) ===\n")
plad <- data.table::fread(here::here("01_datasets/raw/plad/PLAD_April_2024.tab"), sep = "\t")
plad <- plad[!is.na(latitude) & !is.na(longitude) & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]
plad_pts <- unique(plad[, .(leader, iso3 = gid_0, startyear, endyear, lat = latitude, lon = longitude)])

wd <- data.table::fread(here::here("01_datasets/processed/wikidata_supplement_coords.csv"))
wd_pts <- unique(wd[, .(leader, iso3, startyear, endyear, lat, lon)])

pts <- unique(rbind(plad_pts, wd_pts))
cat(sprintf("Leader-spell birthplace records: %d\n", nrow(pts)))

cat("\n=== Step 2: Assign circle_id per unique rounded coordinate (shared birthplaces share a circle) ===\n")
# Round to ~10m precision before grouping -- avoids spurious duplicate
# circles from floating-point noise in coordinates that are, for practical
# purposes, the same point.
pts[, lat_r := round(lat, 4)]
pts[, lon_r := round(lon, 4)]
uniq_coords <- unique(pts[, .(lat_r, lon_r, iso3)])
uniq_coords[, circle_id := sprintf("CIRC_%05d", .I)]
cat(sprintf("Unique birthplace coordinates (circles to build): %d\n", nrow(uniq_coords)))

pts <- merge(pts, uniq_coords, by = c("lat_r", "lon_r", "iso3"))
data.table::fwrite(pts[, .(leader, iso3, startyear, endyear, circle_id)],
                    here::here("01_datasets/processed/birthplace_circles_lookup.csv"))

cat("\n=== Step 3: Build 5km circles (GEODESIC buffer), clipped to each leader's own country boundary ===\n")
# FIX (2026-08-18): buffering in a single global equal-area CRS (ESRI:54034,
# Lambert Cylindrical Equal Area) preserves each circle's AREA but not its
# SHAPE -- verified empirically that circles built this way are severely
# elongated ellipses away from the equator (e.g. at Iceland's latitude,
# ~65N, the "5km circle" was actually 4.1km east-west by 24.2km
# north-south; correlation between this east-west/north-south asymmetry
# and absolute latitude was 0.91 across all circles). This means the
# buffer was sampling DMSP pixels well beyond 5km in one direction while
# excluding genuinely-within-5km pixels in the other. Fixed by buffering
# geodesically on the sphere/ellipsoid directly in WGS84 via s2 (sf's
# default geometry engine when `sf::sf_use_s2(TRUE)`), which produces a true
# circle of the specified radius regardless of latitude (verified: a
# geodesic 5km buffer at 64N latitude measures 10.15km EW x 10.18km NS,
# vs. the old method's severe distortion at the same latitude; and the
# latitude-vs-asymmetry correlation dropped from 0.91 to -0.06 after the fix).
sf::sf_use_s2(TRUE)
l0 <- sf::st_read(here::here("01_datasets/raw/gadm_3.6/gadm36_levels.gpkg"), layer = "level0", quiet = TRUE)
sf::st_geometry(l0) <- "geometry"
l0 <- sf::st_make_valid(l0)

pts_sf <- sf::st_as_sf(uniq_coords, coords = c("lon_r", "lat_r"), crs = 4326)
buffers <- sf::st_buffer(pts_sf, dist = RADIUS_M)

clipped_list <- vector("list", nrow(buffers))
for (i in seq_len(nrow(buffers))) {
  iso <- buffers$iso3[i]
  country_poly <- l0[l0$GID_0 == iso, ]
  if (nrow(country_poly) == 0) {
    clipped_list[[i]] <- NULL
    next
  }
  clip <- tryCatch(
    sf::st_intersection(sf::st_geometry(buffers[i, ]), sf::st_union(sf::st_geometry(country_poly))),
    error = function(e) NULL
  )
  if (is.null(clip) || length(clip) == 0 || sf::st_is_empty(clip)[1]) {
    clipped_list[[i]] <- NULL
    next
  }
  clipped_list[[i]] <- sf::st_sf(circle_id = buffers$circle_id[i], gid_0 = iso, geometry = clip)
}
clipped_list <- clipped_list[!sapply(clipped_list, is.null)]
circles <- do.call(rbind, clipped_list)
cat(sprintf("Circles successfully clipped to country boundary: %d / %d\n", nrow(circles), nrow(buffers)))

circles_wgs84 <- sf::st_transform(circles, 4326)
sf::st_write(circles_wgs84, here::here("01_datasets/processed/birthplace_circles_5km.gpkg"), quiet = TRUE, delete_dsn = TRUE)
cat("Saved: data/processed/birthplace_circles_5km.gpkg\n")
cat("Saved: data/processed/birthplace_circles_lookup.csv\n")
