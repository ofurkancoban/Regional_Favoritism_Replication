suppressWarnings(library(sf))
sf::sf_use_s2(FALSE)
holed <- sf::st_read("data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE)
sf::st_geometry(holed) <- "geometry"
iso3s <- sort(unique(holed$GID_0))
idx <- which(iso3s == "ARE")
cat("Next 3 after ARE:", iso3s[(idx+1):(idx+3)], "\n")

next_iso <- iso3s[idx+1]
sf_obj <- holed[holed$GID_0 == next_iso, ]
cat("Country:", next_iso, "| rows:", nrow(sf_obj), "\n")
for (i in seq_len(nrow(sf_obj))) {
  g <- sf::st_geometry(sf_obj[i,])
  npts <- sum(sapply(sf::st_coordinates(g)[,1], length))
  cat(sprintf("  %s: n_removed=%d, n_coord_rows=%d, valid=%s\n",
      sf_obj$GID_1[i], sf_obj$n_removed[i], nrow(sf::st_coordinates(g)), sf::st_is_valid(g)))
}
