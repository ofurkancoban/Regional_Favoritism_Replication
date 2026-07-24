# ==============================================================================
# File:          24_table1_leader_lag1991fix.R
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
# Description:   Recomputes the boundary-lag-corrected Leader_ict-1 descriptive-statistics row: 1992's one-year lag filled from PLAD/Wikidata pre-1992 leader-tenure records rather than left missing.
#
# Inputs:        01_datasets/processed/analysis_panel.csv, reference_data/
# Outputs:       01_datasets/processed/table1_leader_lag1991fix_hrsample.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

years_hr <- 1992:2009

cat("=== Load analysis panel, restrict to HR's exact sample ===\n")
d <- data.table::fread(here::here("01_datasets/processed/analysis_panel.csv"))
hr126 <- data.table::fread(here::here("01_datasets/raw/plad/hr2014_126_countries.csv"))
hr_65n <- data.table::fread(here::here("01_datasets/processed/hr_excluded_above65n_regions.csv"))
# Third exclusion criterion (p. 1001): "the few regions that are
# unpopulated." Proxy: regions never matched to a GPWv4 population figure
# in any observed year -- see Stage 21b for the important caveat that
# this is not a verified match to the authors' own concept, just the
# closest available signal.
hr_unpop <- data.table::fread(here::here("01_datasets/processed/hr_excluded_unpopulated_regions.csv"))
d <- d[iso3 %in% hr126$iso3]
d <- d[!gid_2 %in% hr_65n$gid_2]
d <- d[!gid_2 %in% hr_unpop$gid_2]
d <- d[year %in% years_hr]
cat(sprintf("Panel: %d obs | %d regions | %d countries\n",
    nrow(d), data.table::uniqueN(d$gid_2), data.table::uniqueN(d$iso3)))

cat("\n=== Build 1991 birth-region flag (same method as table2_own_hrsample.R) ===\n")
plad_raw <- data.table::fread(here::here("01_datasets/raw/plad/PLAD_April_2024.tab"), sep = "\t")
plad_raw <- plad_raw[!is.na(gid_2) & gid_2 != "." & !is.na(startyear) & !is.na(endyear) & gid_0 != "."]
plad_raw <- plad_raw[is.na(foreign_leader) | foreign_leader != 1]
plad_1991 <- plad_raw[startyear <= 1991 & endyear >= 1991,
                       .(gid_2 = gid_2, iso3 = gid_0)]
wd_supp <- data.table::fread(here::here("01_datasets/processed/wikidata_supplement_birthplaces.csv"))
wd_1991 <- wd_supp[startyear <= 1991 & endyear >= 1991,
                    .(gid_2 = birth_gid2, iso3)]
birth_1991 <- unique(rbind(plad_1991, wd_1991))
cat(sprintf("1991 birth regions: %d (across %d countries)\n",
    nrow(birth_1991), data.table::uniqueN(birth_1991$iso3)))

cat("\n=== Build Leader_ict-1 (positional shift by gid_2, 1992 filled) ===\n")
data.table::setorder(d, gid_2, year)
d[, leader_t1 := data.table::shift(is_birthregion, 1L), by = gid_2]
d[year == 1992, leader_t1 := gid_2 %in% birth_1991$gid_2]
d[, leader_t1 := as.integer(leader_t1)]

n_before_fix <- sum(!is.na(d[, data.table::shift(is_birthregion, 1L), by = gid_2]$V1))
cat(sprintf("Leader_t-1 non-NA before fix (1992 left NA): %d | after fix: %d\n",
    n_before_fix, sum(!is.na(d$leader_t1))))

cat("\n=== Compute panel descriptive stats (xtsum-style, region-year level) ===\n")
xtsum <- function(x, unit) {
  ok <- !is.na(x) & !is.na(unit)
  x <- x[ok]; unit <- unit[ok]
  grand_mean <- mean(x)
  dt <- data.table::data.table(x = x, unit = unit)
  unit_means <- dt[, .(m = mean(x)), by = unit]
  dt <- merge(dt, unit_means, by = "unit")
  c(obs = length(x), mean = grand_mean, sd_overall = stats::sd(x),
    sd_between = stats::sd(unit_means$m), sd_within = stats::sd(x - dt$m + grand_mean),
    min = min(x), max = max(x))
}

leader_stats <- xtsum(d$leader_t1, d$gid_2)
out <- data.table::as.data.table(as.list(leader_stats))
out[, variable := "Leaderict-1"]
print(out, digits = 3)

data.table::fwrite(out, here::here("01_datasets/processed/ntl/table1_leader_lag1991fix_hrsample.csv"))
cat("\nSaved: data/processed/ntl/table1_leader_lag1991fix_hrsample.csv\n")

cat("\n=== Export browsable HTML view (combining Stages 22-24) ===\n")
# Runs last of the three Table 1 scripts (22, 23, 24), so all three of
# their outputs already exist: HR 2014's reference numbers, this
# project's own descriptive stats, and the boundary-lag-corrected
# Leader_ict-1 row computed just above -- overriding the uncorrected row
# from Stage 23, the same substitution @tbl-descriptives makes in paper.qmd.
hr_ref <- data.table::fread(here::here("01_datasets/processed/ntl/hr2014_table1_reference.csv"))
own_desc <- data.table::fread(here::here("01_datasets/processed/ntl/table1_descriptive_region_hrsample.csv"))
own_desc <- own_desc[match(c("Lightict", "Leaderict-1"), variable)]
own_desc[variable == "Leaderict-1", names(out) := out]

# Full, paper.qmd-style layout: one row per variable, with HR 2014's
# Orig. block and this package's Repl. block side by side under grouped
# spanners (Obs./Mean/SD/Min/Max each), matching @tbl-descriptives.
stat_cols <- function(dt, var_label, prefix) {
  r <- dt[variable == var_label]
  vals <- list(
    formatC(r$obs, format = "d", big.mark = ","),
    sprintf("%.3f", r$mean),
    sprintf("%.3f", r$sd_overall),
    sprintf("%.3f", r$min),
    sprintf("%.3f", r$max)
  )
  names(vals) <- paste0(prefix, c("obs", "mean", "sd", "min", "max"))
  vals
}
row_for <- function(var_label, display_label) {
  as.data.frame(c(
    list(Variable = display_label),
    stat_cols(hr_ref, var_label, "hr_"),
    stat_cols(own_desc, var_label, "own_")
  ), stringsAsFactors = FALSE)
}
t1_wide <- rbind(
  row_for("Lightict", "Light<sub>ict</sub>"),
  row_for("Leaderict-1", "Leader<sub>ict-1</sub>")
)

stat_labels <- c("Obs.", "Mean", "SD", "Min", "Max")
hr_cols <- paste0("hr_", c("obs", "mean", "sd", "min", "max"))
own_cols <- paste0("own_", c("obs", "mean", "sd", "min", "max"))

gt_tbl <- gt::gt(t1_wide) |>
  gt::fmt_markdown(columns = "Variable") |>
  gt::tab_header(
    title = gt::md("**Descriptive Statistics**"),
    subtitle = "Region-year panel, 126 countries, 1992-2009. Leader_ict-1 includes the boundary-lag fix (Stage 24)."
  ) |>
  gt::tab_spanner(label = "HR 2014 (Orig.)", columns = hr_cols) |>
  gt::tab_spanner(label = "This Package (Repl.)", columns = own_cols) |>
  gt::cols_label(.list = stats::setNames(as.list(rep(stat_labels, 2)), c(hr_cols, own_cols))) |>
  gt::tab_style(
    style = gt::cell_fill(color = "#f2f2f2"),
    locations = gt::cells_body(columns = own_cols)
  ) |>
  gt::tab_style(
    style = gt::cell_fill(color = "#f2f2f2"),
    locations = gt::cells_column_spanners(spanners = "This Package (Repl.)")
  ) |>
  gt::tab_source_note(source_note = "Light_ict is ln(Light intensity + 0.01); Leader_ict-1 is the lagged birth-region dummy.") |>
  gt::tab_options(
    table.font.size = gt::px(12),
    heading.title.font.size = gt::px(17),
    column_labels.font.weight = "bold",
    table.border.top.width = gt::px(2),
    table.border.top.color = "black",
    table.border.bottom.width = gt::px(2),
    table.border.bottom.color = "black"
  )

out_dir <- here::here("03_results", "tables", "html")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
out_path <- file.path(out_dir, "table1_descriptive_hrsample.html")
gt::gtsave(gt_tbl, out_path)
message(sprintf("HTML table saved: %s", out_path))
