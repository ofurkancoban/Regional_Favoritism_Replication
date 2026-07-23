# ==============================================================================
# File:          00_import.R
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
# Category:      Data Preprocessing
#
# Description:   A utility script containing foundational functions, common
#                directory definitions, and global library imports required
#                consistently across every preprocessing and analysis stage.
#                Handles package installation and project directory
#                initialization.
#
# Inputs:        None
# Outputs:       Loaded libraries, initialized directory structure, and
#                utility functions in the global environment.
# ==============================================================================

if (!requireNamespace("here", quietly = TRUE)) install.packages("here")

packages <- c(
  "data.table", # Fast tabular data (fread/fwrite, all region-year panels)
  "dplyr", # Data manipulation used by the figure scripts
  "readr", # CSV import in a few reference scripts
  "readxl", # Excel import (raw covariate sources)
  "haven", # Stata .dta import (Archigos leader-spell data)
  "jsonlite", # JSON parsing (GADM geoboundary downloads)
  "countrycode", # COW code -> ISO3 country code conversion
  "glue", # String interpolation in setup_environment.R's stage log messages
  "R.utils", # gunzip() for compressed raster downloads
  "httr", # Authenticated HTTP downloads (EOG DMSP/VIIRS rasters)
  "sf", # Vector geometry (GADM boundaries, grid cells, circles)
  "terra", # Raster I/O (DMSP/VIIRS composites)
  "exactextractr", # Zonal statistics (raster -> polygon NTL extraction)
  "ggspatial", # Map annotations (scale bars) in Figure 2
  "tidyterra", # ggplot2 geoms for terra rasters, Figure 1
  "fixest", # Fixed-effects estimation, every regression table
  "ggplot2", # Figure 1/2 base plotting
  "patchwork", # Multi-panel figure composition
  "png", # PNG raster handling in Figure 1
  "magick", # Image post-processing for the figures
  "ragg", # High-quality PNG/SVG graphics device
  "systemfonts", # Custom font registration (Latin Modern Roman) for figures
  "svglite", # SVG export of Figure 1/2 before HTML->PDF rasterization
  "reticulate", # Python bridge for Google Earth Engine (GHS-POP only)
  "callr", # Runs each pipeline stage in its own subprocess (setup_environment.R)
  "quarto", # Renders paper.qmd / presentation.qmd
  "tinytex", # LaTeX distribution for the PDF outputs
  "gt", # Styled HTML table export (03_results/tables/html/)
  "pwt", # Penn World Table 7.1 (HR's exact NationalGDP source, Stage 34)
  "knitr", # kable() table rendering in supplementary.qmd
  "kableExtra" # Table styling (spanners, shading) in paper.qmd / supplementary.qmd
)

if (is.null(getOption("repos")) || getOption("repos")["CRAN"] == "@CRAN@") {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}

install_and_load <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message("Installing missing package: ", pkg)
    utils::install.packages(pkg)
  }
  suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}

invisible(lapply(packages, install_and_load))

# --- Robustness Helpers ---

#' Ensure a directory exists, creating it if necessary
#' @param path Character. Path to the directory.
ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    message("Creating missing directory: ", path)
    dir.create(path, recursive = TRUE)
  }
  return(path)
}

#' Check if a file already exists and should be skipped
#' @param target_file Character. Path to the file.
#' @param force Logical. If TRUE, never skip.
#' @return Logical. TRUE if skip is advised, FALSE otherwise.
should_skip <- function(target_file, force = FALSE) {
  if (force) return(FALSE)
  if (file.exists(target_file)) {
    return(TRUE)
  }
  return(FALSE)
}

# --- Project Structure Initialization ---
# 01_datasets/raw and 01_datasets/processed are symlinks to ../data/raw and
# ../data/processed in the main GIS_RegionalFavoritism repository: this
# package is too large in raw data (tens of GB of DMSP/VIIRS rasters) to
# duplicate, so the canonical copy stays in the main repo and this package
# reads it through the symlink via here::here("01_datasets", ...) like any
# of its own files.
standard_dirs <- c(
  "01_datasets/final",
  "03_results/figures",
  "03_results/tables"
)

invisible(lapply(standard_dirs, function(d) ensure_dir(here::here(d))))

message("✓ All packages loaded and project directories initialized.")
