# R/03_qog_load.R
# Purpose: Task 5.2 - load QoG Standard Dataset Jan26 and identify relevant columns.
# Download from: https://www.gu.se/en/quality-government/qog-data/data-downloads
# Place the .dta file at: data/raw/qog/qog_std_ts_jan26.dta

library(haven)
library(data.table)

qog_path <- "data/raw/qog/qog_std_ts_jan26.csv"

if (!file.exists(qog_path)) {
  stop(
    "QoG Standard Dataset (time-series) not found.\n",
    "Download from https://www.qogdata.pol.gu.se/data/qog_std_ts_jan26.csv\n",
    "Place at data/raw/qog/qog_std_ts_jan26.csv"
  )
}

qog <- data.table::fread(qog_path)

# Columns required for this project (from DATA_SOURCES.md Section 5)
needed_cols <- c(
  "ccode",             # COW country code
  "cname",             # country name
  "ccodealp",          # ISO3 alpha code
  "year",
  "p_polity2",         # Polity5 polity2 index (-10 to +10); ends 2018
  "vdem_libdem",       # V-Dem Liberal Democracy Index
  "wbgi_gee",          # WGI Government Effectiveness Estimate; starts 1996, biennial early years
  "al_ethnic2000",     # Alesina ethnic fractionalization (QoG column name: al_ethnic2000)
  "wdi_gdpcapcon2015"  # GDP per capita PPP constant 2015 USD
  # bl_asyt15 (Barro-Lee schooling) is NOT in QoG ts Jan26.
  # Use data/raw/qog/BL2013_MF1599_v2.2.csv directly (yr_sch column, 5-year intervals 1950-2010).
  # Linear interpolation to annual and extrapolation to 2023 done in panel construction script.
)

present <- needed_cols[needed_cols %in% names(qog)]
missing_cols <- needed_cols[!needed_cols %in% names(qog)]

message("Present columns: ",  paste(present, collapse = ", "))
if (length(missing_cols) > 0) {
  message("Missing columns (check variant names): ", paste(missing_cols, collapse = ", "))
  # Search for close matches
  for (col in missing_cols) {
    candidates <- grep(sub("^[a-z]+_", "", col), names(qog), value = TRUE, ignore.case = TRUE)
    if (length(candidates) > 0) {
      message("  Candidates for '", col, "': ", paste(candidates[seq_len(min(5, length(candidates)))], collapse = ", "))
    }
  }
}

# Save minimal panel
qog_sub <- qog[, intersect(present, names(qog)), with = FALSE]
data.table::fwrite(qog_sub, "data/processed/qog_subset.csv")
message("QoG subset saved to data/processed/qog_subset.csv (", nrow(qog_sub), " rows, ",
        ncol(qog_sub), " columns)")

# Turkey time series preview
if ("cname" %in% names(qog_sub)) {
  tur <- qog_sub[grepl("Turkey|Turk", cname, ignore.case = TRUE)]
  message("Turkey rows in QoG: ", nrow(tur), " (years ", min(tur$year), " to ", max(tur$year), ")")
}
