suppressWarnings(library(sf))
sf::sf_use_s2(FALSE)
holed <- sf::st_read("data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE)
sf::st_geometry(holed) <- "geometry"
iso3s <- sort(unique(holed$GID_0))
idx <- which(iso3s == "BOL")
cat("Next after BOL:", iso3s[idx+1], "\n")
