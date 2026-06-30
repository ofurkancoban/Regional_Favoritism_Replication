# Week 1 Summary

Date: 2026-06-30

## Accomplished

1. Project directory structure created per ROADMAP Section 5.
2. .gitignore configured (excludes data/raw/, data/processed/, output/, *.tif, etc.)
3. R environment verified: all 13 required packages load without error (R 4.6).
   - fixest, modelsummary, tidyverse, data.table, sf, terra, spdep, spatialreg,
     wbstats, reticulate, arrow, haven, ggplot2
   - vdemdata not on CRAN; to be installed via remotes::install_github or replaced
     by raw V-Dem CSV download.
4. Python GEE environment verified: earthengine-api loads, ee.Initialize() succeeds
   on project ee-turkey-research, "Hello GEE" confirmed.
5. R scripts written and placed:
   - R/00_session_info.R -- package verification
   - R/01_data_download.R -- GADM 4.1 Turkey ADM1 load and verification
   - R/02_gee_ntl_test.R -- DMSP-OLS 2000 and VIIRS June 2020 zonal stats for Turkey,
                             plus Rize vs Turkey DiD sanity check
   - R/03_qog_load.R -- QoG Standard Dataset Jan26 loading
   - R/utils/gee_helpers.R -- GEE initialization and zonal stats helper functions
6. DHR replication package documented:
   - Package is in R (NOT Stata) -- favorable for our pipeline.
   - Uses GADM 3.6 (we use 4.1), same PLAD DOI, same QoG version.
   - Uses 5 NTL datasets; we start with DMSP-OLS + VIIRS + Chiovelli.
   - STRUCTURE_NOTES.md written at data/raw/dhr_replication/STRUCTURE_NOTES.md

## Blockers

1. GADM 4.1 Turkey ADM1 shapefile not yet downloaded.
   - Action: Download from https://gadm.org/download_country.html (Turkey, level 1)
   - Place at data/raw/gadm_4.1/turkey/gadm41_TUR_1.shp
   - R/01_data_download.R will run once file is present.

2. PLAD dataset not yet downloaded.
   - Action: Check Harvard Dataverse DOI 10.7910/DVN/YUS575 (Bomprezzi et al. 2025)
   - Place at data/raw/plad/
   - Turkey subset validation (Task 3.2) deferred to Week 2.

3. QoG Standard Dataset Jan26 not yet downloaded.
   - Action: Download from https://www.gu.se/en/quality-government/qog-data/data-downloads
   - Place at data/raw/qog/qog_std_ts_jan26.dta
   - R/03_qog_load.R will run once file is present.

4. NTL test queries (Tasks 4.1 and 4.2) not yet run.
   - Blocked by GADM shapefile (needed as FeatureCollection for zonal stats).
   - Will run R/02_gee_ntl_test.R once GADM file is present.

5. vdemdata R package requires GitHub install:
   - Run: remotes::install_github("vdeminstitute/vdemdata")
   - Alternative: download raw V-Dem CSV and load directly (no package needed).

## Adjusted plan for Week 2

- Day 1: Download GADM 4.1 Turkey, run R/01_data_download.R and R/02_gee_ntl_test.R
- Day 2: Download PLAD, run Turkey subset extraction (Task 3.2)
- Day 3-4: PLAD manual validation against TURKEY_LEADERS.md entries
- Day 5: Download QoG Jan26, run R/03_qog_load.R, identify column names

## Key decisions confirmed this week

- DHR replication package is R (not Stata): we can reference their code structure directly
- GEE project ee-turkey-research is operational: pipeline reuse confirmed
- vdemdata: will use raw CSV from V-Dem website to avoid GitHub-only package dependency
- NTL strategy: start with GEE for zonal stats, switch to LAADS direct download only if needed
