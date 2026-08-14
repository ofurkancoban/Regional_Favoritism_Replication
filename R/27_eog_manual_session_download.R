# R/27_eog_manual_session_download.R
# Purpose: Reproducible, automated download of the raw DMSP-OLS
# stable_lights.avg_vis GeoTIFFs (1992-2013) directly from EOG
# (eogdata.mines.edu), using the same authenticated-session mechanism a
# logged-in browser uses for free-tier manual downloads (NOT the paid
# OAuth Bearer-token API -- that endpoint is a separate, subscription-gated
# path we deliberately do not use).
#
# Mechanism: log in through EOG's Keycloak login form with the user's own
# free EOG account credentials (same form a human fills in a browser),
# capture the resulting session cookie, then reuse that cookie for all
# subsequent file downloads. This automates a manual, free, licensed
# (CC BY 4.0) download process for reproducibility -- it does not touch
# the paid programmatic API.
#
# Requires EOG_USERNAME and EOG_PASSWORD in .env (never committed --
# .env is already in .gitignore).
#
# Output: data/raw/dmsp_raster_eog_manual/<year>/<SAT><YEAR>.v4b.global.stable_lights.avg_vis.tif
# Resume-safe: already-downloaded files are skipped.

library(data.table)

source("R/utils/gee_helpers.R")  # reuses .load_env()
.load_env()

eog_user <- Sys.getenv("EOG_USERNAME")
eog_pass <- Sys.getenv("EOG_PASSWORD")
if (eog_user == "" || eog_pass == "") {
  stop(
    "EOG credentials not set.\n",
    "Add to .env:\n",
    "  EOG_USERNAME=your-eog-email\n",
    "  EOG_PASSWORD=your-eog-password\n"
  )
}

out_root  <- "data/raw/dmsp_raster_eog_manual"
cookie_jar <- file.path(tempdir(), "eog_cookies.txt")
dir.create(out_root, showWarnings = FALSE, recursive = TRUE)
if (file.exists(cookie_jar)) file.remove(cookie_jar)

base_url <- "https://eogdata.mines.edu/wwwdata/dmsp/v4composites_rearrange"

# Year -> satellite(s) map, from EOG's own Version 4 DMSP-OLS coverage table.
year_sat <- list(
  "1992" = "F10", "1993" = "F10",
  "1994" = c("F10", "F12"),
  "1995" = "F12", "1996" = "F12",
  "1997" = c("F12", "F14"), "1998" = c("F12", "F14"), "1999" = c("F12", "F14"),
  "2000" = c("F14", "F15"), "2001" = c("F14", "F15"),
  "2002" = c("F14", "F15"), "2003" = c("F14", "F15"),
  "2004" = c("F15", "F16"), "2005" = c("F15", "F16"),
  "2006" = c("F15", "F16"), "2007" = c("F15", "F16"),
  "2008" = "F16", "2009" = "F16",
  "2010" = "F18", "2011" = "F18", "2012" = "F18", "2013" = "F18"
)

file_url <- function(sat, year) {
  sprintf("%s/%s_%s/%s%s.v4b.global.stable_lights.avg_vis.tif", base_url, sat, year, sat, year)
}

# ---- Step 1: establish an authenticated session (mirrors manual browser login) ----
cat("Logging in to EOG (eogdata.mines.edu) with your account...\n")

first_url <- file_url(year_sat[["1992"]][1], "1992")
login_page <- file.path(tempdir(), "eog_login_page.html")

system2("curl", c(
  "-s", "-L",
  "-c", cookie_jar, "-b", cookie_jar,
  "-o", login_page,
  first_url
))

html <- paste(readLines(login_page, warn = FALSE), collapse = "\n")

# Extract the Keycloak login form action URL (session-specific, HTML-escaped).
action_match <- regmatches(html, regexpr('action="[^"]*login-actions/authenticate[^"]*"', html))
if (length(action_match) == 0 || nchar(action_match) == 0) {
  stop(
    "Could not find EOG login form on the page. EOG may have changed their login flow, ",
    "or you may already need a different entry point. Saved page at: ", login_page
  )
}
login_action <- sub('^action="', '', action_match)
login_action <- sub('"$', '', login_action)
login_action <- gsub('&amp;', '&', login_action, fixed = TRUE)

cat("Submitting credentials...\n")

post_page <- file.path(tempdir(), "eog_after_login.html")
system2("curl", c(
  "-s", "-L",
  "-c", cookie_jar, "-b", cookie_jar,
  "-o", post_page,
  "--data-urlencode", paste0("username=", eog_user),
  "--data-urlencode", paste0("password=", eog_pass),
  login_action
))

# ---- Step 2: verify the session actually works by re-requesting a known file ----
verify_headers <- file.path(tempdir(), "eog_verify_headers.txt")
system2("curl", c(
  "-s", "-I", "-L",
  "-b", cookie_jar,
  "-D", verify_headers,
  "-o", "/dev/null",
  first_url
))
verify_txt <- paste(readLines(verify_headers, warn = FALSE), collapse = "\n")

if (!grepl("Content-Type:\\s*image/tiff", verify_txt, ignore.case = TRUE)) {
  stop(
    "Login did not succeed -- file request is not returning a TIFF.\n",
    "Check EOG_USERNAME/EOG_PASSWORD in .env are correct.\n",
    "Response headers:\n", verify_txt
  )
}
cat("Session authenticated successfully.\n\n")

# ---- Step 3: download all year/satellite files ----
years <- names(year_sat)
n_total <- sum(sapply(year_sat, length))
n_done  <- 0L

for (yr in years) {
  yr_dir <- file.path(out_root, yr)
  dir.create(yr_dir, showWarnings = FALSE, recursive = TRUE)

  for (sat in year_sat[[yr]]) {
    n_done <- n_done + 1L
    url  <- file_url(sat, yr)
    dest <- file.path(yr_dir, sprintf("%s%s.v4b.global.stable_lights.avg_vis.tif", sat, yr))

    if (file.exists(dest) && file.size(dest) > 1e6) {
      cat(sprintf("[%3d%%] [%2d/%2d] %s %s  cached (%.1f MB)\n",
          round(n_done / n_total * 100), n_done, n_total, yr, sat, file.size(dest) / 1e6))
      next
    }

    tmp_dest <- paste0(dest, ".tmp")
    if (file.exists(tmp_dest)) file.remove(tmp_dest)

    res <- system2("curl", c(
      "-s", "-L", "--fail",
      "-b", cookie_jar,
      "-o", tmp_dest,
      url
    ))

    if (res != 0 || !file.exists(tmp_dest) || file.size(tmp_dest) < 1e6) {
      cat(sprintf("[%3d%%] [%2d/%2d] %s %s  FAILED\n",
          round(n_done / n_total * 100), n_done, n_total, yr, sat))
      if (file.exists(tmp_dest)) file.remove(tmp_dest)
      next
    }
    file.rename(tmp_dest, dest)

    cat(sprintf("[%3d%%] [%2d/%2d] %s %s  downloaded (%.1f MB)\n",
        round(n_done / n_total * 100), n_done, n_total, yr, sat, file.size(dest) / 1e6))
  }
}

cat("\nDone.\n")
all_files <- list.files(out_root, pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
cat(sprintf("Files on disk: %d / %d expected\n", length(all_files), n_total))
cat(sprintf("Total size: %.1f GB\n", sum(file.size(all_files)) / 1e9))
cat(sprintf("Output dir: %s\n", out_root))
