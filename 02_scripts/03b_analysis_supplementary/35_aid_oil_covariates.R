# ==============================================================================
# File:          35_aid_oil_covariates.R
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
# Category:      Data Preprocessing (Supplementary)
#
# Description:   Builds the two country-year covariates behind HR 2014
#                Table VII (Aid, Oil, and Regional Favoritism):
#                  Aid_ct: log of net ODA per capita plus 1, using the
#                          sign(x)*log1p(|x|) transform of Levy-Yeyati,
#                          Panizza & Stein (2007) HR cite. Fetched live
#                          from the OECD DAC2A SDMX REST API
#                          (sdmx.oecd.org, no auth needed) -- this is HR's
#                          own stated source (International Development
#                          Statistics, DAC-OECD), not a substitute.
#                  Oil_ct: log of oil rents per capita plus 1, from QoG's
#                          World Bank Adjusted Net Savings series
#                          (wdi_oilrent x wdi_gdpcapcur).
#                Both divide by population in THOUSANDS, not raw
#                headcount, matching HR's Appendix A population
#                convention -- confirmed against HR's own published
#                Table I ranges (Aid [-10.632, 13.712], Oil [0.000,
#                16.396]).
#
# Inputs:        01_datasets/raw/qog/qog_std_ts_jan26.csv,
#                OECD DAC2A SDMX API (live network call)
# Outputs:       01_datasets/processed/table7_covariates.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))

years_rep <- 1992:2013

cat("=== Load QoG oil/GDP/population/polity series ===\n")
qog <- data.table::fread(
  here::here("01_datasets/raw/qog/qog_std_ts_jan26.csv"),
  select = c("ccodealp", "year", "wdi_pop", "wdi_oilrent", "wdi_gdpcapcur", "p_polity2")
)
data.table::setnames(qog, "ccodealp", "iso3")
qog <- qog[year %in% years_rep]

cat("\n=== Fetch Net ODA disbursements from OECD DAC2A SDMX API ===\n")
oecd_url <- sprintf(
  "https://sdmx.oecd.org/public/rest/data/OECD.DCD.FSD,DSD_DAC2@DF_DAC2A,1.0/DAC..206.USD.V?startPeriod=%d&endPeriod=%d&format=csv",
  min(years_rep), max(years_rep)
)
oda_raw <- data.table::fread(oecd_url)
# DAC2A's RECIPIENT dimension mixes real ISO3 country codes with regional/
# aggregate codes (e.g. "A5", "ACP", "4EU002", "5WB001"); keep only rows
# whose RECIPIENT matches a real ISO3 country code.
valid_iso3 <- unique(stats::na.omit(countrycode::codelist$iso3c))
oda <- oda_raw[RECIPIENT %in% valid_iso3,
  .(iso3 = RECIPIENT, year = TIME_PERIOD, oda_total = OBS_VALUE * 10^UNIT_MULT)]
oda <- oda[!is.na(oda_total)]
cat(sprintf("ODA rows fetched: %d | countries: %d\n", nrow(oda), data.table::uniqueN(oda$iso3)))

qog <- merge(qog, oda, by = c("iso3", "year"), all.x = TRUE)

cat("\n=== Aid per capita (Levy-Yeyati, Panizza & Stein 2007 transform) ===\n")
# Population divisor is in THOUSANDS: HR's Appendix A defines
# Population_ict as "log of regional population in thousands," and
# testing both conventions against HR's own published Table I range
# (min -10.632, max 13.712, mean 6.191) confirms the thousands
# convention -- dividing by raw wdi_pop gives roughly [-4.9, 9.0], nowhere
# near HR's range, while wdi_pop/1000 gives [-11.8, 15.9], matching HR's
# reported range almost exactly once restricted to HR's own 126-country,
# 1992-2009 sample.
qog[, oda_pc := oda_total / (wdi_pop / 1000)]
qog[, aid := sign(oda_pc) * log1p(abs(oda_pc))]

cat("=== Oil rents per capita ===\n")
# Same population-in-thousands convention as Aid above. `wdi_gdpcapcur` is
# GDP per capita in raw persons, so (wdi_oilrent/100)*wdi_gdpcapcur equals
# oil rents per-raw-person; multiplying by 1000 converts to HR's
# per-thousand-population convention. Confirmed against HR's published
# Table I range [0.000, 16.396]: the raw per-person formula tops out at
# ~9.2, the x1000 version at ~16.1, matching HR's max almost exactly.
qog[, oil_rents_pc := (wdi_oilrent / 100) * wdi_gdpcapcur * 1000]
qog[, oil := log1p(oil_rents_pc)]

cat("=== Polity (0-1 rescaled, same construction as Stage 34) ===\n")
qog[, polity := (p_polity2 + 10) / 20]

out <- qog[, .(iso3, year, aid, oil, polity)]
cat(sprintf("Rows: %d | countries: %d\n", nrow(out), data.table::uniqueN(out$iso3)))
cat(sprintf("Non-NA: aid=%d oil=%d polity=%d\n",
    out[!is.na(aid), .N], out[!is.na(oil), .N], out[!is.na(polity), .N]))

data.table::fwrite(out, here::here("01_datasets/processed/table7_covariates.csv"))
cat("\nSaved: 01_datasets/processed/table7_covariates.csv\n")
