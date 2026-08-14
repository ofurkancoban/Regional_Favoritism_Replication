suppressWarnings(library(sf))
sf::sf_use_s2(FALSE)

plad <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & gid_0 != "."]
cw36 <- data.table::fread("data/processed/gadm36_41_crosswalk.csv")
plad[cw36, on = .(gid_2 = gid2_36), gid_2_41 := i.gid2_41]
plad[, birth_gid2_final := data.table::fcase(!is.na(gid_2_41), gid_2_41, default = gid_2)]
ever_birth <- unique(plad[, .(gid_0, birth_gid2 = birth_gid2_final)])

l1 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level1", quiet = TRUE)
sf::st_geometry(l1) <- "geometry"
l2 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
sf::st_geometry(l2) <- "geometry"

for (gid1_target in c("NZL.1_1", "NZL.14_1")) {
  cat("\n===", gid1_target, "===\n")
  geom1_obj <- l1[l1$GID_1 == gid1_target, ]
  geom1 <- sf::st_geometry(geom1_obj)
  cat("raw ADM1 coord rows:", nrow(sf::st_coordinates(geom1)), "valid:", sf::st_is_valid(geom1), "\n")

  birth_children <- ever_birth$birth_gid2[ever_birth$gid_0 == "NZL"]
  child_polys <- l2[l2$GID_2 %in% birth_children, ]
  child_polys <- sf::st_make_valid(child_polys)
  cat("candidate children in NZL:", nrow(child_polys), "\n")

  # only children actually inside/touching this ADM1
  child_in <- child_polys[sf::st_intersects(child_polys, geom1_obj, sparse=FALSE)[,1], ]
  cat("children intersecting this ADM1:", nrow(child_in), "\n")
  if (nrow(child_in) > 0) {
    child_union <- sf::st_union(sf::st_geometry(child_in))
    cand <- sf::st_difference(geom1, child_union)
    cat("difference coord rows:", nrow(sf::st_coordinates(cand)), "valid:", sf::st_is_valid(cand), "\n")
    cand10 <- sf::st_simplify(cand, preserveTopology=TRUE, dTolerance=10)
    cat("after 10m simplify: coord rows:", nrow(sf::st_coordinates(cand10)), "valid:", sf::st_is_valid(cand10), "\n")
  }
}
