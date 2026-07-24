# ==============================================================================
# File:          29_table4_assemble.R
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
# Description:   Combines Table IV's seven own-estimate columns with the authors' own published reference numbers into the single table paper.qmd reads.
#
# Inputs:        01_datasets/processed/table4_col1_own_hrsample.csv, table4_col23_own_hrsample.csv, table4_col4_7_own_hrsample.csv
# Outputs:       01_datasets/processed/table4_full_hrsample.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

out_dir <- here::here("01_datasets/processed/ntl")

cat("=== HR 2014 Table IV reference rows (p. 1018) ===\n")
hr_rows <- data.table::data.table(
  col       = 1:7,
  b         = c(0.049, 0.026, 0.023, 0.043, 0.028, 0.020, 0.005),
  se        = c(0.024, 0.010, 0.012, 0.010, 0.011, 0.009, 0.009),
  sig       = c("**", "**", "**", "***", "**", "**", ""),
  n_regions = c(520, 2242, 2220, 64204, 17242, 6101, 2110),
  n_obs     = c(9134, 40157, 39761, 1048370, 280210, 101655, 35889),
  within_r2 = c(0.520, 0.602, 0.603, 0.210, 0.298, 0.362, 0.449),
  source    = "hr"
)

cat("=== Load own-estimate rows from the three component scripts ===\n")
own_col1  <- data.table::fread(file.path(out_dir, "table4_col1_own_hrsample.csv"))
own_col23 <- data.table::fread(file.path(out_dir, "table4_col23_own_hrsample.csv"))
own_col47 <- data.table::fread(file.path(out_dir, "table4_col4_7_own_hrsample.csv"))
own_rows <- data.table::rbindlist(list(own_col1, own_col23, own_col47))
data.table::setorder(own_rows, col)

if (!identical(own_rows$col, 1:7)) {
  stop("Expected own-estimate rows for columns 1-7; got: ",
       paste(own_rows$col, collapse = ", "),
       ". Re-run the three table4_*_hrsample.R component scripts first.")
}

cat("=== Combine and write table4_full_hrsample.csv ===\n")
table4_full <- data.table::rbindlist(list(hr_rows, own_rows), use.names = TRUE)
data.table::setorder(table4_full, source, col)
data.table::fwrite(table4_full, file.path(out_dir, "table4_full_hrsample.csv"))
cat(sprintf("Saved: %s\n", file.path(out_dir, "table4_full_hrsample.csv")))
print(table4_full)

cat("\n=== Export browsable HTML view (full table, matching paper.qmd's layout) ===\n")
unit_labels <- c(`1` = "5km circle", `2` = "SN1 region", `3` = "SN1 excl. birth SN2",
                  `4` = "50km grid", `5` = "100km grid", `6` = "200km grid", `7` = "400km grid")

t4_coefs <- table4_full[, .(row = "Leader_t-1", col, b, se, sig, source)]

hr_sum <- table4_full[source == "hr", .(col, n_regions, n_obs, within_r2)]
own_sum <- table4_full[source == "own", .(col, n_regions, n_obs, within_r2)]

build_full_table_gt(
  coefs = t4_coefs,
  row_order = "Leader_t-1",
  row_labels = c("Leader_t-1" = "Leader<sub>ict-1</sub>"),
  n_cols = 7,
  dv_spans = c("Light<sub>ict</sub>" = 7),
  shaded_cols = c(2, 4, 6),
  footer_rows = list(
    "Units of observation" = unname(unit_labels[as.character(1:7)]),
    "Number of regions" = data.table::data.table(
      col = 1:7,
      hr = formatC(hr_sum$n_regions, format = "d", big.mark = ","),
      own = formatC(own_sum$n_regions, format = "d", big.mark = ",")
    ),
    "Observations" = data.table::data.table(
      col = 1:7,
      hr = formatC(hr_sum$n_obs, format = "d", big.mark = ","),
      own = formatC(own_sum$n_obs, format = "d", big.mark = ",")
    ),
    "Within R2" = data.table::data.table(
      col = 1:7,
      hr = sprintf("%.3f", hr_sum$within_r2),
      own = sprintf("%.3f", own_sum$within_r2)
    )
  ),
  region_fe = rep("Yes", 7),
  title = "Table IV Replication",
  subtitle = "HR 2014's Table IV, all seven columns, on the authors' exact 126-country, 1992-2009 sample. Dependent variable: Light_ict throughout.",
  notes = "Standard errors, in parentheses, are clustered by leader spell, lagged one period. *** p<0.01, ** p<0.05, * p<0.10.",
  file_name = "table4_full_hrsample.html"
)
