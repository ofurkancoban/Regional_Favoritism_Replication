suppressWarnings(library(sf))
sf::sf_use_s2(FALSE)
holed <- sf::st_read("data/processed/gadm_holepunched_adm1.gpkg", quiet = TRUE)
sf::st_geometry(holed) <- "geometry"
cat("file mtime:", format(file.info("data/processed/gadm_holepunched_adm1.gpkg")$mtime), "\n")
cat("total rows:", nrow(holed), "\n")
for (g in c("NZL.1_1", "NZL.14_1", "BRA.10_1", "ARG.1_1")) {
  sf_obj <- holed[holed$GID_1 == g, ]
  if (nrow(sf_obj) == 0) { cat(g, ": NOT FOUND\n"); next }
  geom <- sf::st_geometry(sf_obj)
  cat(sprintf("%s: n_removed=%d coord_rows=%d valid=%s\n",
      g, sf_obj$n_removed, nrow(sf::st_coordinates(geom)), sf::st_is_valid(geom)))
}
cat("\nsummary of all coord_rows:\n")
counts <- sapply(seq_len(nrow(holed)), function(i) nrow(sf::st_coordinates(sf::st_geometry(holed[i,]))))
print(summary(counts))
cat("top 5 most complex:\n")
ord <- order(-counts)[1:5]
print(data.frame(GID_1=holed$GID_1[ord], n_removed=holed$n_removed[ord], coord_rows=counts[ord]))
