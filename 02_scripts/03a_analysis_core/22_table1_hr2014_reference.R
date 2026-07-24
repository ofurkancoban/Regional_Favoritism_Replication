# ==============================================================================
# File:          22_table1_hr2014_reference.R
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
# Category:      Econometric Analysis
#
# Description:   Writes the authors' own published Table I numbers (HR 2014, p. 1007) as a CSV, the 'Orig.' columns of the descriptive statistics table.
#
# Inputs:        None (hardcoded, cited)
# Outputs:       01_datasets/processed/hr2014_table1_reference.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

hr_table1 <- data.table::data.table(
  variable   = c("Lightict", "Leaderict-1"),
  obs        = c(690495, 690495),
  mean       = c(0.050, 0.004),
  sd_overall = c(2.482, 0.060),
  sd_between = c(2.425, 0.045),
  sd_within  = c(0.538, 0.040),
  min        = c(-4.605, 0.000),
  max        = c(4.143, 1.000)
)

data.table::fwrite(hr_table1, here::here("01_datasets/processed/ntl/hr2014_table1_reference.csv"))
cat("Saved: data/processed/ntl/hr2014_table1_reference.csv\n")
print(hr_table1)
