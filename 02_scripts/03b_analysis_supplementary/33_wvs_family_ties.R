# ==============================================================================
# File:          33_wvs_family_ties.R
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
# Description:   Builds FamilyTies_c, HR 2014's Table V covariate for the
#                strength of family ties: the first principal component of
#                three World Values Survey / European Values Study items
#                (importance of family, parents' duty to children, duty to
#                love/respect parents), averaged to the country level. HR's
#                own source, Alesina & Giuliano (2014), never publishes a
#                raw country lookup table (only a map figure), so this
#                script reconstructs the index from WVS/EVS microdata
#                directly, following the chapter's own stated methodology
#                (Section 4.1). The WVS/EVS question codes A025/A026 are
#                only present in waves 1-4 (1981-2004), not waves 5-7, so
#                this reproduces the original 4-wave version of the index,
#                matching what HR 2014 itself would have had access to.
#
#                SHIPPED, GZIP-COMPRESSED: unlike most of this project's
#                other manually-downloaded sources, the WVS Trend File
#                (1.3GB) and EVS Trend File (192MB) ship WITH this
#                package, gzip-compressed to ~121MB and ~35MB respectively
#                and tracked via Git LFS (see .gitattributes and
#                README.md's "What's physically shipped vs. symlinked").
#                WVS/EVS's own terms permit redistribution of the Trend
#                Files for academic, non-commercial research use, which
#                this replication package is. This stage reads the CSV
#                .gz directly (data.table::fread() decompresses gzip
#                in-stream) and decompresses the .dta.gz to a session
#                temp file before handing it to haven::read_dta(), which
#                has no native gzip support of its own.
#
# Inputs:        01_datasets/raw/wvs/WVS_Time_Series_1981-2022_csv_v5_0.csv.gz,
#                01_datasets/raw/wvs/ZA7503_v3-0-0.dta.gz,
#                01_datasets/raw/wvs/WV4_Data_csv_v20201117.csv.gz (optional)
# Outputs:       01_datasets/processed/family_ties_country.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

wvs_path <- here::here("01_datasets/raw/wvs/WVS_Time_Series_1981-2022_csv_v5_0.csv.gz")
evs_path <- here::here("01_datasets/raw/wvs/ZA7503_v3-0-0.dta.gz")
require_input_file(wvs_path, "WVS Trend File (1981-2022, gzip-compressed)",
  "n/a -- ships with this package via Git LFS", "Shipped",
  note = "If missing, run `git lfs pull` (see README.md, 'What's physically shipped vs. symlinked').")
require_input_file(evs_path, "EVS Trend File (ZA7503, gzip-compressed)",
  "n/a -- ships with this package via Git LFS", "Shipped",
  note = "If missing, run `git lfs pull`.")

cat("=== Load WVS Trend File (selected columns only, gzip decompressed in-stream) ===\n")
wvs <- data.table::fread(wvs_path, select = c("COUNTRY_ALPHA", "A001", "A025", "A026"))
data.table::setnames(wvs, c("iso3", "q1", "q2", "q3"))
cat(sprintf("WVS rows: %d\n", nrow(wvs)))

cat("\n=== Load EVS Trend File (selected columns only) ===\n")
# haven::read_dta() has no native gzip support, unlike fread() above, so
# the .dta.gz is decompressed to a session temp file first and read from
# there; the temp file is removed once loaded, regardless of outcome.
evs_tmp <- tempfile(fileext = ".dta")
R.utils::gunzip(evs_path, destname = evs_tmp, remove = FALSE, overwrite = TRUE)
on.exit(unlink(evs_tmp), add = TRUE)
evs <- data.table::as.data.table(haven::read_dta(evs_tmp, col_select = c("COW_NUM", "A001", "A025", "A026")))
# EVS splits the UK into COW 201 (Great Britain) and 202 (Northern Ireland)
# rather than the standard sovereign-state COW code 200, and COW 348
# (Serbia) is EVS-specific -- countrycode's "cown" table leaves these
# unmapped without an explicit custom_match, which would silently drop
# GBR entirely from the final index.
evs[, iso3 := countrycode::countrycode(as.integer(COW_NUM), "cown", "iso3c", warn = FALSE,
                                        custom_match = c("201" = "GBR", "202" = "GBR", "348" = "SRB"))]
evs <- evs[!is.na(iso3), .(iso3, q1 = as.numeric(A001), q2 = as.numeric(A025), q3 = as.numeric(A026))]
cat(sprintf("EVS rows (mapped to ISO3): %d\n", nrow(evs)))

# WVS Wave 4 standalone release: A025/A026 are absent from the pooled
# Trend File for waves 5-7 but were asked in Wave 4 itself under
# wave-specific codes V4/V13/V14. Almost entirely redundant with the
# Trend File above; the one addition that matters for HR's 126-country
# sample is Iraq. Optional: this file is smaller and less critical than
# the two above, so its absence only drops Iraq rather than halting the
# stage.
wv4_path <- here::here("01_datasets/raw/wvs/WV4_Data_csv_v20201117.csv.gz")
if (file.exists(wv4_path)) {
  wv4 <- data.table::fread(wv4_path, select = c("C_COW_ALPHA", "V4", "V13", "V14"))
  wv4[, iso3 := countrycode::countrycode(C_COW_ALPHA, "cowc", "iso3c", warn = FALSE,
                                          custom_match = c("SRB" = "SRB"))]
  wv4 <- wv4[!is.na(iso3), .(iso3, q1 = as.numeric(V4), q2 = as.numeric(V13), q3 = as.numeric(V14))]
  cat(sprintf("WV4 rows (mapped to ISO3): %d\n", nrow(wv4)))
} else {
  cat("WV4 standalone file not found, skipping (only affects Iraq's coverage).\n")
  wv4 <- data.table::data.table(iso3 = character(), q1 = numeric(), q2 = numeric(), q3 = numeric())
}

# Pool WVS + EVS + WV4 respondent-level rows into one dataset before
# computing PC1, rather than three separate PCAs, so every country's
# index sits on the same latent-component scale.
wvs[, source := "WVS"]
evs[, source := "EVS"]
wv4[, source := "WV4"]
d <- rbind(wvs, evs, wv4)

# WVS/EVS use negative codes for missing/don't know/not asked.
d <- d[q1 > 0 & q2 > 0 & q3 > 0]
cat(sprintf("\nPooled valid responses (all 3 questions non-missing): %d\n", nrow(d)))
wvs_c <- unique(d[source == "WVS"]$iso3)
evs_new <- setdiff(unique(d[source == "EVS"]$iso3), wvs_c)
wv4_new <- setdiff(unique(d[source == "WV4"]$iso3), c(wvs_c, evs_new))
cat(sprintf("Countries covered: %d (WVS: %d, EVS added: %d, WV4 added: %d)\n",
    data.table::uniqueN(d$iso3), length(wvs_c), length(evs_new), length(wv4_new)))

cat("\n=== Compute first principal component (individual level) ===\n")
pca <- stats::prcomp(d[, .(q1, q2, q3)], scale. = TRUE)
cat("Variance explained by PC1:", round(summary(pca)$importance[2, 1], 3), "\n")

# PC1's sign is arbitrary; flipped here to match the country pattern the
# Alesina & Giuliano (2014) chapter itself describes (Scandinavian
# countries weakest, Egypt/Zimbabwe/Philippines/Venezuela strongest),
# verified empirically against an unflipped run.
pc1 <- -pca$x[, 1]
d[, family_ties_pc1 := pc1]

cat("\n=== Aggregate to country level ===\n")
country_index <- d[, .(family_ties = mean(family_ties_pc1, na.rm = TRUE), n_respondents = .N), by = iso3]
data.table::setorder(country_index, -family_ties)

cat(sprintf("\nFinal country coverage: %d\n", nrow(country_index)))
data.table::fwrite(country_index, here::here("01_datasets/processed/family_ties_country.csv"))
cat("Saved: 01_datasets/processed/family_ties_country.csv\n")
