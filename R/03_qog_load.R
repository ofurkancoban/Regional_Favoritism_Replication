# R/03_qog_load.R
# Purpose: Task 5.2 - load QoG Standard Dataset Jan26 and identify relevant columns.
# Download from: https://www.gu.se/en/quality-government/qog-data/data-downloads
# Place the .dta file at: data/raw/qog/qog_std_ts_jan26.dta

library(haven)
library(data.table)

qog_path <- "data/raw/qog/qog_std_ts_jan26.dta"

if (!file.exists(qog_path)) {
  stop(
    "QoG Standard Dataset not found.\n",
    "Download from https://www.gu.se/en/quality-government/qog-data/data-downloads\n",
    "Place the .dta file at data/raw/qog/qog_std_ts_jan26.dta"
  )
}

qog_raw <- haven::read_dta(qog_path)
qog     <- data.table::as.data.table(qog_raw)

# Columns required for this project (from DATA_SOURCES.md Section 5)
needed_cols <- c(
  "ccode",          # country code (COW or ISO, verify)
  "cname",          # country name
  "year",
  "p_polity2",      # Polity5 polity2 index (-10 to +10)
  "vdem_libdem",    # V-Dem Liberal Democracy Index
  "wbgi_gee",       # WGI Government Effectiveness Estimate
  "bl_asyt15",      # Barro-Lee average years of schooling, 15+
  "al_ethnic",      # Alesina ethnic fractionalization
  "wdi_gdpcapcon2015"  # GDP per capita PPP constant 2015 USD
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
