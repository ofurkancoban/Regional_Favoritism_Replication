# R/15_build_holepunched_adm1.R
# Purpose: For HR 2014 Table IV Col(3), build "hole-punched" ADM1 geometries --
# each affected ADM1 polygon with its ever-birth-region ADM2 sub-polygons
# geometrically removed (st_difference), at FULL GADM coordinate precision
# (the input geometry is never simplified). This lets us zonal-mean
# stable_lights over exactly the area HR describe: "SN1 regions ... but when
# calculating the average nighttime light intensity, we omit all SN2 regions
# in which a political leader from our sample was ever born" (p. 1018).
#
# Only ADM1s that actually contain an ever-birth ADM2 need modification
# (582 of 3,610 in our data) -- all other ADM1s are identical to the Col(2)
# full-area panel and do not need reprocessing.
#
# Parallelized across local CPU cores (future.apply) since full-precision
# st_difference on complex/archipelagic polygons is slow one-at-a-time.
#
# Post-difference cleanup: st_difference between two full-precision polygons
# produces large numbers of microscopic sliver artifacts along the shared
# boundary (floating-point/topological noise, not real geographic detail) --
# e.g. one Argentine province ballooned to 109,189 coordinate vertices after
# a single ADM2 was subtracted, which made the GEE zonal-mean request hang.
# We apply a 10 m simplification tolerance to the DIFFERENCE OUTPUT only
# (never to the input GADM boundaries). GEE's DMSP-OLS pixel scale is 1,000 m,
# so a 10 m tolerance changes no pixel's in/out zonal-mean membership -- it
# only removes sub-pixel numerical noise, not real boundary detail.
#
# Output: data/processed/gadm_holepunched_adm1.gpkg (582 modified polygons)

library(sf)
library(data.table)
library(future)
library(future.apply)

sf::sf_use_s2(FALSE)

cat("=== Identify affected ADM1s and their ever-birth ADM2 children ===\n")
plad <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & gid_0 != "."]
cw36 <- data.table::fread("data/processed/gadm36_41_crosswalk.csv")
plad[cw36, on = .(gid_2 = gid2_36), gid_2_41 := i.gid2_41]
plad[, birth_gid2_final := data.table::fcase(!is.na(gid_2_41), gid_2_41, default = gid_2)]
ever_birth <- unique(plad[, .(gid_0, birth_gid2 = birth_gid2_final)])
ever_birth[, gid1 := data.table::fcase(
  grepl("^[A-Z]{3}\\.[0-9]+\\.[0-9]+_[0-9]+$", birth_gid2),
  sub("(\\.[0-9]+)\\.[0-9]+_[0-9]+$", "\\1_1", birth_gid2),
  default = NA_character_
)]
ever_birth <- ever_birth[!is.na(gid1)]
affected_gid1 <- unique(ever_birth$gid1)
cat(sprintf("Affected ADM1: %d | Countries: %d | Birth ADM2 to remove: %d\n",
    length(affected_gid1), uniqueN(ever_birth$gid_0), uniqueN(ever_birth$birth_gid2)))

cat("\n=== Load GADM 3.6 level1 + level2 (full precision, no simplification) ===\n")
l1 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level1", quiet = TRUE)
sf::st_geometry(l1) <- "geometry"
l2 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
sf::st_geometry(l2) <- "geometry"

l1_affected <- l1[l1$GID_1 %in% affected_gid1, ]
cat(sprintf("Matched %d / %d affected ADM1 polygons in GADM 3.6\n",
    nrow(l1_affected), length(affected_gid1)))
l2_affected <- l2[l2$GID_2 %in% ever_birth$birth_gid2, ]
rm(l1, l2)

cat("\n=== Compute hole-punched geometry per affected ADM1 (parallel, full precision) ===\n")
n_workers <- max(1L, parallel::detectCores() - 1L)
cat(sprintf("Using %d parallel workers\n", n_workers))
# multicore (fork-based) avoids re-serializing sf objects into each worker,
# which was corrupting the sf geometry-column attribute under multisession.
future::plan(future::multicore, workers = n_workers)

# No simplification anywhere in this script -- geometry stays at full GADM
# precision. Complex/dense results (e.g. New Zealand's fjord coastline,
# ~250K vertices, which barely shrinks under simplification at any tolerance
# because it is a MultiPolygon of thousands of near-minimal-vertex islands)
# are handled downstream in R/16 by splitting the polygon into its
# constituent parts and uploading them as separate GEE chunks, then
# recombining with a pixel-count-weighted average -- not by altering the
# boundary itself.
hole_punch_one <- function(i, l1_affected, l2_affected, ever_birth) {
  gid1 <- l1_affected$GID_1[i]
  birth_children <- ever_birth[["birth_gid2"]][ever_birth$gid1 == gid1]
  child_polys <- l2_affected[l2_affected$GID_2 %in% birth_children, ]

  geom1 <- sf::st_geometry(l1_affected[i, ])
  holed_geom <- geom1
  if (nrow(child_polys) > 0) {
    child_union <- sf::st_union(sf::st_geometry(child_polys))
    cand <- tryCatch(sf::st_difference(geom1, child_union), error = function(e) {
      message(sprintf("[%s] st_difference FAILED: %s", gid1, conditionMessage(e)))
      NULL
    })
    if (!is.null(cand) && length(cand) == 1 && !sf::st_is_empty(cand)[1]) {
      holed_geom <- cand
    }
  }
  holed_geom <- sf::st_make_valid(holed_geom)

  sf::st_sf(GID_1 = gid1, GID_0 = l1_affected$GID_0[i],
            n_removed = nrow(child_polys), geometry = holed_geom)
}

t0 <- Sys.time()
holed_list <- future.apply::future_lapply(
  seq_len(nrow(l1_affected)),
  hole_punch_one,
  l1_affected = l1_affected, l2_affected = l2_affected, ever_birth = ever_birth,
  future.seed = TRUE
)
cat(sprintf("Elapsed: %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))

holed <- do.call(rbind, holed_list)
cat(sprintf("Hole-punched ADM1 polygons: %d\n", nrow(holed)))

cat("\n=== Save ===\n")
sf::st_write(holed, "data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE, delete_dsn = TRUE)
cat("Saved: data/processed/gadm_holepunched_adm1.gpkg\n")
