# R/00_session_info.R
# Purpose: verify that all required packages are installed and log session info.
# Run this once at the start of the project and after any environment change.

required_packages <- c(
  "fixest",
  "modelsummary",
  "tidyverse",
  "data.table",
  "sf",
  "terra",
  "spdep",
  "spatialreg",
  "wbstats",
  "reticulate",
  "arrow",
  "haven",
  "ggplot2"
)

# vdemdata is not on CRAN; install with:
#   remotes::install_github("vdeminstitute/vdemdata")
# We use the raw V-Dem CSV instead if the package is unavailable.
optional_packages <- c("vdemdata")

missing_packages <- required_packages[
  !sapply(required_packages, requireNamespace, quietly = TRUE)
]

if (length(missing_packages) > 0) {
  message("Installing missing packages: ", paste(missing_packages, collapse = ", "))
  install.packages(missing_packages)
} else {
  message("All required packages are available.")
}

for (pkg in required_packages) {
  library(pkg, character.only = TRUE)
  message("Loaded: ", pkg)
}

print(utils::sessionInfo())
