suppressWarnings(library(sf))
sf::sf_use_s2(FALSE)
holed <- sf::st_read("data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE)
sf::st_geometry(holed) <- "geometry"
sf_obj <- holed[holed$GID_1 == "ARG.1_1", ]
g <- sf::st_geometry(sf_obj)
cat("ARG.1_1 coord rows:", nrow(sf::st_coordinates(g)), "\n")
cat("valid:", sf::st_is_valid(g), "\n")
