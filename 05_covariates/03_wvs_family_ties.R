# 05_covariates/03_wvs_family_ties.R
# HR 2014 Table V: FamilyTies_c -- "Measure of the strength of family ties
# based on the first principal component of three variables in the World
# Value Survey, which capture beliefs on the importance of the family in
# an individual's life, the duties and responsibilities of parents and
# children, and the love and respect for one's own parents." Source cited
# by HR 2014: Alesina and Giuliano (forthcoming) = Alesina & Giuliano
# (2014), "Family Ties," Handbook of Economic Growth Vol. 2A, pp.177-215.
#
# That chapter (and its 2010 predecessor "The Power of the Family") never
# publishes a raw country-level lookup table -- country values are only
# shown as a map/figure (Figure 5), not a table (confirmed by reading the
# full chapter PDF, 01_literature/familyties_march2013.pdf). The index is
# computed by the authors from WVS individual-level microdata: the FIRST
# PRINCIPAL COMPONENT of three WVS questions at the individual-respondent
# level, then averaged to the country level.
#
# The three WVS questions (chapter Section 4.1, verbatim) and their
# confirmed WVS Trend File variable codes (verified against
# data/raw/wvs/F00003844-..._v3_1.xlsx, the official WVS equivalence table):
#   Q1 -> A001 "Important in life: Family" (1=not important .. 4=very important)
#   Q2 -> A026 "Parents responsibilities to their children" (parents have a
#         life of their own [1] vs. parents' duty to do their best for
#         their children even at their own expense [2])
#   Q3 -> A025 "Respect and love for parents" (no unconditional duty [1] vs.
#         must always love/respect parents regardless of their qualities [2])
#
# IMPORTANT CAVEAT: per the WVS equivalence table, A025 and A026 are only
# mapped in WVS waves 1-4 (1981-2004) -- they are NOT present in WVS5-7
# (2005-2022). This matches a footnote in the Handbook chapter itself:
# "Alesina and Giuliano (2010) only used four waves, having a substantially
# smaller sample size" [than the 2014 chapter's later six-wave claim for
# OTHER measures in the same chapter]. This script therefore reproduces the
# ORIGINAL 4-wave (1981-2004) version of the index, which is very likely
# what HR 2014 (published based on research conducted ~2011-2013) actually
# had access to, rather than a later 6-wave extension whose equivalent
# variable codes (if any exist under different names in WVS5-7) were not
# found in the available codebook.
#
# Data source: WVS Trend File "Timeseries (1981-2022)", data/raw/wvs/
#   (free registration at worldvaluessurvey.org; NOT auto-downloadable)
#
# EVS extension (2026-08-19): the EVS (European Values Study) Trend File
# 1981-2017 (GESIS ZA7503, data/raw/wvs/ZA7503_v3-0-0.dta/) asks the same
# three A001/A025/A026 questions and is a fully separate survey program
# from WVS (mostly European/EU-adjacent coverage) -- pooling it in adds 13
# countries not in our WVS-derived set, 8 of which are in HR's 126-country
# sample (AUT, BEL, DNK, FRA, GRC, ITA, NLD, PRT), raising FamilyTies
# coverage of HR126 leader-birth-regions from 188/386 (49%) to 212/386
# (55%). Checked and ruled out first: the newer "leaner" EVS_WVS_Joint
# harmonized file (IVS 2021 concept, data/raw/wvs/EVS_WVS_Joint_Csv_v5_0.csv)
# does NOT carry A025/A026 at all -- they didn't meet the new trend-file
# inclusion threshold -- so the two source Trend Files must be combined
# directly, not via that joint file.
#
# Output: data/processed/family_ties_country.csv (country-level index, cross-sectional, ISO3-keyed)

library(data.table)
library(haven)
library(countrycode)

wvs_path <- "data/raw/wvs/WVS_Time_Series_1981-2022_csv_v5_0.csv"
evs_path <- "data/raw/wvs/ZA7503_v3-0-0.dta/ZA7503_v3-0-0.dta"
if (!file.exists(wvs_path)) stop(sprintf("WVS Trend File not found at %s.", wvs_path))
if (!file.exists(evs_path)) stop(sprintf("EVS Trend File not found at %s.", evs_path))

cat("=== Load WVS Trend File (selected columns only, ~1.3GB full file) ===\n")
wvs <- data.table::fread(wvs_path, select = c("COUNTRY_ALPHA", "A001", "A025", "A026"))
data.table::setnames(wvs, c("iso3", "q1", "q2", "q3"))
cat(sprintf("WVS rows: %d\n", nrow(wvs)))

cat("\n=== Load EVS Trend File (selected columns only) ===\n")
evs <- data.table::as.data.table(haven::read_dta(evs_path, col_select = c("COW_NUM", "A001", "A025", "A026")))
# EVS splits the UK into COW 201 (Great Britain) and 202 (Northern Ireland)
# rather than using the standard sovereign-state COW code 200 -- neither
# 201 nor 202 is a real Correlates-of-War code, so countrycode's built-in
# "cown" table leaves them unmapped (confirmed 2026-08-19: this silently
# dropped 5,402 valid GBR respondent-rows, the only reason GBR appeared
# in the WVS Trend File with zero valid A025/A026 responses but is
# missing from our final country index entirely).
# COW 348 = Serbia -- not in countrycode's "cown" table under this code
# (348 is EVS/Serbia-specific; the standard COW code is 340/345 depending
# on period) and is in HR's 126-country sample (2 leader-birth-regions).
# COW 347 (Kosovo) and 353 (Northern Cyprus) are also unmapped but neither
# is in HR's 126-country sample, so left unmapped deliberately -- Kosovo
# has no standard sovereign-state COW code (contested statehood) and
# Northern Cyprus is not a GADM level0 country of its own, so mapping
# either would require a judgment call this project doesn't need to make.
evs[, iso3 := countrycode::countrycode(as.integer(COW_NUM), "cown", "iso3c", warn = FALSE,
                                        custom_match = c("201" = "GBR", "202" = "GBR", "348" = "SRB"))]
evs <- evs[!is.na(iso3), .(iso3, q1 = as.numeric(A001), q2 = as.numeric(A025), q3 = as.numeric(A026))]
cat(sprintf("EVS rows (mapped to ISO3): %d\n", nrow(evs)))

# WVS Wave 4 standalone release (data/raw/wvs/WV4_Data_csv_v20201117.csv):
# A025/A026 are absent from the pooled Trend File for waves 5-7 but were
# asked in Wave 4 itself, under wave-specific codes V4/V13/V14 (per the
# WVS equivalence table, F00003844-...v3_1.xlsx). Almost entirely redundant
# with the Trend File above (37 of 39 countries already covered there) --
# the one addition that matters for HR's 126-country sample is Iraq (4
# leader-birth-regions), so it is worth folding in. Confirmed 2026-08-19.
wv4_path <- "data/raw/wvs/WV4_Data_csv_v20201117.csv"
if (file.exists(wv4_path)) {
  wv4 <- data.table::fread(wv4_path, select = c("C_COW_ALPHA", "V4", "V13", "V14"))
  # PRI (Puerto Rico) has valid V4/V13/V14 responses but is a US territory,
  # not a sovereign country and not in HR's 126-country sample -- left
  # unmapped deliberately, same reasoning as Kosovo/Northern Cyprus above.
  wv4[, iso3 := countrycode::countrycode(C_COW_ALPHA, "cowc", "iso3c", warn = FALSE,
                                          custom_match = c("SRB" = "SRB"))]
  wv4 <- wv4[!is.na(iso3), .(iso3, q1 = as.numeric(V4), q2 = as.numeric(V13), q3 = as.numeric(V14))]
  cat(sprintf("WV4 rows (mapped to ISO3): %d\n", nrow(wv4)))
} else {
  wv4 <- data.table::data.table(iso3 = character(), q1 = numeric(), q2 = numeric(), q3 = numeric())
}

# Pool WVS + EVS respondent-level rows into one dataset before computing
# PC1, rather than computing two separate PCAs and appending country
# means -- this keeps every country's index on the same latent-component
# scale (a per-survey PCA could flip sign or rescale independently, which
# would silently break comparability between WVS-only and EVS-only
# countries in the final index).
wvs[, source := "WVS"]
evs[, source := "EVS"]
wv4[, source := "WV4"]
d <- rbind(wvs, evs, wv4)

# WVS/EVS use negative codes for missing/don't know/not asked -- drop those.
# A026 has a rare 3rd response category (~2% of valid responses, likely an
# added "both/neither" option in some wave) -- keep it as-is, matching
# whatever the survey instrument actually offered; PCA does not require
# strict binary coding.
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

# PC1's sign is arbitrary and cannot be reliably inferred from the raw
# item-coding direction alone (A025/A026's 1/2 coding order in the WVS file
# does not match the (1)/(2) statement order as narrated in the paper's
# prose -- verified empirically: an unflipped PC1 put Scandinavian
# countries at the top and Egypt/Zimbabwe/Philippines/Venezuela at the
# bottom, the EXACT OPPOSITE of the country pattern the chapter itself
# describes ("Scandinavian countries... tend to have the weakest levels of
# family ties... more familistic societies are Italy... Latin American
# countries... extreme: Guatemala, Venezuela... Egypt and Zimbabwe...
# Indonesia, Vietnam and the Philippines"). Flipping the sign here
# reproduces that exact pattern, confirming the methodology is otherwise
# correct.
pc1 <- -pca$x[, 1]
d[, family_ties_pc1 := pc1]

cat("\n=== Aggregate to country level ===\n")
country_index <- d[, .(family_ties = mean(family_ties_pc1, na.rm = TRUE), n_respondents = .N), by = iso3]
data.table::setorder(country_index, -family_ties)

cat(sprintf("\nFinal country coverage: %d\n", nrow(country_index)))
data.table::fwrite(country_index, "data/processed/family_ties_country.csv")
cat("Saved: data/processed/family_ties_country.csv\n")
