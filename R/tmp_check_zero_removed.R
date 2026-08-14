suppressWarnings(library(sf))
sf::sf_use_s2(FALSE)
holed <- sf::st_read("data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE)
sf::st_geometry(holed) <- "geometry"
cat("n_removed==0 count:", sum(holed$n_removed == 0), "/", nrow(holed), "\n")
cat("n_removed>0 count:", sum(holed$n_removed > 0), "\n")
