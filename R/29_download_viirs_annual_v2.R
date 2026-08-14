# R/29_download_viirs_annual_v2.R
# Purpose: Download raw VIIRS annual nighttime lights composites (EOG VNL v2
# family) directly from eogdata.mines.edu, WITHOUT going through Google Earth
# Engine. Band: average_masked (background-zeroed annual average radiance,
# the VIIRS analogue of DMSP's stable_lights -- persistent lighting only,
# ephemeral/noise sources removed).
#
# Version choice per year (see EOG VNL v2.1/v2.2 readmes):
#   - v2.1 for 2012-2021: v2.0 had a real bug (monthly average radiances were
#     sometimes paired with the WRONG month's cloud-free coverage count when
#     computing the weighted annual average); v2.1 fixes this. v2.0 must not
#     be used.
#   - v2.2 for 2022-2024: required because of an SNPP sensor glitch in
#     August 2022 (first 10 days missing) -- v2.2 fills the gap by mixing in
#     NOAA-20 (J01) data for that period, hence "npp-j01" in filenames.
#
# File names embed an unpredictable creation timestamp, so this script
# authenticates the same way as R/28_download_tif_from_har.R (EOG's own free
# account login, via Keycloak), then for each year fetches that year's
# directory LISTING page (still same authenticated session) and parses out
# the actual average_masked.*.tif.gz filename before downloading it.
#
# For 2012 (VIIRS DNB only available from April 2012), EOG publishes two
# composite periods -- this script uses the "201204-201212" (Apr-Dec 2012)
# period, the natural direct analogue of a calendar-year composite for the
# other years.
#
# Output: data/raw/viirs_raster_eog_manual/<year>/<original filename>.tif
# (downloaded .gz is decompressed and removed to save disk space).
# Resume-safe: existing decompressed .tif files are skipped.

suppressPackageStartupMessages({
  library(jsonlite)
})

load_env <- function(env_path = ".env") {
  if (file.exists(env_path)) {
    lines <- readLines(env_path, warn = FALSE)
    lines <- lines[grepl("^[A-Za-z_][A-Za-z0-9_]*=", lines)]
    for (line in lines) {
      parts <- strsplit(line, "=", fixed = TRUE)[[1]]
      key <- trimws(parts[1])
      val <- trimws(paste(parts[-1], collapse = "="))
      val <- gsub("^[\"']|[\"']$", "", val)
      if (Sys.getenv(key) == "") {
        do.call(Sys.setenv, setNames(list(val), key))
      }
    }
  }
}
load_env()

MIN_GZ_SIZE <- 50 * 1024 * 1024   # 50 MB floor for a valid average_masked.tif.gz

# --------------------------------------------------
# 1. Credentials (.env, with HAR fallback like R/28)
# --------------------------------------------------
eog_user <- Sys.getenv("EOG_USERNAME")
eog_pass <- Sys.getenv("EOG_PASSWORD")

if ((eog_user == "" || eog_pass == "") && file.exists("eogdata.mines.edu.har")) {
  har_data <- jsonlite::fromJSON("eogdata.mines.edu.har", simplifyVector = FALSE)
  for (entry in har_data$log$entries) {
    pd <- entry$request$postData
    if (!is.null(pd) && !is.null(pd$params)) {
      for (p in pd$params) {
        if (p$name == "username" && eog_user == "") eog_user <- utils::URLdecode(p$value)
        if (p$name == "password" && eog_pass == "") eog_pass <- utils::URLdecode(p$value)
      }
    }
  }
}

if (eog_user == "" || eog_pass == "") {
  stop("EOG credentials not found. Set EOG_USERNAME and EOG_PASSWORD in .env")
}
cat(sprintf("Using EOG account: %s\n", eog_user))

# --------------------------------------------------
# 2. Year -> version catalog
# --------------------------------------------------
years <- 2012:2024
year_version <- function(yr) if (yr <= 2021) "v21" else "v22"

base_url <- "https://eogdata.mines.edu/nighttime_light/annual"

listing_url <- function(yr) sprintf("%s/%s/%d/", base_url, year_version(yr), yr)

out_root <- "data/raw/viirs_raster_eog_manual"
dir.create(out_root, showWarnings = FALSE, recursive = TRUE)

# --------------------------------------------------
# 3. Authenticate (same Keycloak flow as R/28)
# --------------------------------------------------
# Wrapped in a function and re-run before EACH year (not just once at
# startup): the 2012 file alone is ~11.6GB and can take long enough to
# download+decompress that the EOG session cookie expires before the next
# year's request, which silently manifests as "NO FILE FOUND on listing
# page" for every subsequent year (looks like a missing-file problem but is
# actually an expired-session problem) -- this was the actual root cause of
# only 2012 succeeding on the previous run.
authenticate <- function() {
  cookie_jar <- tempfile(fileext = ".txt")
  login_page <- tempfile(fileext = ".html")
  first_url  <- listing_url(years[1])

  system2("curl", args = c(
    "-s", "-L", "-c", shQuote(cookie_jar), "-b", shQuote(cookie_jar),
    "-o", shQuote(login_page), shQuote(first_url)
  ))

  html_txt <- paste(readLines(login_page, warn = FALSE), collapse = "\n")
  action_match <- regmatches(html_txt, regexpr('action="[^"]*login-actions/authenticate[^"]*"', html_txt))

  if (length(action_match) == 0 || nchar(action_match[1]) == 0) {
    stop("Could not find Keycloak login action URL. Saved page at: ", login_page)
  }
  login_action <- sub('^action="', '', action_match[1])
  login_action <- sub('"$', '', login_action)
  login_action <- gsub('&amp;', '&', login_action, fixed = TRUE)

  post_page <- tempfile(fileext = ".html")
  post_body <- sprintf(
    "username=%s&password=%s&credentialId=",
    utils::URLencode(eog_user, reserved = TRUE),
    utils::URLencode(eog_pass, reserved = TRUE)
  )
  system2("curl", args = c(
    "-s", "-L", "-c", shQuote(cookie_jar), "-b", shQuote(cookie_jar),
    "-o", shQuote(post_page), "-d", shQuote(post_body), shQuote(login_action)
  ))

  verify_page <- tempfile(fileext = ".html")
  system2("curl", args = c(
    "-s", "-L", "-b", shQuote(cookie_jar), "-o", shQuote(verify_page), shQuote(first_url)
  ))
  verify_txt <- paste(readLines(verify_page, warn = FALSE), collapse = "\n")

  unlink(c(login_page, post_page, verify_page))

  if (!grepl("Index of", verify_txt, ignore.case = TRUE)) {
    stop("Authentication failed -- did not get a directory listing back. Check EOG_USERNAME/EOG_PASSWORD.")
  }
  cookie_jar
}

cat("\n--------------------------------------------------\n")
cat("Authenticating session with EOG Keycloak...\n")
cat("--------------------------------------------------\n")
cookie_jar <- authenticate()
cat("Session authenticated successfully.\n")

# --------------------------------------------------
# 4. Per-year: fetch listing, find average_masked file, download, gunzip
# --------------------------------------------------
cat("\n--------------------------------------------------\n")
cat("Downloading VIIRS VNL annual average_masked composites (2012-2024)...\n")
cat("--------------------------------------------------\n")

n_total <- length(years)
n_done  <- 0L

for (yr in years) {
  n_done <- n_done + 1L
  pct <- round(n_done / n_total * 100)
  ver <- year_version(yr)

  yr_dir <- file.path(out_root, as.character(yr))
  dir.create(yr_dir, showWarnings = FALSE, recursive = TRUE)

  # Skip if a decompressed .tif already exists for this year
  existing_tif <- list.files(yr_dir, pattern = "average_masked.*\\.tif$", full.names = TRUE)
  if (length(existing_tif) > 0 && file.size(existing_tif[1]) > 1e6) {
    cat(sprintf("[%3d%%] [%2d/%2d] %d (%s) -> CACHED (%s)\n",
        pct, n_done, n_total, yr, ver, basename(existing_tif[1])))
    next
  }

  # Re-authenticate before every year (not just once) -- see note above.
  cookie_jar <- authenticate()

  list_page <- tempfile(fileext = ".html")
  res <- system2("curl", args = c(
    "-s", "-L", "-b", shQuote(cookie_jar), "-o", shQuote(list_page), shQuote(listing_url(yr))
  ))
  list_txt <- paste(readLines(list_page, warn = FALSE), collapse = "\n")
  unlink(list_page)

  # Find all average_masked .tif.gz hrefs
  hrefs <- regmatches(list_txt, gregexpr('href="[^"]*average_masked[^"]*\\.tif\\.gz"', list_txt))[[1]]
  hrefs <- gsub('^href="', '', hrefs)
  hrefs <- gsub('"$', '', hrefs)

  if (length(hrefs) == 0) {
    cat(sprintf("[%3d%%] [%2d/%2d] %d (%s) -> NO FILE FOUND on listing page\n", pct, n_done, n_total, yr, ver))
    next
  }

  # 2012 special case: two composite periods exist -- prefer 201204-201212
  if (yr == 2012 && length(hrefs) > 1) {
    preferred <- hrefs[grepl("201204-201212", hrefs)]
    if (length(preferred) > 0) hrefs <- preferred
  }
  fname <- hrefs[1]
  file_url <- paste0(listing_url(yr), fname)

  gz_dest <- file.path(yr_dir, fname)
  tmp_gz  <- paste0(gz_dest, ".part")
  if (file.exists(tmp_gz)) file.remove(tmp_gz)

  res_dl <- system2("curl", args = c(
    "-s", "-L", "--fail", "-b", shQuote(cookie_jar),
    "-o", shQuote(tmp_gz), shQuote(file_url)
  ))

  if (res_dl != 0 || !file.exists(tmp_gz) || file.size(tmp_gz) < MIN_GZ_SIZE) {
    if (file.exists(tmp_gz)) file.remove(tmp_gz)
    cat(sprintf("[%3d%%] [%2d/%2d] %d (%s) -> DOWNLOAD FAILED (%s)\n", pct, n_done, n_total, yr, ver, fname))
    next
  }
  file.rename(tmp_gz, gz_dest)

  gz_mb <- round(file.size(gz_dest) / 1e6, 1)
  cat(sprintf("[%3d%%] [%2d/%2d] %d (%s) -> downloaded %s (%.1f MB), decompressing...\n",
      pct, n_done, n_total, yr, ver, fname, gz_mb))

  tif_dest <- sub("\\.gz$", "", gz_dest)
  gz_res <- system2("gunzip", args = c("-f", shQuote(gz_dest)))
  if (gz_res == 0 && file.exists(tif_dest)) {
    tif_mb <- round(file.size(tif_dest) / 1e6, 1)
    cat(sprintf("           decompressed -> %s (%.1f MB)\n", basename(tif_dest), tif_mb))
  } else {
    cat("           WARNING: gunzip failed, .gz kept as-is\n")
  }
}

unlink(cookie_jar)

# --------------------------------------------------
# 5. Summary
# --------------------------------------------------
cat("\n--------------------------------------------------\n")
cat("Download Summary\n")
cat("--------------------------------------------------\n")
all_tif <- list.files(out_root, pattern = "average_masked.*\\.tif$", recursive = TRUE, full.names = TRUE)
total_gb <- round(sum(file.size(all_tif)) / 1e9, 2)
cat(sprintf("Files on disk: %d / %d expected years\n", length(all_tif), n_total))
cat(sprintf("Total dataset size: %.2f GB\n", total_gb))
cat(sprintf("Output directory: %s\n", out_root))
cat("Finished.\n")
