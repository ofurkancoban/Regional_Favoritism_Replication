# ==============================================================================
# File:          setup_environment.R
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
# Description:   Master orchestrator for the 41-stage research pipeline, in
#                three phases after preprocessing: Stages 22-32 (core
#                analysis, the tables and figures in the main paper),
#                Stages 33-39 (supplementary analysis, the additional
#                tables in supplementary.qmd -- Table III, V, VI, VII),
#                and Stages 40-41 (rendering both documents and the
#                presentation). Establishes the central directory
#                structure, loads necessary R packages, and sequentially
#                executes every stage. Supports granular execution via
#                command-line arguments (--stage=preprocess|core|
#                supplementary|render).
#
# Inputs:        Command-line arguments (e.g., --stage=preprocess)
# Outputs:       Initialized project environment and sequential execution of
#                the data pipeline stages.
# ==============================================================================

if (!requireNamespace("here", quietly = TRUE)) install.packages("here")

# --- Pre-flight Check: System Dependencies ---
check_system_dependency <- function(cmd, install_hint) {
  found <- system(paste0("which ", cmd), ignore.stdout = TRUE) == 0
  if (!found && .Platform$OS.type == "windows") {
    found <- system(paste0("where ", cmd), ignore.stdout = TRUE) == 0
  }
  if (!found) {
    stop(sprintf("\n[ERROR] System dependency '%s' not found.\n%s", cmd, install_hint))
  }
  message(sprintf("✓ System dependency '%s' detected.", cmd))
}

message("Checking system requirements...")
check_system_dependency("quarto", "Please install Quarto CLI: https://quarto.org/get-started/")

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

if (!tinytex::is_tinytex()) {
  message("--> Installing TinyTeX...")
  tinytex::install_tinytex()
}

# GADM/DMSP/VIIRS (Stages 01-04) are large, multi-hour, one-time downloads
# but need no registration -- they run here like any other stage. PLAD,
# Archigos, G-Econ, and GPWv4 are the ones that DO need a manual,
# registration-gated download with no API; see README.md, "Raw data",
# and place them before running this script.

# --- Define Script Paths (01-21 Preprocessing) ---
pp_dir <- function(f) here::here("02_scripts", "02_data_preprocessing", f)
s01 <- pp_dir("01_download_gadm.R")
s02 <- pp_dir("02_download_gadm_adm2.R")
s03 <- pp_dir("03_download_dmsp_raw.R")
s04 <- pp_dir("04_download_viirs_raw.R")
s06 <- pp_dir("06_wikidata_missing_leaders.R")
s07 <- pp_dir("07_build_grid_cells.R")
s08 <- pp_dir("08_build_holepunched_adm1.R")
s09 <- pp_dir("09_build_birthplace_circles.R")
s10 <- pp_dir("10_dmsp_adm2_extraction.R")
s11 <- pp_dir("11_dmsp_adm1_full_extraction.R")
s12 <- pp_dir("12_dmsp_adm1_holepunched_extraction.R")
s13 <- pp_dir("13_dmsp_grid_cells_extraction.R")
s14 <- pp_dir("14_viirs_adm2_extraction.R")
s15 <- pp_dir("15_dmsp_birthplace_circles_extraction.R")
s16 <- pp_dir("16_harmonized_dmsp_viirs_adm2.R")
s17 <- pp_dir("17_gecon_regional_gdp.R")
s18 <- pp_dir("18_gpw_population.R")
s19 <- pp_dir("19_ghs_pop_gee.R")
s20 <- pp_dir("20_ghspop_interpolate.R")
s21 <- pp_dir("21_build_analysis_panel.R")
s21b <- pp_dir("21b_hr_unpopulated_regions.R")

# --- Define Script Paths (22-32 Core Analysis: main paper tables & figures) ---
core_dir <- function(f) here::here("02_scripts", "03a_analysis_core", f)
s22 <- core_dir("22_table1_hr2014_reference.R")
s23 <- core_dir("23_table1_descriptive_stats.R")
s24 <- core_dir("24_table1_leader_lag1991fix.R")
s25 <- core_dir("25_table2_own.R")
s26 <- core_dir("26_table4_col1_circles.R")
s27 <- core_dir("27_table4_col23_holepunch.R")
s28 <- core_dir("28_table4_col4_7_grid.R")
s29 <- core_dir("29_table4_assemble.R")
s30 <- core_dir("30_extension_table2.R")
s31 <- core_dir("31_figure1_goh.R")
s32 <- core_dir("32_figure2_erdogan_units.R")

# --- Define Script Paths (33-39 Supplementary Analysis: supplementary.qmd
# tables -- Table I full/country-year detail already covered by Stage 23
# above; these seven stages cover Table III, V, VI, and VII, which the
# main paper's tables do not need) ---
supp_dir <- function(f) here::here("02_scripts", "03b_analysis_supplementary", f)
s33 <- supp_dir("33_wvs_family_ties.R")
s34 <- supp_dir("34_table5_covariates.R")
s35 <- supp_dir("35_aid_oil_covariates.R")
s36 <- supp_dir("36_table3_dynamics.R")
s37 <- supp_dir("37_table5_determinants.R")
s38 <- supp_dir("38_table6_continents.R")
s39 <- supp_dir("39_table7_aid_oil.R")

# --- Define Script Paths (40-41 Rendering) ---
s40 <- here::here("04_paper", "40_Render_Paper.R")
s41 <- here::here("05_presentation", "41_Render_Presentation.R")

# --- Command Line Argument Support (for Makefile) ---
args <- commandArgs(trailingOnly = TRUE)
run_stage <- "all"
if (length(args) > 0) {
  for (arg in args) {
    if (startsWith(arg, "--stage=")) {
      run_stage <- sub("--stage=", "", arg)
    }
  }
}

#' Run one pipeline stage in its own subprocess via callr::rscript.
#'
#' setup_environment.R previously ran every stage with source() in this
#' same R session. Across 30+ stages that accumulates unreclaimed memory
#' (the harmonized DMSP/VIIRS panel alone is ~1.5 million rows, and none
#' of the large objects earlier stages create are ever removed), and a
#' full `make all` run was observed to crash silently partway through
#' Stage 32 -- no R-level error, just the process gone, consistent with
#' an OS-level out-of-memory kill. Each stage now runs as its own
#' subprocess with its own fresh memory budget, freed in full when that
#' subprocess exits; callr::rscript still streams the stage's own output
#' live (show = TRUE) and still raises an R error here if the stage
#' itself errors, so a broken stage still stops the pipeline exactly as
#' source() did.
run_stage_script <- function(path) {
  callr::rscript(path, show = TRUE)
  invisible(NULL)
}

message(glue::glue("\n===== STARTING PROJECT PIPELINE (Stage: {run_stage}) =====\n"))

# --- Pre-flight Check: Manually-Downloaded Raw Data ---
# Catches a missing PLAD/Archigos/G-Econ/GPWv3/GPWv4/WVS/EVS file (none of
# these have a download API, see README.md) BEFORE any stage runs, with
# one clear report of everything missing, download links included --
# instead of the pipeline running for however long and then dying on an
# opaque fread()/read_dta() error deep inside some later stage.
source(here::here("02_scripts", "01_setup", "check_raw_data.R"))
check_raw_data(run_stage)

# --- Decompress Shipped Large Files ---
# analysis_panel.csv, gadm_holepunched_adm1.gpkg, the population files,
# the harmonized panel, QoG, and the four grid_cells_*km.gpkg all ship
# gzip-compressed via Git LFS (see README.md, "What's physically shipped
# vs. symlinked"); every consuming script still expects the plain
# filename, so this decompresses each once (idempotent -- skipped if
# `make preprocess` already regenerated the plain file fresh).
source(here::here("02_scripts", "04_tools", "utils.R"))
ensure_shipped_inputs(run_stage)

# --- STAGE 01-21: Preprocessing ---
if (run_stage %in% c("all", "preprocess")) {
  message("--- [01-21] DATA PREPROCESSING ---")
  scripts_pre <- list(
    "GADM 4.1 Boundary Downloader (Turkey ADM1 + global levels)" = s01,
    "GADM 4.1 ADM2 Boundary Downloader (per-country, PLAD universe)" = s02,
    "DMSP-OLS Raw Raster Downloader" = s03,
    "VIIRS Raw Raster Downloader" = s04,
    "Wikidata Missing-Leader Gap Detector" = s06,
    "Equal-Area Grid Cell Geometry" = s07,
    "Hole-Punched ADM1 Geometry" = s08,
    "5km Birthplace Circle Geometry" = s09,
    "DMSP ADM2 Nighttime-Lights Extraction" = s10,
    "DMSP ADM1 Full-Area Extraction" = s11,
    "DMSP ADM1 Hole-Punched Extraction" = s12,
    "DMSP Grid-Cell Extraction (4 resolutions)" = s13,
    "VIIRS ADM2 Extraction" = s14,
    "DMSP Birthplace-Circle Extraction" = s15,
    "Harmonized DMSP/VIIRS Panel (1992-2023)" = s16,
    "G-Econ 4.0 Regional GDP" = s17,
    "GPWv4 Population" = s18,
    "GHS-POP Extraction (Google Earth Engine)" = s19,
    "GHS-POP Annual Interpolation" = s20,
    "Analysis Panel Assembly" = s21,
    "HR 2014 Unpopulated-Region Exclusion List" = s21b
  )

  for (i in seq_along(scripts_pre)) {
    message(glue::glue("→ [{i}/41] Running {names(scripts_pre)[i]}..."))
    run_stage_script(scripts_pre[[i]])
    message("  ✓ Done.\n")
  }
}

# --- STAGE 22-32: Core Analysis (main paper tables & figures) ---
if (run_stage %in% c("all", "core", "analysis")) {
  message("--- [22-32] CORE ANALYSIS: MAIN PAPER TABLES & FIGURES ---")
  scripts_ana <- list(
    "22" = "Table 1: HR 2014 Reference Numbers", "23" = "Table 1: Descriptive Statistics",
    "24" = "Table 1: Leader Lag 1991 Fix", "25" = "Table 2: Full Replication",
    "26" = "Table 4 Col(1): Birthplace Circles", "27" = "Table 4 Col(2)-(3): SN1 Full/Hole-Punched",
    "28" = "Table 4 Col(4)-(7): Grid Cells", "29" = "Table 4: Assemble All Columns",
    "30" = "Extension: Table 2 over 1992-2023", "31" = "Figure 1: G-Econ vs. Own Regional GDP",
    "32" = "Figure 2: Table IV Units of Observation"
  )
  scripts_paths <- list(
    "22" = s22, "23" = s23, "24" = s24, "25" = s25, "26" = s26, "27" = s27,
    "28" = s28, "29" = s29, "30" = s30, "31" = s31, "32" = s32
  )

  for (stage in names(scripts_ana)) {
    message(glue::glue("→ [{stage}/41] Running {scripts_ana[[stage]]}..."))
    run_stage_script(scripts_paths[[stage]])
    message(glue::glue("  ✓ Stage {stage} Completed.\n"))
  }
}

# --- STAGE 33-39: Supplementary Analysis (supplementary.qmd tables) ---
if (run_stage %in% c("all", "supplementary")) {
  message("--- [33-39] SUPPLEMENTARY ANALYSIS: TABLE III, V, VI, VII ---")
  scripts_supp <- list(
    "33" = "FamilyTies (WVS/EVS Family Ties Index)", "34" = "Table V Covariates (Polity/Schooling/GDP/Language)",
    "35" = "Table VII Covariates (Aid/Oil)", "36" = "Table III: Dynamics",
    "37" = "Table V: Determinants", "38" = "Table VI: Continents",
    "39" = "Table VII: Aid, Oil, and Regional Favoritism"
  )
  scripts_supp_paths <- list(
    "33" = s33, "34" = s34, "35" = s35, "36" = s36, "37" = s37, "38" = s38, "39" = s39
  )

  for (stage in names(scripts_supp)) {
    message(glue::glue("→ [{stage}/41] Running {scripts_supp[[stage]]}..."))
    run_stage_script(scripts_supp_paths[[stage]])
    message(glue::glue("  ✓ Stage {stage} Completed.\n"))
  }
}

# --- STAGE 40-41: Rendering ---
if (run_stage %in% c("all", "render")) {
  message("--- [40-41] DOCUMENT RENDERING ---")
  scripts_render <- list("40" = "Rendering Research Paper + Supplementary (PDF)", "41" = "Rendering Presentation (Reveal.js)")
  scripts_render_paths <- list("40" = s40, "41" = s41)

  for (stage in names(scripts_render)) {
    message(glue::glue("→ [{stage}/41] {scripts_render[[stage]]}..."))
    run_stage_script(scripts_render_paths[[stage]])
    message(glue::glue("  ✓ Final Stage {stage} Completed.\n"))
  }
}

message("\n==========================================")
message("   FULL PIPELINE COMPLETED SUCCESSFULLY")
message("==========================================\n")
