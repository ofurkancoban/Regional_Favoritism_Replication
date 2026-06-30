# R/01_data_download.R
# Purpose: download and validate GADM 4.1 administrative boundaries.
#   Task 2.1: Turkey ADM1 (81 provinces) -- pipeline test and Layer 2/3/4
#   Task 2.2: Global ADM2 (~1.5 GB) -- Layer 1 global replication panel
#
# GADM 4.1 GeoPackage URLs (single-file, no unzip needed for gpkg):
#   Turkey ADM1: https://geodata.ucdavis.edu/gadm/gadm4.1/gpkg/gadm41_TUR.gpkg
#   Global all levels: https://geodata.ucdavis.edu/gadm/gadm4.1/gadm_410-levels.zip
#
# Run from project root: Rscript R/01_data_download.R

library(sf)
library(ggplot2)

# ---- helpers ----

download_if_missing <- function(url, dest) {
  if (file.exists(dest)) {
    message("Already present, skipping download: ", dest)
    return(invisible(dest))
  }
  dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)
  message("Downloading: ", url)
  message("Destination: ", dest)
  utils::download.file(url, dest, mode = "wb", method = "auto")
  message("Done: ", dest)
  invisible(dest)
}

unzip_if_missing <- function(zip_path, exdir, sentinel_file) {
  if (file.exists(sentinel_file)) {
    message("Already extracted, skipping: ", sentinel_file)
    return(invisible(exdir))
  }
  message("Extracting: ", zip_path)
  utils::unzip(zip_path, exdir = exdir)
  message("Extracted to: ", exdir)
  invisible(exdir)
}

# ---- Task 2.1: Turkey ADM1 ----
# Primary source: GADM 4.1 (geodata.ucdavis.edu).
# Fallback: Natural Earth via rnaturalearth package (used when GADM server is down).
# Natural Earth has the same 81 provinces but slightly different column names.
# Switch back to GADM 4.1 once the server is accessible; column mappings may differ.

turkey_gpkg      <- "data/raw/gadm_4.1/turkey/gadm41_TUR.gpkg"
turkey_ne_gpkg   <- "data/raw/gadm_4.1/turkey/naturalearth_TUR_1.gpkg"

gb_adm1 <- "data/raw/gadm_4.1/turkey/geoboundaries_TUR_ADM1.geojson"
gb_adm1_url <- paste0(
  "https://github.com/wmgeolab/geoBoundaries/raw/main/",
  "releaseData/gbOpen/TUR/ADM1/geoBoundaries-TUR-ADM1.geojson"
)

if (file.exists(turkey_gpkg)) {
  tur_adm1 <- sf::st_read(turkey_gpkg, layer = "ADM_1", quiet = TRUE)
  message("Using GADM 4.1 Turkey ADM1.")
} else {
  # Try GADM first; fall back to geoBoundaries (GitHub) if unavailable
  tryCatch(
    download_if_missing(
      url  = "https://geodata.ucdavis.edu/gadm/gadm4.1/gpkg/gadm41_TUR.gpkg",
      dest = turkey_gpkg
    ),
    error = function(e) message("GADM server unreachable: ", conditionMessage(e))
  )

  if (file.exists(turkey_gpkg)) {
    tur_adm1 <- sf::st_read(turkey_gpkg, layer = "ADM_1", quiet = TRUE)
    message("Using GADM 4.1 Turkey ADM1.")
  } else {
    message("Falling back to geoBoundaries (GitHub)...")
    download_if_missing(url = gb_adm1_url, dest = gb_adm1)
    tur_adm1 <- sf::st_read(gb_adm1, quiet = TRUE)
    # Rename columns to match GADM 4.1 convention used downstream
    names(tur_adm1)[names(tur_adm1) == "shapeName"] <- "NAME_1"
    names(tur_adm1)[names(tur_adm1) == "shapeISO"]  <- "GID_1"
    message("Using geoBoundaries Turkey ADM1 (temporary substitute for GADM 4.1).")
  }
}

stopifnot(
  "Turkey should have 81 provinces at ADM1" = nrow(tur_adm1) == 81
)

name_col <- names(tur_adm1)[grepl("NAME_1", names(tur_adm1))][1]
adm1_names <- tur_adm1[[name_col]]

post1990_provinces <- c("Bartin", "Karabuk", "Yalova", "Kilis", "Osmaniye", "Duzce")
missing_prov <- post1990_provinces[
  !sapply(post1990_provinces, function(p) any(grepl(p, adm1_names, ignore.case = TRUE)))
]
if (length(missing_prov) > 0) {
  warning("Post-1990 provinces not matched by name: ", paste(missing_prov, collapse = ", "),
          "\nCheck encoding or name variant in the GeoPackage.")
} else {
  message("All post-1990 provinces verified present.")
}

message("Turkey ADM1 province count: ", nrow(tur_adm1))

dir.create("output/figures", showWarnings = FALSE, recursive = TRUE)
p <- ggplot2::ggplot(tur_adm1) +
  ggplot2::geom_sf(fill = "grey90", color = "black", linewidth = 0.2) +
  ggplot2::labs(
    title   = "Turkey ADM1 provinces (GADM 4.1)",
    caption = paste0("n = ", nrow(tur_adm1), " provinces")
  ) +
  ggplot2::theme_minimal()
ggplot2::ggsave("output/figures/turkey_adm1_check.pdf", p, width = 10, height = 6)
message("Verification map saved to output/figures/turkey_adm1_check.pdf")

# ---- Task 2.2: Global ADM2 ----
# Primary: GADM 4.1 global levels zip (~1.5 GB). Deferred to Week 3 when server is up.
# Fallback: geoBoundaries open API (https://www.geoboundaries.org), free, no auth.
#   geoBoundaries provides ADM1 and ADM2 per country as GeoJSON via REST API.
#   Coverage: ~200 countries. ADM2 missing for ~20 small countries (use ADM1 as substitute,
#   same approach as Bora 2025 Section 3.3).
#
# This function downloads ADM2 boundaries for a single country from geoBoundaries.
# Used in Week 3 panel construction if GADM remains unavailable.

download_geoboundaries <- function(iso3, level = "ADM2",
                                   outdir = "data/raw/gadm_4.1/global/geoboundaries") {
  dest <- file.path(outdir, paste0(iso3, "_", level, ".geojson"))
  if (file.exists(dest)) return(invisible(dest))
  dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
  url <- paste0("https://www.geoboundaries.org/api/current/", level, "/", iso3, "/")
  resp <- tryCatch(
    jsonlite::fromJSON(url),
    error = function(e) NULL
  )
  if (is.null(resp) || is.null(resp$gjDownloadURL)) {
    message("geoBoundaries: no ", level, " for ", iso3, "; trying ADM1 fallback.")
    if (level == "ADM2") return(download_geoboundaries(iso3, "ADM1", outdir))
    return(invisible(NULL))
  }
  utils::download.file(resp$gjDownloadURL, dest, mode = "wb", quiet = TRUE)
  invisible(dest)
}

global_gadm_zip <- "data/raw/gadm_4.1/global/gadm_410-levels.zip"
global_adm2_shp <- "data/raw/gadm_4.1/global/gadm_410-levels/gadm_410-2.shp"

if (file.exists(global_adm2_shp)) {
  message("Global ADM2 (GADM 4.1) already extracted. Reading...")
  global_adm2 <- sf::st_read(global_adm2_shp, quiet = TRUE)
  message("Global ADM2 region count: ", nrow(global_adm2))
} else {
  message("GADM 4.1 global ADM2 not available locally.")
  message("Will download via GADM when server is accessible (Week 3).")
  message("geoBoundaries fallback is available via download_geoboundaries(iso3) function.")
  message("Example: download_geoboundaries('TUR') for Turkey.")
  message("Skipping global ADM2 download -- re-run this block in Week 3.")
}
