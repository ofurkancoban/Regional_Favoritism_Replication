# ==============================================================================
# File:          check_raw_data.R
# Project:       Regional Favoritism: A Replication and Extension of
#                Hodler & Raschky (2014)
# Author:        Ömer Furkan Çoban
#
# University:    Carl von Ossietzky University of Oldenburg
# Department:    Applied Economics and Data Science
# Course:        Applied Econometrics Using GIS Techniques
# Semester:      SoSe 2026
# Lecturer:      Prof. Dr. Erkan Gören
#
# Category:      Setup
#
# Description:   Pre-flight check for every manually-downloaded raw input
#                this package needs (no download API: PLAD, Archigos,
#                G-Econ, GPWv3, GPWv4, GHS-POP/Earth Engine auth, WVS/EVS).
#                Run automatically at the top of setup_environment.R,
#                before any stage executes, so a user who forgot one of
#                these gets ONE clear report listing every missing file,
#                where to download it, and where it goes -- instead of
#                the pipeline running for 20 minutes and then dying on an
#                opaque fread()/read_dta() error deep inside some later
#                stage. Scoped to the requested --stage, so `make core`
#                does not demand WVS/EVS files only Stage 33 needs.
#
# Inputs:        None (checks file existence on disk)
# Outputs:       A console report; halts (non-zero exit) if anything
#                required for the requested stage is missing.
# ==============================================================================

# Each entry: path (here::here()-relative), human name, URL, registration
# note, optional extra instructions, and which run_stage phase(s) need it.
# "preprocess" gates Stages 01-21, "core" Stages 22-32, "supplementary"
# Stages 33-39. A file needed by more than one phase lists all of them.
raw_data_manifest <- list(
  list(
    path = "01_datasets/raw/plad/PLAD_April_2024.tab",
    name = "PLAD (Political Leaders' Affiliation Database), April 2024 release",
    url = "n/a -- ships with this package (see README.md)",
    registration = "Shipped",
    note = "Small (~600KB), redistributed for academic use per PLAD's own terms. If missing, check the clone/checkout rather than downloading fresh.",
    phases = c("preprocess", "core", "supplementary")
  ),
  list(
    path = "01_datasets/raw/archigos/Archigos_4.1.dta",
    name = "Archigos 4.1 (leader-spell dataset)",
    url = "n/a -- ships with this package (see README.md)",
    registration = "Shipped",
    note = "Small (~2.8MB), fully open with no registration requirement of its own. If missing, check the clone/checkout rather than downloading fresh.",
    phases = c("core", "supplementary")
  ),
  list(
    path = "01_datasets/raw/gecon/",
    name = "G-Econ 4.0 (Nordhaus et al., gridded regional GDP)",
    url = "https://gecon.yale.edu",
    registration = "Free",
    note = "This project's own substitute for HR 2014's unreleased Gennaioli et al. (2014) source, Table II Column 8.",
    phases = c("preprocess")
  ),
  list(
    path = "01_datasets/raw/GPWv3_pcount/",
    name = "GPWv3 population count, 1990 and 1995",
    url = "https://sedac.ciesin.columbia.edu/data/collection/gpw-v3",
    registration = "Free, NASA Earthdata login",
    note = "Per-country \"Population Count\" zip archives for 1990 and 1995.",
    phases = c("preprocess")
  ),
  list(
    path = "01_datasets/raw/gpw/population/pop/",
    name = "GPWv4 population count, 2000/2005/2010",
    url = "https://sedac.ciesin.columbia.edu/data/collection/gpw-v4",
    registration = "Free, NASA Earthdata login",
    note = "\"Population Count\" raster tiles for 2000, 2005, and 2010.",
    phases = c("preprocess")
  ),
  list(
    path = "01_datasets/raw/wvs/WVS_Time_Series_1981-2022_csv_v5_0.csv.gz",
    name = "WVS Trend File (1981-2022, gzip-compressed)",
    url = "n/a -- ships with this package via Git LFS",
    registration = "Shipped",
    note = "Used by Stage 33 to build FamilyTies_c (HR 2014 Table V/VI/VII). If missing, run `git lfs pull` rather than downloading it.",
    phases = c("supplementary")
  ),
  list(
    path = "01_datasets/raw/wvs/ZA7503_v3-0-0.dta.gz",
    name = "EVS Trend File (ZA7503, gzip-compressed)",
    url = "n/a -- ships with this package via Git LFS",
    registration = "Shipped",
    note = "Used alongside the WVS Trend File by Stage 33. If missing, run `git lfs pull` rather than downloading it.",
    phases = c("supplementary")
  )
)

#' Run the pre-flight check for a given run_stage value ("all",
#' "preprocess", "core", "supplementary", "render"). Reports every missing
#' file relevant to that stage in one pass; stops (halts the pipeline) if
#' anything required is missing, after printing the full list -- a user
#' fixes everything once rather than being stopped repeatedly.
check_raw_data <- function(run_stage = "all") {
  if (run_stage == "analysis") run_stage <- "core" # legacy alias, see Makefile
  active_phases <- if (run_stage == "all") {
    c("preprocess", "core", "supplementary")
  } else if (run_stage == "render") {
    character(0) # rendering reads only files earlier stages already produced
  } else {
    run_stage
  }
  if (length(active_phases) == 0) {
    return(invisible(TRUE))
  }

  relevant <- Filter(function(e) any(e$phases %in% active_phases), raw_data_manifest)
  missing <- Filter(function(e) !file.exists(here::here(e$path)), relevant)

  if (length(missing) == 0) {
    message(sprintf("✓ Raw-data pre-flight check passed (%d manual file(s) verified for --stage=%s).",
                     length(relevant), run_stage))
    return(invisible(TRUE))
  }

  cat("\n", strrep("=", 78), "\n", sep = "")
  cat(sprintf("MISSING RAW DATA: %d file(s) required for --stage=%s not found\n", length(missing), run_stage))
  cat(strrep("=", 78), "\n\n")
  for (e in missing) {
    cat(sprintf("• %s\n", e$name))
    cat(sprintf("    Expected at:   %s\n", here::here(e$path)))
    cat(sprintf("    Download from: %s\n", e$url))
    cat(sprintf("    Registration:  %s\n", e$registration))
    if (!is.null(e$note)) cat(sprintf("    Note:          %s\n", e$note))
    cat("\n")
  }
  cat("See README.md, 'Raw data that cannot be downloaded automatically',\n")
  cat("for the complete table (including GADM/DMSP/VIIRS/GHS-POP, which this\n")
  cat("pipeline downloads automatically and so are not listed above).\n")
  cat(strrep("=", 78), "\n\n")

  stop(sprintf("%d required raw data file(s) missing -- see the report above.", length(missing)), call. = FALSE)
}

# Large project-derived outputs that ship gzip-compressed (see
# .gitattributes and README.md, "What's physically shipped vs.
# symlinked") but that every consuming script still expects in plain
# form under its original filename -- decompressing them individually
# inside each of the ~18 scripts that read one of these would mean
# editing every one of those scripts and keeping them in sync; doing it
# once here instead, before any stage runs, means none of those scripts
# need to know the file was ever compressed.
shipped_gz_manifest <- list(
  list(path = "01_datasets/processed/analysis_panel.csv", phases = c("core", "supplementary")),
  list(path = "01_datasets/processed/gadm_holepunched_adm1.gpkg", phases = c("core")),
  list(path = "01_datasets/processed/population_adm2.csv", phases = c("core")),
  list(path = "01_datasets/processed/population_adm2_ghspop_interpolated.csv", phases = c("core")),
  list(path = "01_datasets/processed/ntl/harmonized_dmsp_viirs_adm2_panel.csv", phases = c("core", "supplementary")),
  list(path = "01_datasets/raw/qog/qog_std_ts_jan26.csv", phases = c("supplementary")),
  list(path = "01_datasets/processed/grid_cells_50km.gpkg", phases = c("core")),
  list(path = "01_datasets/processed/grid_cells_100km.gpkg", phases = c("core")),
  list(path = "01_datasets/processed/grid_cells_200km.gpkg", phases = c("core")),
  list(path = "01_datasets/processed/grid_cells_400km.gpkg", phases = c("core"))
)

#' Decompress every shipped `.gz` source relevant to `run_stage` into its
#' plain, expected filename (idempotent: skips any file already present,
#' e.g. because `make preprocess` regenerated it fresh from raw data,
#' which takes precedence over the shipped copy). Requires
#' `ensure_decompressed()` from utils.R to already be loaded.
ensure_shipped_inputs <- function(run_stage = "all") {
  if (run_stage == "analysis") run_stage <- "core"
  active_phases <- if (run_stage == "all") c("preprocess", "core", "supplementary") else run_stage
  relevant <- Filter(function(e) any(e$phases %in% active_phases), shipped_gz_manifest)
  if (length(relevant) == 0) {
    return(invisible(TRUE))
  }
  for (e in relevant) {
    ensure_decompressed(here::here(e$path))
  }
  invisible(TRUE)
}
