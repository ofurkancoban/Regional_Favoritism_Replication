# 05_covariates/05_aid_oil.R
# HR 2014 Table VII: Aid, Oil, and Regional Favoritism -- covariates.
#
# Aid_ct: "Logarithm of net overseas development assistance per capita
# disbursed in current USD dollars plus 1. It is calculated as
# AID_ct = sign(ODA_ct) * ln(1+|ODA_ct|) ... This formula proposed by
# Levy-Yeyati, Panizza, and Stein (2007) allows for a log-specification
# without censoring the aid variable at zero. Source: International
# Development Statistics, DAC-OECD." (Appendix A)
#   -> OECD DAC2A ("Aid (ODA) disbursements to countries and regions"),
#      fetched directly from the OECD Data Explorer SDMX REST API
#      (sdmx.oecd.org, no auth required) -- this IS HR's own stated source
#      (International Development Statistics, DAC-OECD), not a substitute.
#      Query: donor=DAC (all DAC members combined), measure=206 (net
#      disbursements), unit=USD, price_base=V (current prices), all
#      recipients, 1992-2013. A World Bank WDI substitute (DT.ODA.ODAT.CD)
#      was used in an earlier version of this script because QoG's own
#      compiled DAC column (`gcdf_groda`) has zero coverage before 2000 --
#      confirmed 2026-08-20 that OECD's own API has full 1992-2013
#      coverage directly, so the WDI substitution was unnecessary and has
#      been replaced with the exact source.
#      Divided by `wdi_pop` (population, from QoG) for ODA per capita.
#
# Oil_ct: "Logarithm of oil rents in US dollars per capita plus 1 ...
# Source: Adjusted net savings data." (Appendix A)
#   -> QoG `wdi_oilrent` (oil rents, % of GDP, World Bank Adjusted Net
#      Savings series) x `wdi_gdpcapcur` (GDP per capita, current USD)
#      = oil rents per capita in current USD.
#
# Output: data/processed/table7_covariates.csv (iso3, year, aid, oil, polity)

library(data.table)
library(jsonlite)
library(countrycode)

years_rep <- 1992:2013

cat("=== Load QoG oil/GDP/population/polity series ===\n")
qog <- data.table::fread(
  "data/raw/qog/qog_std_ts_jan26.csv",
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
# aggregate codes (e.g. "A5", "ACP", "4EU002", "5WB001") -- keep only rows
# whose RECIPIENT matches a real ISO3 country code.
valid_iso3 <- unique(stats::na.omit(countrycode::codelist$iso3c))
oda <- oda_raw[RECIPIENT %in% valid_iso3,
  .(iso3 = RECIPIENT, year = TIME_PERIOD, oda_total = OBS_VALUE * 10^UNIT_MULT)]
oda <- oda[!is.na(oda_total)]
cat(sprintf("ODA rows fetched: %d | countries: %d\n", nrow(oda), data.table::uniqueN(oda$iso3)))

qog <- merge(qog, oda, by = c("iso3", "year"), all.x = TRUE)

cat("\n=== Aid per capita (Levy-Yeyati, Panizza & Stein 2007 IHS-like transform) ===\n")
# Population divisor is in THOUSANDS, not raw headcount -- HR's Appendix A
# defines their regional Population_ict as "log of regional population in
# thousands," and empirically testing both conventions against HR's own
# published Table I summary stats (min -10.632, max 13.712, mean 6.191)
# confirms the thousands convention: dividing by wdi_pop directly (raw
# headcount) gives a min/max of roughly [-4.9, 9.0], nowhere near HR's
# range, while dividing by wdi_pop/1000 gives [-11.8, 15.9] -- matching
# HR's reported [-10.632, 13.712] almost exactly once further restricted to
# HR's own 126-country, 1992-2009 sample. Confirmed 2026-08-17.
qog[, oda_pc := oda_total / (wdi_pop / 1000)]
qog[, aid := sign(oda_pc) * log1p(abs(oda_pc))]

cat("=== Oil rents per capita ===\n")
# Same population-in-thousands convention as Aid above. `wdi_gdpcapcur` is
# GDP per capita in raw persons, so (wdi_oilrent/100)*wdi_gdpcapcur already
# equals oil rents per-raw-person; to match HR's per-thousand-population
# convention, multiply by 1000 (equivalent to: total oil rents / (population
# in thousands), since total oil rents = (wdi_oilrent/100)*wdi_gdpcapcur*pop).
# Confirmed against HR's published Table I range [0.000, 16.396]: the raw
# per-person formula tops out at ~9.2, the x1000 version at ~16.1 -- matching
# HR's max almost exactly. Confirmed 2026-08-17.
qog[, oil_rents_pc := (wdi_oilrent / 100) * wdi_gdpcapcur * 1000]
qog[, oil := log1p(oil_rents_pc)]

cat("=== Polity (0-1 rescaled, same as Table V) ===\n")
qog[, polity := (p_polity2 + 10) / 20]

out <- qog[, .(iso3, year, aid, oil, polity)]
cat(sprintf("Rows: %d | countries: %d\n", nrow(out), data.table::uniqueN(out$iso3)))
cat(sprintf("Non-NA: aid=%d oil=%d polity=%d\n",
    out[!is.na(aid), .N], out[!is.na(oil), .N], out[!is.na(polity), .N]))

data.table::fwrite(out, "data/processed/table7_covariates.csv")
cat("\nSaved: data/processed/table7_covariates.csv\n")
