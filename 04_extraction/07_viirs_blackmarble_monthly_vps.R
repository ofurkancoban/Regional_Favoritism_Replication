# 04_extraction/07_viirs_blackmarble_monthly_vps.R
# VPS variant of 07_viirs_blackmarble_monthly.R: same NASA Black Marble
# VNP46A3 monthly extraction, but pointed at a local VPS h5 tile cache
# (instead of the external drive used on the Mac) and with per-month h5
# cleanup, since the VPS only has ~40GB free disk vs. 476GB on the
# external drive. Intended to run for days in the background on the VPS,
# where LAADS DAAC's server-side rate limiting (~2-3 files/min even with
# parallel curl, confirmed earlier this session) is tolerable because
# nothing else is competing for the runtime. Reverted to Black Marble
# (from the faster AWS "Light Every Night" alternative) on 2026-08-18
# per explicit user decision: BRDF/near-nadir correction is worth the
# slower background download when wall-clock time isn't a constraint.
#
# Output: data/processed/ntl/viirs_blackmarble_adm2_panel.csv

library(sf)
library(data.table)
library(blackmarbler)

blackmarble_h5_dir <- "/root/viirs_pipeline/data/raw/blackmarble_raw"
dir.create(blackmarble_h5_dir, showWarnings = FALSE, recursive = TRUE)

get_blackmarble_token <- function() {
  # ~/.netrc here is the standard multi-line format (one `machine`/`login`/
  # `password` directive per line), not a single combined line -- a
  # single-regex parse silently matched the `machine` line and produced
  # empty user/pass strings, causing an opaque "Incorrect username or
  # password" error. Confirmed 2026-08-18.
  netrc <- readLines("~/.netrc")
  user <- trimws(sub(".*login +", "", grep("login", netrc, value = TRUE)[1]))
  pass <- trimws(sub(".*password +", "", grep("password", netrc, value = TRUE)[1]))
  blackmarbler::get_nasa_token(username = user, password = pass)
}

blackmarble_months <- function(end_date = Sys.Date()) {
  seq(as.Date("2012-01-01"), as.Date(format(end_date, "%Y-%m-01")), by = "month")
}

cat("=== Load GADM 3.6 (ADM2, ADM1 fallback) for PLAD countries ===\n")
plad  <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
iso3s <- sort(unique(plad$gid_0))
iso3s <- iso3s[iso3s != "."]

sf::sf_use_s2(FALSE)
adm2 <- sf::st_read("data/raw/gadm_3.6/gadm36_levels.gpkg", layer = "level2", quiet = TRUE)
sf::st_geometry(adm2) <- "geometry"
adm2 <- adm2[adm2$GID_0 %in% iso3s, c("GID_0", "GID_2", "geometry")]
data.table::setnames(adm2, c("GID_0", "GID_2"), c("iso3", "region_id"))
adm2$adm_level <- "ADM2"

adm1 <- sf::st_read("data/raw/gadm_3.6/gadm36_level1_only.gpkg", quiet = TRUE)
sf::st_geometry(adm1) <- "geometry"
adm1 <- adm1[adm1$GID_0 %in% iso3s, c("GID_0", "GID_1", "geometry")]
data.table::setnames(adm1, c("GID_0", "GID_1"), c("iso3", "region_id"))
adm1$adm_level <- "ADM1"

has_adm2 <- unique(adm2$iso3)
adm1_fallback <- adm1[!adm1$iso3 %in% has_adm2, ]

regions <- rbind(adm2[, c("region_id", "iso3", "adm_level")],
                  adm1_fallback[, c("region_id", "iso3", "adm_level")])
regions <- sf::st_transform(regions, 4326)
cat(sprintf("Regions: %d | ADM2: %d | ADM1-fallback: %d | countries: %d\n",
    nrow(regions), sum(regions$adm_level == "ADM2"), sum(regions$adm_level == "ADM1"),
    data.table::uniqueN(regions$iso3)))

cat("\n=== Get NASA bearer token ===\n")
token <- get_blackmarble_token()
cat("Token OK.\n")

months <- blackmarble_months()
cat(sprintf("Months to process: %d (%s to %s)\n",
    length(months), format(months[1], "%Y-%m"), format(months[length(months)], "%Y-%m")))

out_dir <- "data/processed/ntl/viirs_blackmarble_by_month"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

for (m in months) {
  ym <- format(as.Date(m, origin = "1970-01-01"), "%Y-%m")
  out_file <- file.path(out_dir, paste0(ym, ".csv"))
  if (file.exists(out_file)) {
    cat(sprintf("[%s] cached, skipping\n", ym)); next
  }

  t0 <- Sys.time()
  # Extracting all 174 countries' regions in one bm_extract() call loads
  # every intersecting tile's raster data into memory simultaneously --
  # this OOM-killed the R process twice on this memory-constrained, shared
  # VPS (11GB RAM, confirmed via `dmesg`: anon-rss up to ~6GB before being
  # killed). Looping per country instead keeps each call's memory
  # footprint small; blackmarbler's own download_h5_files() already skips
  # re-downloading any tile file that exists on disk (file.exists() check
  # per tile), so tiles shared across countries within the same month are
  # fetched once and reused, not re-downloaded. Confirmed 2026-08-18.
  country_list <- sort(unique(regions$iso3))
  country_dt_list <- vector("list", length(country_list))
  any_failed <- FALSE
  for (i in seq_along(country_list)) {
    cty <- country_list[i]
    reg_c <- regions[regions$iso3 == cty, ]
    ext_c <- tryCatch(
      blackmarbler::bm_extract(
        roi_sf           = reg_c,
        product_id       = "VNP46A3",
        date             = paste0(ym, "-01"),
        bearer           = token,
        aggregation_fun  = "mean",
        add_n_pixels     = TRUE,
        quality_flag_rm  = 2,
        h5_dir           = blackmarble_h5_dir,
        download_method  = "httr",
        quiet            = TRUE
      ),
      error = function(e) {
        cat(sprintf("[%s] %s FAILED: %s\n", ym, cty, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(ext_c)) { any_failed <- TRUE; next }
    dt_c <- data.table::as.data.table(sf::st_drop_geometry(ext_c))
    # ext_c retains our own input columns (region_id, iso3, adm_level) --
    # earlier drafts assumed a GID_0 column would be added by bm_extract()
    # itself (as it is when roi_sf's country column is literally named
    # GID_0), but with our pre-renamed "iso3" column that never happens;
    # referencing it threw "object 'GID_0' not found". Confirmed 2026-08-18.
    country_dt_list[[i]] <- dt_c[, .(region_id, iso3, adm_level,
                 year = as.integer(format(as.Date(m, origin = "1970-01-01"), "%Y")),
                 month = as.integer(format(as.Date(m, origin = "1970-01-01"), "%m")),
                 viirs_ntl = ntl_mean, n_pixels, n_non_na_pixels)]
    if (i %% 10 == 0) gc(full = FALSE)
  }
  dt <- data.table::rbindlist(country_dt_list, fill = TRUE)
  if (nrow(dt) == 0) {
    cat(sprintf("[%s] FAILED: no countries extracted\n", ym))
    unlink(list.files(blackmarble_h5_dir, full.names = TRUE))
    next
  }

  tmp_file <- paste0(out_file, ".tmp")
  data.table::fwrite(dt, tmp_file)
  file.rename(tmp_file, out_file)

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  cat(sprintf("[%s] rows=%d countries=%d/%d (%.1fs)%s\n", ym, nrow(dt),
      data.table::uniqueN(dt$iso3), length(country_list), elapsed,
      if (any_failed) " -- some countries failed, see log" else ""))

  # Delete this month's raw h5 tiles once its panel CSV is safely written --
  # the VPS has only ~40GB free disk, nowhere near enough to keep all 176
  # months' tile caches. Confirmed 2026-08-18.
  rm(country_dt_list, dt); unlink(list.files(blackmarble_h5_dir, full.names = TRUE)); gc(full = TRUE)
}

csv_files <- file.path(out_dir, paste0(format(months, "%Y-%m"), ".csv"))
if (all(file.exists(csv_files))) {
  cat("\nAll months present -- assembling panel...\n")
  panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
  data.table::fwrite(panel, "data/processed/ntl/viirs_blackmarble_adm2_panel.csv")
  cat(sprintf("Panel saved: %d rows, %d regions, %d months\n",
      nrow(panel), data.table::uniqueN(panel$region_id), length(csv_files)))
} else {
  missing <- length(csv_files) - sum(file.exists(csv_files))
  cat(sprintf("\nNot all months done yet (%d missing) -- panel assembly skipped.\n", missing))
}
