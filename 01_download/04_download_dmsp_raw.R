# 01_download/04_download_dmsp_raw.R
# Purpose: Inspect eogdata.mines.edu.har for credentials and sample URLs,
# establish an authenticated session with EOG Keycloak auth, and automatically
# download all DMSP-OLS Version 4 stable_lights.avg_vis GeoTIFFs (1992-2013)
# to data/raw/dmsp_raster_eog_manual/.
#
# Resume-safe: Skips already completed files and terminates cleanly when all
# 34 files are present.

suppressPackageStartupMessages({
  library(jsonlite)
})

# Helper function to load .env variables if present
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

# Minimum expected size for a complete DMSP GeoTIFF (10 MB = 10,485,760 bytes)
MIN_FILE_SIZE <- 10 * 1024 * 1024
out_root <- "data/raw/dmsp_raster_eog_manual"
dir.create(out_root, showWarnings = FALSE, recursive = TRUE)

# --------------------------------------------------
# 1. Build Full Dataset URL Catalog (1992-2013)
# --------------------------------------------------
base_url <- "https://eogdata.mines.edu/wwwdata/dmsp/v4composites_rearrange"

# Official EOG DMSP-OLS Version 4 satellite-year mapping (1992-2013)
year_sat <- list(
  "1992" = "F10",
  "1993" = "F10",
  "1994" = c("F10", "F12"),
  "1995" = "F12",
  "1996" = "F12",
  "1997" = c("F12", "F14"),
  "1998" = c("F12", "F14"),
  "1999" = c("F12", "F14"),
  "2000" = c("F14", "F15"),
  "2001" = c("F14", "F15"),
  "2002" = c("F14", "F15"),
  "2003" = c("F14", "F15"),
  "2004" = c("F15", "F16"),
  "2005" = c("F15", "F16"),
  "2006" = c("F15", "F16"),
  "2007" = c("F15", "F16"),
  "2008" = "F16",
  "2009" = "F16",
  "2010" = "F18",
  "2011" = "F18",
  "2012" = "F18",
  "2013" = "F18"
)

build_url <- function(sat, year) {
  # 2010 F18 uses v4d suffix, 2011-2013 F18 use v4c suffix
  version_suffix <- "v4b"
  if (sat == "F18") {
    if (year == "2010") {
      version_suffix <- "v4d"
    } else {
      version_suffix <- "v4c"
    }
  }
  sprintf("%s/%s_%s/%s%s.%s.global.stable_lights.avg_vis.tif", base_url, sat, year, sat, year, version_suffix)
}

# Construct download catalog
catalog <- list()
for (yr in names(year_sat)) {
  for (sat in year_sat[[yr]]) {
    v_suffix <- "v4b"
    if (sat == "F18") {
      if (yr == "2010") v_suffix <- "v4d" else v_suffix <- "v4c"
    }
    catalog[[length(catalog) + 1]] <- list(
      year = yr,
      sat  = sat,
      file = sprintf("%s%s.%s.global.stable_lights.avg_vis.tif", sat, yr, v_suffix),
      url  = build_url(sat, yr)
    )
  }
}

n_total <- length(catalog)

# --------------------------------------------------
# 2. Pre-Check: If All Files Exist, Terminate Immediately
# --------------------------------------------------
n_existing <- 0L
for (item in catalog) {
  dest_file <- file.path(out_root, item$year, item$file)
  if (file.exists(dest_file) && file.size(dest_file) >= MIN_FILE_SIZE) {
    n_existing <- n_existing + 1L
  }
}

if (n_existing == n_total) {
  all_files <- list.files(out_root, pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
  total_gb  <- round(sum(file.size(all_files)) / (1024^3), 2)
  
  cat("--------------------------------------------------\n")
  cat("All files already downloaded!\n")
  cat("--------------------------------------------------\n")
  cat(sprintf("Files on disk: %d / %d expected\n", n_existing, n_total))
  cat(sprintf("Total dataset size: %.2f GB\n", total_gb))
  cat(sprintf("Output directory: %s\n", out_root))
  cat("Finished cleanly. Exiting.\n")
  flush.console()
  return(invisible(NULL))
}

cat(sprintf("Catalog status: %d / %d files present on disk. %d files remaining to download.\n",
            n_existing, n_total, n_total - n_existing))
flush.console()

# --------------------------------------------------
# 3. Inspect HAR file for Credentials
# --------------------------------------------------
har_path <- "eogdata.mines.edu.har"
har_username <- ""
har_password <- ""

if (file.exists(har_path)) {
  cat("--------------------------------------------------\n")
  cat("1. Inspecting HAR file:", har_path, "\n")
  cat("--------------------------------------------------\n")
  flush.console()
  
  har_data <- jsonlite::fromJSON(har_path, simplifyVector = FALSE)
  entries  <- har_data$log$entries
  
  for (entry in entries) {
    req <- entry$request
    pd  <- req$postData
    if ((har_username == "" || har_password == "") && !is.null(pd) && !is.null(pd$params)) {
      for (p in pd$params) {
        if (p$name == "username") har_username <- utils::URLdecode(p$value)
        if (p$name == "password") har_password <- utils::URLdecode(p$value)
      }
    }
  }
}

# Determine credentials (.env takes precedence, fallback to HAR postData)
eog_user <- Sys.getenv("EOG_USERNAME")
eog_pass <- Sys.getenv("EOG_PASSWORD")

if (eog_user == "") eog_user <- har_username
if (eog_pass == "") eog_pass <- har_password

if (eog_user == "" || eog_pass == "") {
  stop(
    "EOG credentials not found in environment or HAR file.\n",
    "Please set EOG_USERNAME and EOG_PASSWORD in .env"
  )
}

cat(sprintf("Using account credentials for user: %s\n", eog_user))
flush.console()

# --------------------------------------------------
# 4. Authenticate Session via Keycloak Login
# --------------------------------------------------
cat("\n--------------------------------------------------\n")
cat("2. Authenticating session with EOG Keycloak...\n")
cat("--------------------------------------------------\n")
flush.console()

cookie_jar <- tempfile(fileext = ".txt")
login_page <- tempfile(fileext = ".html")
first_missing_item <- NULL
for (item in catalog) {
  dest_file <- file.path(out_root, item$year, item$file)
  if (!file.exists(dest_file) || file.size(dest_file) < MIN_FILE_SIZE) {
    first_missing_item <- item
    break
  }
}
if (is.null(first_missing_item)) first_missing_item <- catalog[[1]]
first_target_url <- first_missing_item$url

# Initial request to obtain login page and action URL
user_agent <- "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"

# Helper: run curl via system() with proper quoting
run_curl <- function(...) {
  args <- c(...)
  cmd <- paste("curl", paste(shQuote(args), collapse = " "))
  system(cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
}

# Helper: run curl and capture output to file
run_curl_to_file <- function(out_file, ...) {
  args <- c(...)
  cmd <- paste("curl", paste(shQuote(args), collapse = " "))
  system(cmd)
}

success <- FALSE
for (attempt in 1:5) {
  run_curl(
    "-s", "-L",
    "-A", user_agent,
    "--retry", "5", "--retry-delay", "5",
    "-c", cookie_jar,
    "-b", cookie_jar,
    "-o", login_page,
    first_target_url
  )
  if (file.exists(login_page) && file.size(login_page) > 500) {
    success <- TRUE
    break
  }
  Sys.sleep(3)
}

if (!success) {
  stop("Failed to reach EOG Keycloak login page after 5 attempts.")
}

html_txt <- paste(readLines(login_page, warn = FALSE), collapse = "\n")
action_match <- regmatches(html_txt, regexpr('action="[^"]*login-actions/authenticate[^"]*"', html_txt))

if (length(action_match) == 0 || nchar(action_match[1]) == 0) {
  stop("Could not find Keycloak login action URL on page.")
}

login_action <- sub('^action="', '', action_match[1])
login_action <- sub('"$', '', login_action)
login_action <- gsub('&amp;', '&', login_action, fixed = TRUE)

# Submit credentials
post_page <- tempfile(fileext = ".html")
post_body <- sprintf(
  "username=%s&password=%s&credentialId=",
  utils::URLencode(eog_user, reserved = TRUE),
  utils::URLencode(eog_pass, reserved = TRUE)
)

run_curl(
  "-s", "-L",
  "-A", user_agent,
  "--retry", "5", "--retry-delay", "5",
  "-c", cookie_jar,
  "-b", cookie_jar,
  "-o", post_page,
  "-d", post_body,
  login_action
)

# Verify authenticated session
verify_headers <- tempfile(fileext = ".txt")
run_curl(
  "-s", "-I", "-L",
  "-b", cookie_jar,
  "-D", verify_headers,
  "-o", "/dev/null",
  first_target_url
)

verify_txt <- paste(readLines(verify_headers, warn = FALSE), collapse = "\n")

if (grepl("Content-Type: image/tiff", verify_txt, ignore.case = TRUE) ||
    grepl("200 OK", verify_txt, ignore.case = TRUE) ||
    grepl("Location:", verify_txt, ignore.case = TRUE)) {
  cat(sprintf("Session authenticated successfully for user: %s\n", eog_user))
  flush.console()
} else {
  stop("Authentication failed -- session verification did not return a valid GeoTIFF response.\nPlease check EOG_USERNAME and EOG_PASSWORD.")
}

if (file.exists(verify_headers)) file.remove(verify_headers)

# --------------------------------------------------
# 5. Download Missing GeoTIFF Files (Atomic & Resume-Safe)
# --------------------------------------------------
cat("\n--------------------------------------------------\n")
cat("3. Downloading DMSP-OLS Version 4 GeoTIFF Time Series...\n")
cat("--------------------------------------------------\n")
flush.console()

n_done <- 0L

for (i in seq_along(catalog)) {
  item <- catalog[[i]]
  n_done <- n_done + 1L
  
  yr_dir <- file.path(out_root, item$year)
  dir.create(yr_dir, showWarnings = FALSE, recursive = TRUE)
  dest_file <- file.path(yr_dir, item$file)
  tmp_file  <- paste0(dest_file, ".tmp")
  
  pct <- round(n_done / n_total * 100)
  
  # Check if target file already exists and is complete (>= MIN_FILE_SIZE)
  if (file.exists(dest_file)) {
    if (file.size(dest_file) >= MIN_FILE_SIZE) {
      fsize_mb <- round(file.size(dest_file) / (1024 * 1024), 2)
      cat(sprintf("[%3d%%] [%2d/%2d] %s %s -> CACHED (%.2f MB)\n", pct, n_done, n_total, item$year, item$sat, fsize_mb))
      flush.console()
      next
    } else {
      # Remove incomplete or corrupted file under 10 MB threshold
      file.remove(dest_file)
    }
  }
  
  # Print immediate progress before curl download starts
  cat(sprintf("[%3d%%] [%2d/%2d] %s %s -> Downloading...", pct, n_done, n_total, item$year, item$sat))
  flush.console()
  
  # Clean up any corrupt leftover .tmp file before starting fresh download
  if (file.exists(tmp_file)) file.remove(tmp_file)
  
  # Download to temporary file
  res_code <- run_curl(
    "-s", "-L", "--fail",
    "-A", user_agent,
    "--retry", "5", "--retry-delay", "5",
    "-b", cookie_jar,
    "-o", tmp_file,
    item$url
  )
  
  # Verify temporary file size and move to final target path upon success
  if (res_code == 0 && file.exists(tmp_file) && file.size(tmp_file) >= MIN_FILE_SIZE) {
    file.rename(tmp_file, dest_file)
    fsize_mb <- round(file.size(dest_file) / (1024 * 1024), 2)
    cat(sprintf(" DOWNLOADED (%.2f MB)\n", fsize_mb))
  } else {
    if (file.exists(tmp_file)) file.remove(tmp_file)
    cat(" FAILED\n")
  }
  flush.console()
}

if (file.exists(cookie_jar)) file.remove(cookie_jar)
if (file.exists(login_page)) file.remove(login_page)
if (file.exists(post_page)) file.remove(post_page)

# --------------------------------------------------
# 6. Summary & Clean Termination
# --------------------------------------------------
cat("\n--------------------------------------------------\n")
cat("Download Summary\n")
cat("--------------------------------------------------\n")
flush.console()

all_files <- list.files(out_root, pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
total_bytes <- sum(file.size(all_files))
total_gb <- round(total_bytes / (1024^3), 2)

cat(sprintf("Files on disk: %d / %d expected\n", length(all_files), n_total))
cat(sprintf("Total dataset size: %.2f GB\n", total_gb))
cat(sprintf("Output directory: %s\n", out_root))
cat("Finished cleanly.\n")
flush.console()

