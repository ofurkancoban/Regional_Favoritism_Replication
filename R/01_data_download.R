# R/01_data_download.R
# Purpose: download and validate administrative boundary data.
# Task 2.1: GADM 4.1 Turkey ADM1.
# Run after placing the GADM shapefile in data/raw/gadm_4.1/turkey/

library(sf)
library(ggplot2)

# ---- Task 2.1: Load and verify Turkey ADM1 ----

turkey_adm1_path <- "data/raw/gadm_4.1/turkey/gadm41_TUR_1.shp"

if (!file.exists(turkey_adm1_path)) {
  stop(
    "GADM 4.1 Turkey ADM1 shapefile not found.\n",
    "Download from https://gadm.org/download_country.html (select Turkey, ADM1).\n",
    "Place in data/raw/gadm_4.1/turkey/"
  )
}

tur_adm1 <- sf::st_read(turkey_adm1_path, quiet = TRUE)

stopifnot(
  "Turkey should have 81 provinces at ADM1" = nrow(tur_adm1) == 81
)

# Verify post-1990 provinces are present
post1990_provinces <- c("Bartın", "Karabük", "Yalova", "Kilis", "Osmaniye", "Düzce")
name_col <- names(tur_adm1)[grepl("NAME_1", names(tur_adm1))][1]
adm1_names <- tur_adm1[[name_col]]

missing <- post1990_provinces[
  !sapply(post1990_provinces, function(p) any(grepl(p, adm1_names, ignore.case = TRUE)))
]
if (length(missing) > 0) {
  warning("Post-1990 provinces not found by name: ", paste(missing, collapse = ", "),
          "\nCheck encoding or name variant in the shapefile.")
} else {
  message("All post-1990 provinces verified present.")
}

message("Province count: ", nrow(tur_adm1))
message("Columns: ", paste(names(tur_adm1), collapse = ", "))

# Save a verification map
dir.create("output/figures", showWarnings = FALSE, recursive = TRUE)
p <- ggplot2::ggplot(tur_adm1) +
  ggplot2::geom_sf(fill = "grey90", color = "black", linewidth = 0.2) +
  ggplot2::labs(title = "Turkey ADM1 provinces (GADM 4.1)",
                caption = paste0("n = ", nrow(tur_adm1), " provinces")) +
  ggplot2::theme_minimal()
ggplot2::ggsave("output/figures/turkey_adm1_check.pdf", p, width = 10, height = 6)
message("Map saved to output/figures/turkey_adm1_check.pdf")
