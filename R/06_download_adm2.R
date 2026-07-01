# R/06_download_adm2.R
# Purpose: Week 3 -- download ADM2 boundaries for all PLAD countries.
# Primary source: GADM 4.1 per-country JSON (geodata.ucdavis.edu).
# Fallback: geoBoundaries GitHub (if GADM fails or country missing).
# ADM1 fallback if ADM2 unavailable for a country.
#
# Resume-safe: completed entries logged to adm2_download_log.csv.
# Output files saved as {ISO3}_ADM2.geojson (or _ADM1.geojson for fallback).

library(data.table)
library(sf)

plad   <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
iso3s  <- sort(unique(plad$gid_0))
iso3s  <- iso3s[iso3s != "."]
gb_dir <- "data/raw/gadm_4.1/global/geoboundaries"
dir.create(gb_dir, showWarnings = FALSE, recursive = TRUE)

log_file <- "data/raw/gadm_4.1/global/adm2_download_log.csv"

if (file.exists(log_file)) {
  log  <- data.table::fread(log_file)
  done <- log$iso3
  cat(sprintf("Resuming -- already processed: %d / %d\n", length(done), length(iso3s)))
} else {
  log  <- data.table::data.table(iso3 = character(), status = character(), source = character())
  done <- character()
}

remaining <- iso3s[!iso3s %in% done]
cat(sprintf("%d countries remaining.\n\n", length(remaining)))

# Download a single file and validate it
.try_download <- function(url, dest) {
  res <- tryCatch(
    utils::download.file(url, dest, mode = "wb", quiet = TRUE),
    error   = function(e) -1L,
    warning = function(w) -1L
  )
  if (res == 0 && file.exists(dest) && file.size(dest) > 500) return(TRUE)
  suppressWarnings(try(file.remove(dest), silent = TRUE))
  FALSE
}

# Extract first .json/.geojson from a zip into dest path
.unzip_json <- function(zip_path, dest) {
  contents <- tryCatch(utils::unzip(zip_path, list = TRUE)$Name, error = function(e) NULL)
  if (is.null(contents)) return(FALSE)
  json_file <- contents[grepl("\\.(json|geojson)$", contents, ignore.case = TRUE)][1]
  if (is.na(json_file)) return(FALSE)
  tryCatch({
    utils::unzip(zip_path, files = json_file, exdir = dirname(dest))
    extracted <- file.path(dirname(dest), json_file)
    if (file.exists(extracted)) {
      file.rename(extracted, dest)
      return(file.exists(dest) && file.size(dest) > 500)
    }
    FALSE
  }, error = function(e) FALSE)
}

download_country <- function(iso3, level = 2) {
  lv  <- as.character(level)
  dest <- file.path(gb_dir, paste0(iso3, "_ADM", lv, ".geojson"))

  if (file.exists(dest) && file.size(dest) > 500) return(list(status = "cached", source = "existing"))

  # --- Primary: GADM 4.1 ---
  gadm_url <- paste0(
    "https://geodata.ucdavis.edu/gadm/gadm4.1/json/gadm41_", iso3, "_", lv, ".json.zip"
  )
  zip_tmp <- tempfile(fileext = ".zip")
  on.exit(suppressWarnings(file.remove(zip_tmp)), add = TRUE)

  if (.try_download(gadm_url, zip_tmp) && .unzip_json(zip_tmp, dest)) {
    return(list(status = paste0("ok_ADM", lv), source = "gadm"))
  }

  # --- Fallback: geoBoundaries GitHub ---
  gb_url <- paste0(
    "https://github.com/wmgeolab/geoBoundaries/raw/main/",
    "releaseData/gbOpen/", iso3, "/ADM", lv,
    "/geoBoundaries-", iso3, "-ADM", lv, ".geojson"
  )
  if (.try_download(gb_url, dest)) {
    return(list(status = paste0("ok_ADM", lv), source = "geoboundaries"))
  }

  # --- Try ADM1 if ADM2 failed ---
  if (level == 2) return(download_country(iso3, level = 1))

  return(list(status = "no_adm", source = NA_character_))
}

for (iso3 in remaining) {
  result <- tryCatch(download_country(iso3), error = function(e) list(status = "error", source = NA_character_))

  log <- rbind(log, data.table::data.table(
    iso3   = iso3,
    status = result$status,
    source = result$source
  ))
  data.table::fwrite(log, log_file)

  n_done <- nrow(log)
  pct    <- round(n_done / length(iso3s) * 100)
  cat(sprintf("[%3d%%] [%3d/%3d] %-6s  %-14s  %s\n",
              pct, n_done, length(iso3s), iso3, result$status,
              if (!is.na(result$source)) result$source else ""))
}

cat("\n--- Download summary ---\n")
print(log[, .N, by = .(status, source)][order(-N)])

no_adm <- log[status == "no_adm", iso3]
if (length(no_adm)) {
  writeLines(no_adm, "data/raw/gadm_4.1/global/no_adm2_countries.txt")
  cat("\nNo boundaries available:", paste(no_adm, collapse = ", "), "\n")
}
cat(sprintf("\nDone: %d / %d countries.\n",
            log[!status %in% c("no_adm", "error"), .N], length(iso3s)))
