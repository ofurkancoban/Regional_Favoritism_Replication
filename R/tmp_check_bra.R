suppressWarnings(library(sf))
sf::sf_use_s2(FALSE)
holed <- sf::st_read("data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE)
sf::st_geometry(holed) <- "geometry"
sf_obj <- holed[holed$GID_0 == "BRA", ]
cat("BRA rows:", nrow(sf_obj), "\n")
for (i in seq_len(nrow(sf_obj))) {
  g <- sf::st_geometry(sf_obj[i,])
  cat(sprintf("%s: n_removed=%d, coord_rows=%d, valid=%s\n",
      sf_obj$GID_1[i], sf_obj$n_removed[i], nrow(sf::st_coordinates(g)), sf::st_is_valid(g)))
}
