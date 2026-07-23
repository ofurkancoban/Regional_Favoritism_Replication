# ==============================================================================
# File:          verify_outputs.R
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
# Category:      Verification
#
# Description:   Checks the headline coefficients in every table this
#                package produces against the values reported in the paper
#                (paper.pdf, rendered 2026-09-04), to answer "did this run
#                actually reproduce the paper" in one command instead of by
#                eye. Run after `make analysis` (Stages 22-32). Exits with a
#                non-zero status if any check fails, so it composes with CI.
#
# Inputs:        01_datasets/processed/ntl/table1_leader_lag1991fix_hrsample.csv,
#                table2_full_coefs_hrsample.csv, table4_full_hrsample.csv,
#                extension_table2_summary.csv
# Outputs:       A pass/fail report printed to the console.
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))

cat("\n===== VERIFYING REPLICATION OUTPUTS AGAINST paper.pdf =====\n\n")

failures <- 0L
checks <- 0L

check_close <- function(label, actual, expected, tol = 1e-3) {
  checks <<- checks + 1L
  if (is.na(actual)) {
    cat(sprintf("  [MISSING] %-55s -- file/row not found\n", label))
    failures <<- failures + 1L
    return(invisible(FALSE))
  }
  ok <- abs(actual - expected) < tol
  status <- if (ok) "OK  " else "FAIL"
  cat(sprintf("  [%s] %-55s expected %8.4f, got %8.4f\n", status, label, expected, actual))
  if (!ok) failures <<- failures + 1L
  invisible(ok)
}

#' Look up one cell by plain vector filtering -- deliberately not
#' data.table's NSE (dt[col == x]): a filter column literally named "col"
#' (as Table 4's and the extension's own CSVs are) collides with any local
#' variable of the same name once the expression is eval()'d inside dt[...],
#' since that scope resolves bare `col` to the table's own column, not the
#' caller's variable -- every row then matches, nrow() != 1, and every
#' lookup silently returns NA. Base-R indexing has no such scoping trap.
get_val <- function(dt, match_cols, out_col) {
  mask <- rep(TRUE, nrow(dt))
  for (nm in names(match_cols)) mask <- mask & (dt[[nm]] == match_cols[[nm]])
  sub <- dt[mask, ]
  if (nrow(sub) != 1) return(NA_real_)
  sub[[out_col]]
}

# --- Table 1: boundary-lag-corrected Leader_ict-1 --------------------------
cat("--- Table 1 (descriptive statistics) ---\n")
t1_path <- here::here("01_datasets/processed/ntl/table1_leader_lag1991fix_hrsample.csv")
if (file.exists(t1_path)) {
  t1 <- data.table::fread(t1_path)
  check_close("Leader_ict-1 obs. count (boundary-lag fix)", t1$obs[1], 654254, tol = 0.5)
} else {
  cat("  [MISSING] table1_leader_lag1991fix_hrsample.csv -- run Stage 24\n")
  failures <- failures + 1L
  checks <- checks + 1L
}

# --- Table 2: HR 2014 Table II replication, all eight columns --------------
cat("\n--- Table 2 (HR 2014 Table II replication) ---\n")
t2_path <- here::here("01_datasets/processed/ntl/table2_full_coefs_hrsample.csv")
if (file.exists(t2_path)) {
  t2 <- data.table::fread(t2_path)
  t2_own <- t2[source == "own"]
  expected_t2 <- list(
    "Col(1) Leader_t-1" = c(row = "Leader_t-1", col = 1, b = 0.032),
    "Col(2) Leader_t"   = c(row = "Leader_t",   col = 2, b = 0.029),
    "Col(3) Leader_t-2" = c(row = "Leader_t-2", col = 3, b = 0.040),
    "Col(4) Leader_t-1" = c(row = "Leader_t-1", col = 4, b = 0.026),
    "Col(5) Leader_t-1" = c(row = "Leader_t-1", col = 5, b = 0.050),
    "Col(6) Leader_t-1" = c(row = "Leader_t-1", col = 6, b = 0.008),
    "Col(7) Leader_t-1" = c(row = "Leader_t-1", col = 7, b = 0.025),
    "Col(8) Leader_t-1" = c(row = "Leader_t-1", col = 8, b = 0.013)
  )
  for (label in names(expected_t2)) {
    spec <- expected_t2[[label]]
    v <- get_val(t2_own, list(row = spec[["row"]], col = as.integer(spec[["col"]])), "b")
    check_close(label, v, as.numeric(spec[["b"]]))
  }
} else {
  cat("  [MISSING] table2_full_coefs_hrsample.csv -- run Stage 25\n")
  failures <- failures + 1L
  checks <- checks + 1L
}

# --- Table 4: HR 2014 Table IV replication, all seven columns --------------
cat("\n--- Table 4 (HR 2014 Table IV replication) ---\n")
t4_path <- here::here("01_datasets/processed/ntl/table4_full_hrsample.csv")
if (file.exists(t4_path)) {
  t4 <- data.table::fread(t4_path)
  t4_own <- t4[source == "own"]
  expected_t4 <- c(`1` = 0.0245, `2` = 0.0175, `3` = 0.0102, `4` = 0.0359,
                    `5` = 0.0192, `6` = -0.0005, `7` = -0.0044)
  for (col in names(expected_t4)) {
    v <- get_val(t4_own, list(col = as.integer(col)), "b")
    check_close(sprintf("Col(%s) own estimate", col), v, expected_t4[[col]], tol = 5e-3)
  }
} else {
  cat("  [MISSING] table4_full_hrsample.csv -- run Stages 26-29\n")
  failures <- failures + 1L
  checks <- checks + 1L
}

# --- Extension: Table 2 over the 1992-2023 harmonized panel ----------------
cat("\n--- Extension (1992-2023 harmonized panel) ---\n")
ext_path <- here::here("01_datasets/processed/ntl/extension_table2_summary.csv")
if (file.exists(ext_path)) {
  ext <- data.table::fread(ext_path)
  expected_ext <- c(`1` = 0.048, `2` = 0.043, `3` = 0.046, `4` = 0.025,
                     `5` = 0.074, `6` = 0.035, `7` = 0.026)
  for (col in names(expected_ext)) {
    v <- get_val(ext, list(col = as.integer(col)), "b")
    check_close(sprintf("Col(%s) coefficient", col), v, expected_ext[[col]], tol = 5e-3)
  }
} else {
  cat("  [MISSING] extension_table2_summary.csv -- run Stage 30\n")
  failures <- failures + 1L
  checks <- checks + 1L
}

cat(sprintf("\n===== %d/%d checks passed =====\n\n", checks - failures, checks))
if (failures > 0L) {
  quit(status = 1L)
}
