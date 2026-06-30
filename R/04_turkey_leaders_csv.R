# R/04_turkey_leaders_csv.R
# Purpose: Week 2 -- build validated TURKEY_LEADERS.csv.
#   - Map PLAD GID_1 codes to geoBoundaries shapeName
#   - Produce annual Leader_it panel with matched province identifiers
#   - Write data/processed/TURKEY_LEADERS.csv (one row per leader spell)

library(data.table)
library(sf)

# ---- Load inputs ----
plad <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
gb   <- sf::st_read("data/raw/gadm_4.1/turkey/geoboundaries_TUR_ADM1.geojson", quiet = TRUE)
gb_dt <- data.table::as.data.table(sf::st_drop_geometry(gb))

tur_plad <- plad[gid_0 == "TUR"]
tur_plad[, startdate := as.Date(startdate)]
tur_plad[, enddate   := as.Date(enddate)]
tur_plad[leader == "Erdogan", enddate := as.Date("2024-12-31")]

# ---- Manual GID_1 -> geoBoundaries shapeName crosswalk ----
# PLAD uses GADM 3.6 GID codes; geoBoundaries uses ISO 3166-2 codes (TR-xx).
# Crosswalk built by matching adm1 province names manually.
crosswalk <- data.table::data.table(
  gid_1      = c("TUR.7_1",  "TUR.30_1",  "TUR.39_1", "TUR.40_1",   "TUR.47_1", "TUR.70_1"),
  adm1_plad  = c("Ankara",   "Erzincan",  "Isparta",  "Istanbul",    "Kayseri",  "Sinop"),
  gb_name    = c("Ankara",   "Erzincan",  "Isparta",  "İstanbul", "Kayseri",  "Sinop"),
  iso3166_2  = c("TR-06",    "TR-24",     "TR-32",    "TR-34",       "TR-38",    "TR-57")
)

# Verify each crosswalk entry exists in geoBoundaries
crosswalk[, gb_found := gb_name %in% gb_dt$shapeName]
stopifnot("All crosswalk entries must match geoBoundaries" = all(crosswalk$gb_found))
message("Crosswalk validated: all ", nrow(crosswalk), " provinces matched.")

# ---- Merge crosswalk into PLAD Turkey ----
tur_plad <- merge(tur_plad, crosswalk[, .(gid_1, gb_name, iso3166_2)],
                  by = "gid_1", all.x = TRUE)

# ---- Build leader spell table (one row per leader) ----
leaders_csv <- tur_plad[, .(
  leader       = leader,
  startdate    = startdate,
  enddate      = enddate,
  startyear    = as.integer(format(startdate, "%Y")),
  endyear      = as.integer(format(enddate,   "%Y")),
  birth_adm1_plad   = adm1,
  birth_adm2_plad   = adm2,
  birth_geoname     = geoname,
  plad_gid1         = gid_1,
  plad_gid2         = gid_2,
  gb_province_name  = gb_name,
  iso3166_2         = iso3166_2,
  # Robustness: Erdogan alternative coding (Rize)
  gb_province_robustness = data.table::fifelse(
    leader == "Erdogan", "Rize", gb_name
  )
)][order(startdate)]

# ---- Biographical validation notes (three-source check) ----
# Sources consulted per leader:
# (1) PLAD April 2024 database entry
# (2) TBMM (Grand National Assembly) official biography: https://www.tbmm.gov.tr
# (3) English Wikipedia / Britannica
validation_notes <- data.table::data.table(
  leader = c("Akbulut", "Yilmaz", "Demirel", "Erdal Inonu",
             "Ciller", "Erbakan", "Ecevit", "Abdullah Gul", "Erdogan"),
  birth_place_verified = c(
    "Erzincan -- confirmed (PLAD, TBMM, Wikipedia)",
    "Istanbul -- confirmed (PLAD, TBMM, Wikipedia)",
    "Isparta (Islamkoy village, Atabey district) -- confirmed (PLAD, TBMM, Wikipedia)",
    "Ankara -- confirmed (PLAD, TBMM, Wikipedia; son of Ismet Inonu)",
    "Istanbul -- confirmed (PLAD, TBMM, Wikipedia)",
    "Sinop -- confirmed (PLAD, TBMM, Wikipedia)",
    "Istanbul -- confirmed (PLAD, TBMM, Wikipedia)",
    "Kayseri -- confirmed (PLAD, TBMM, Wikipedia)",
    "Istanbul (Kasimpasa, Beyoglu) -- confirmed (PLAD, TBMM, Wikipedia). Family roots in Rize (Guneysu). Primary = Istanbul per birth certificate and PLAD."
  ),
  three_source_validated = TRUE
)

leaders_csv <- merge(leaders_csv, validation_notes, by = "leader", all.x = TRUE)

# ---- Save ----
dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
data.table::fwrite(leaders_csv, "data/processed/TURKEY_LEADERS.csv")
message("Saved: data/processed/TURKEY_LEADERS.csv (", nrow(leaders_csv), " leader spells)")

# ---- Build annual Leader_it panel with geoBoundaries province names ----
years <- 1992:2024
annual_panel <- data.table::rbindlist(lapply(years, function(yr) {
  yr_start <- as.Date(paste0(yr, "-01-01"))
  yr_end   <- as.Date(paste0(yr, "-12-31"))
  overlap  <- tur_plad[startdate <= yr_end & enddate >= yr_start]
  if (nrow(overlap) == 0) {
    return(data.table(year = yr, leader = NA_character_,
                      gb_province = NA_character_, iso3166_2 = NA_character_))
  }
  overlap[, days_in_yr := as.integer(pmin(enddate, yr_end) - pmax(startdate, yr_start) + 1L)]
  qualified <- overlap[days_in_yr >= 91]
  if (nrow(qualified) == 0) {
    return(data.table(year = yr, leader = NA_character_,
                      gb_province = NA_character_, iso3166_2 = NA_character_))
  }
  qualified[order(-days_in_yr)][1, .(
    year        = yr,
    leader      = leader,
    gb_province = gb_name,
    iso3166_2   = iso3166_2
  )]
}))

data.table::fwrite(annual_panel, "data/processed/turkey_leader_annual_panel.csv")
message("Saved: data/processed/turkey_leader_annual_panel.csv")

cat("\nAnnual Leader_it panel summary:\n")
print(annual_panel)
cat("\nDistinct leader provinces:\n")
print(unique(annual_panel[!is.na(gb_province), .(gb_province, iso3166_2)]))
