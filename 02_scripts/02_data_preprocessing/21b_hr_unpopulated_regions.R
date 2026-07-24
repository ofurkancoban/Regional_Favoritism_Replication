# ==============================================================================
# File:          21b_hr_unpopulated_regions.R
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
# Category:      Data Preprocessing
#
# Description:   Builds the third of HR 2014's three stated "exact sample"
#                exclusion criteria (p. 1001) -- alongside the
#                <500k-population country list and the >65N latitude
#                cutoff already applied everywhere -- HR 2014 also drop
#                "the few regions that are unpopulated." This project's
#                own panel had no exclusion list for that criterion at
#                all (found during a paper audit, 2026-09-04); this
#                script closes that gap for the ADM2-level tables (Table
#                I, Table II), where a population figure per region-year
#                already exists to test.
#
#                IMPORTANT CAVEAT, tested and confirmed before this
#                script was written: "unpopulated" here is a proxy, not a
#                verified match to HR 2014's own criterion.
#                analysis_panel.csv's lnpop column comes from a LEFT JOIN
#                against the GPWv4 zonal-population source (Stage 21,
#                Step 4) -- a region-year with no matching population row
#                gets lnpop = NA whether that region is genuinely
#                uninhabited (HR 2014's own meaning) or the GPWv4
#                zonal-sum simply failed to match it (a small island, a
#                newly-split ADM2 unit, a raster coverage gap -- a data
#                artifact, not depopulation). This script cannot tell
#                those two cases apart; it only identifies regions with
#                NO population match in ANY observed year of the
#                HR-exact window, the closest available proxy.
#
#                Tested via a standalone comparison before being wired
#                into the main pipeline (85 regions found, 0.06% of
#                region-years in the HR sample): every Table II
#                coefficient was unchanged to 3 decimals except Column
#                (5), which moved from 0.051 to 0.050 -- noise, not a
#                substantive finding. Applied here despite the negligible
#                effect, for completeness against the authors' own
#                three-part criterion, not because it changes any
#                conclusion.
#
#                Scope: only the ADM2-level tables (Table I, Table II)
#                use this list. Table IV's alternative units of
#                observation (5km birthplace circles, SN1/ADM1 regions,
#                equal-area grid cells) each have their own spatial
#                aggregation with no equivalent population match already
#                built, so this exclusion is not extended to those
#                tables -- see paper.qmd Section 3.3 for how that scope
#                limit is stated.
#
# Inputs:        01_datasets/processed/analysis_panel.csv,
#                01_datasets/raw/plad/hr2014_126_countries.csv,
#                01_datasets/processed/hr_excluded_above65n_regions.csv
# Outputs:       01_datasets/processed/hr_excluded_unpopulated_regions.csv
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

years_hr <- 1992:2009

cat("=== Load analysis panel, restrict to HR's exact sample (excl. unpopulated) ===\n")
d <- data.table::fread(here::here("01_datasets/processed/analysis_panel.csv"))
hr126 <- data.table::fread(here::here("01_datasets/raw/plad/hr2014_126_countries.csv"))
hr_65n <- data.table::fread(here::here("01_datasets/processed/hr_excluded_above65n_regions.csv"))
d <- d[iso3 %in% hr126$iso3]
d <- d[!gid_2 %in% hr_65n$gid_2]
d <- d[year %in% years_hr]
cat(sprintf("Panel before unpopulated-region check: %d obs | %d regions\n",
    nrow(d), data.table::uniqueN(d$gid_2)))

unpopulated <- unique(d[, .(never_matched = all(is.na(lnpop))), by = gid_2][
  never_matched == TRUE, .(gid_2)
])
cat(sprintf("Regions with no population match in any observed year: %d (%.2f%% of region-years)\n",
    nrow(unpopulated), 100 * nrow(d[gid_2 %in% unpopulated$gid_2]) / nrow(d)))

data.table::fwrite(unpopulated, here::here("01_datasets/processed/hr_excluded_unpopulated_regions.csv"))
cat("Saved: 01_datasets/processed/hr_excluded_unpopulated_regions.csv\n")
