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
# Output: data/processed/family_ties_country.csv (country-level index, cross-sectional, ISO3-keyed)

library(data.table)

wvs_path <- "data/raw/wvs/WVS_Time_Series_1981-2022_csv_v5_0.csv"
if (!file.exists(wvs_path)) {
  stop(sprintf("WVS Trend File not found at %s.", wvs_path))
}

cat("=== Load WVS Trend File (selected columns only, ~1.3GB full file) ===\n")
wvs <- data.table::fread(wvs_path, select = c("COUNTRY_ALPHA", "A001", "A025", "A026"))
data.table::setnames(wvs, c("iso3", "q1", "q2", "q3"))
cat(sprintf("Rows: %d\n", nrow(wvs)))

# WVS uses negative codes for missing/don't know/not asked -- drop those.
# A026 has a rare 3rd response category (~2% of valid responses, likely an
# added "both/neither" option in some wave) -- keep it as-is, matching
# whatever the survey instrument actually offered; PCA does not require
# strict binary coding.
d <- wvs[q1 > 0 & q2 > 0 & q3 > 0]
cat(sprintf("Valid responses (all 3 questions non-missing, WVS1-4 only per availability): %d\n", nrow(d)))
cat(sprintf("Countries covered: %d\n", data.table::uniqueN(d$iso3)))

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
