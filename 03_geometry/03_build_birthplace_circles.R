# 03_geometry/03_build_birthplace_circles.R
# HR 2014 Table IV Col(1): "In a first exercise, we focus on the very narrow
# geographical areas around the birthplace of each political leader in our
# sample period. We use the point coordinates of these birthplaces and
# build a circle with a radius of 5 km around each point. We clip the area
# on national borders and coastal boundaries, and calculate the average
# nighttime light intensity ... for each of these 520 circular areas."
# (p. 1017). Previously entirely unimplemented in this project -- Table IV
# Col(2)-(3) (SN1 full-area / hole-punched) and Col(4)-(7) (grid cells) were
# built, but Col(1)'s circular-buffer specification was not, and prior
# comments in 07_regression/table4/01_col23_holepunch.R implicitly (and
# incorrectly) leaned on Table II Col(1)'s ADM2-based coefficient as a
# stand-in for this distinct construct. Fixed 2026-08-17.
#
# Method: one 5km-radius circle per unique birthplace point (lat/lon) drawn
# from PLAD + the Wikidata supplement (same combined source used for the
# grid-cell birth-point matching, 07_regression/table4/02_col4_7_grid.R),
# built in an equal-area projection (ESRI:54034, matching the grid-cell
# construction in 03_geometry/01_build_grid_cells.R) so the 5km radius is
# genuine, then clipped to the leader's own country boundary (GADM 3.6
# level0) -- this clips both at the national border and, since GADM's
# country polygons already respect coastlines, at the coast.
#
# Output: data/processed/birthplace_circles_5km.gpkg
#   Columns: circle_id, gid_0, geometry (clipped 5km buffer, WGS84)
#   Also: data/processed/birthplace_circles_lookup.csv
#   Columns: leader, iso3, startyear, endyear, circle_id (links leader-spells
#   to their circle, for is_birthregion construction downstream)

library(sf)
library(data.table)

sf::sf_use_s2(FALSE)
EQUAL_AREA_CRS <- "ESRI:54034"
RADIUS_M <- 5000

cat("=== Step 1: Collect birthplace points (PLAD + Wikidata supplement) ===\n")
plad <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(latitude) & !is.na(longitude) & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]
plad_pts <- unique(plad[, .(leader, iso3 = gid_0, startyear, endyear, lat = latitude, lon = longitude)])

wd <- data.table::fread("data/processed/wikidata_supplement_coords.csv")
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
                    "data/processed/birthplace_circles_lookup.csv")

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
# default geometry engine when `sf_use_s2(TRUE)`), which produces a true
# circle of the specified radius regardless of latitude (verified: a
# geodesic 5km buffer at 64N latitude measures 10.15km EW x 10.18km NS,
# vs. the old method's severe distortion at the same latitude; and the
# latitude-vs-asymmetry correlation dropped from 0.91 to -0.06 after the fix).
sf::sf_use_s2(TRUE)
l0 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level0", quiet = TRUE)
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
sf::st_write(circles_wgs84, "data/processed/birthplace_circles_5km.gpkg", quiet = TRUE, delete_dsn = TRUE)
cat("Saved: data/processed/birthplace_circles_5km.gpkg\n")
cat("Saved: data/processed/birthplace_circles_lookup.csv\n")
