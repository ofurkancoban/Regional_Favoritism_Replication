# R/03b_plad_turkey.R
# Purpose: Task 3.2 -- extract Turkey subset from PLAD, build Leader_it panel skeleton.
# PLAD version: April 2024 (doi:10.7910/DVN/YUS575)

library(data.table)

plad_path <- "data/raw/plad/PLAD_April_2024.tab"
if (!file.exists(plad_path)) stop("PLAD not found at ", plad_path)

plad <- data.table::fread(plad_path, sep = "\t")

# ---- Turkey subset ----
tur <- plad[gid_0 == "TUR"]
tur[, startdate := as.Date(startdate)]
tur[, enddate   := as.Date(enddate)]

# Extend Erdogan entry to 2024-12-31 (PLAD ends at 2023-12-31)
tur[leader == "Erdogan", enddate := as.Date("2024-12-31")]

# ---- Build annual Leader_it panel ----
# For each year in 1992-2024, identify which ADM1 (gid_1) is the leader province.
# A leader qualifies for year t if they held office for >= 91 days in year t
# (following Bora 2025: 25% of the period threshold).

years      <- 1992:2024
provinces  <- sort(unique(tur$gid_1))

leader_rows <- data.table::rbindlist(lapply(years, function(yr) {
  yr_start <- as.Date(paste0(yr, "-01-01"))
  yr_end   <- as.Date(paste0(yr, "-12-31"))

  overlap <- tur[startdate <= yr_end & enddate >= yr_start]
  if (nrow(overlap) == 0) return(data.table(year = yr, gid_1 = NA_character_, leader = NA_character_))

  overlap[, days_in_yr := as.integer(
    pmin(enddate, yr_end) - pmax(startdate, yr_start) + 1L
  )]
  # Apply 25% threshold (91 days for non-leap years)
  qualified <- overlap[days_in_yr >= 91]
  if (nrow(qualified) == 0) return(data.table(year = yr, gid_1 = NA_character_, leader = NA_character_))

  # If multiple leaders qualify in one year, take the one with most days
  qualified[order(-days_in_yr)][1, .(year = yr, gid_1, leader, adm1, days_in_yr)]
}))

data.table::setDT(leader_rows)

message("Annual leader panel (1992-2024):")
print(leader_rows[, .(year, leader, adm1 = if ("adm1" %in% names(leader_rows)) adm1 else gid_1, gid_1)])

# ---- Save ----
dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
data.table::fwrite(leader_rows, "data/processed/turkey_leaders_annual.csv")
message("Saved: data/processed/turkey_leaders_annual.csv")

# ---- Summary ----
cat("\nDistinct leader provinces in 1992-2024:\n")
print(unique(leader_rows[!is.na(gid_1), .(gid_1, adm1 = if ("adm1" %in% names(leader_rows)) adm1 else gid_1)]))

cat("\nYears Istanbul is leader province:", sum(leader_rows$gid_1 == "TUR.40_1", na.rm = TRUE), "\n")
cat("Years with no qualified leader:", sum(is.na(leader_rows$gid_1)), "\n")
