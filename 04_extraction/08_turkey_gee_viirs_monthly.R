# 04_extraction/08_turkey_gee_viirs_monthly.R
# Monthly VIIRS nighttime lights for Turkey's 81 ADM1 provinces via Google
# Earth Engine, for the Kahramanmaras earthquake crisis-premium extension.
#
# Rationale: NASA's Black Marble VNP46A3 (monthly) is not itself in the GEE
# catalog, but its daily upstream product VNP46A2 (NASA/VIIRS/002/VNP46A2,
# same BRDF/lunar-corrected pipeline) is. We aggregate daily images to
# monthly composites server-side on GEE instead of downloading raw HDF5
# tiles from NASA LAADS and processing locally -- the LAADS-based pipeline
# (04_extraction/07_viirs_blackmarble_wget_monthly.R) has proven extremely
# slow this session (likely server-side throttling), while GEE runs the
# same reduction in Google's own infrastructure.
#
# Window: 2022-02 to 2024-02 (12 months before/after the 6 Feb 2023
# Kahramanmaras earthquake), per the crisis-premium extension design.
#
# Band: Gap_Filled_DNB_BRDF_Corrected_NTL (already gap-filled/BRDF-corrected,
# same underlying correction as VNP46A3's monthly composite), masked to
# Mandatory_Quality_Flag == 0 (highest quality retrievals only) before
# monthly averaging, matching the quality-flag filtering convention used
# throughout this project's other NTL extraction scripts.
#
# Output: data/processed/ntl/turkey_gee_viirs_monthly_adm1.csv
#   Columns: GID_1, NAME_1, year, month, viirs_ntl_mean, n_days

library(reticulate)
library(data.table)
library(sf)

reticulate::use_virtualenv("~/.virtualenvs/gee_research_env", required = TRUE)
ee <- reticulate::import("ee")
ee$Initialize(project = "regional-favoritism")

cat("=== Load Turkey ADM1 (GADM 4.1) ===\n")
adm1 <- sf::st_read("data/raw/gadm_4.1/turkey/gadm41_TUR_1.json", quiet = TRUE)
cat(sprintf("Provinces: %d\n", nrow(adm1)))

# Convert to an ee.FeatureCollection via GeoJSON round-trip (simplest
# reticulate-safe path -- avoids geojsonio/rgee dependency).
adm1_geojson <- sf::st_write(adm1, tempfile(fileext = ".geojson"), quiet = TRUE)
adm1_path <- attr(adm1_geojson, "path")
if (is.null(adm1_path)) {
  tmp_gj <- tempfile(fileext = ".geojson")
  sf::st_write(adm1, tmp_gj, quiet = TRUE)
  adm1_path <- tmp_gj
}
gj <- jsonlite::fromJSON(adm1_path, simplifyVector = FALSE)
fc <- ee$FeatureCollection(gj)

months <- seq(as.Date("2022-02-01"), as.Date("2024-02-01"), by = "month")
cat(sprintf("Months to process: %d (%s to %s)\n", length(months),
    format(months[1], "%Y-%m"), format(months[length(months)], "%Y-%m")))

out_dir <- "data/processed/ntl/turkey_gee_viirs_by_month"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

col <- ee$ImageCollection("NASA/VIIRS/002/VNP46A2")

for (m in months) {
  d <- as.Date(m, origin = "1970-01-01")
  ym <- format(d, "%Y-%m")
  out_file <- file.path(out_dir, paste0(ym, ".csv"))
  if (file.exists(out_file)) { cat(sprintf("[%s] cached, skipping\n", ym)); next }

  start <- format(d, "%Y-%m-%d")
  end   <- format(seq(d, by = "month", length.out = 2)[2], "%Y-%m-%d")

  monthly_col <- col$filterDate(start, end)$map(function(img) {
    qf   <- img$select("Mandatory_Quality_Flag")
    ntl  <- img$select("Gap_Filled_DNB_BRDF_Corrected_NTL")
    ntl$updateMask(qf$eq(0))
  })
  n_imgs <- monthly_col$size()$getInfo()
  if (n_imgs == 0) { cat(sprintf("[%s] no images, skipping\n", ym)); next }

  composite <- monthly_col$mean()$rename("viirs_ntl_mean")
  n_obs     <- monthly_col$count()$rename("n_days")
  stack     <- composite$addBands(n_obs)

  reduced <- stack$reduceRegions(
    collection = fc,
    reducer    = ee$Reducer$mean(),
    scale      = 500,
    tileScale  = 4
  )

  result <- tryCatch(reduced$getInfo(), error = function(e) {
    cat(sprintf("[%s] getInfo FAILED: %s\n", ym, conditionMessage(e)))
    NULL
  })
  if (is.null(result)) next

  feats <- result$features
  dt <- data.table::rbindlist(lapply(feats, function(f) {
    p <- f$properties
    data.table::data.table(
      GID_1          = p$GID_1,
      NAME_1         = p$NAME_1,
      year           = as.integer(format(d, "%Y")),
      month          = as.integer(format(d, "%m")),
      viirs_ntl_mean = p$viirs_ntl_mean,
      n_days         = p$n_days
    )
  }), fill = TRUE)

  data.table::fwrite(dt, out_file)
  cat(sprintf("[%s] rows=%d (n_images=%d)\n", ym, nrow(dt), n_imgs))
}

csv_files <- file.path(out_dir, paste0(format(months, "%Y-%m"), ".csv"))
if (all(file.exists(csv_files))) {
  panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
  data.table::fwrite(panel, "data/processed/ntl/turkey_gee_viirs_monthly_adm1.csv")
  cat(sprintf("\nPanel saved: %d rows, %d provinces, %d months\n",
      nrow(panel), data.table::uniqueN(panel$GID_1), length(csv_files)))
} else {
  cat(sprintf("\nNot all months done (%d/%d) -- panel assembly skipped.\n",
      sum(file.exists(csv_files)), length(csv_files)))
}
