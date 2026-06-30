# Week 1 Tasks: Concrete Atomic Steps

**Goal:** End of week 1, pipeline runs end-to-end on Turkey for one test year, all reference data downloaded, working environment validated.

Each task is small, has a clear definition of done, and can be tackled independently.

---

## Day 1: Environment setup

### Task 1.1: Project directory structure
- [ ] Create `regional_favoritism/` root directory in your work space
- [ ] Create subdirectories per ROADMAP Section 5
- [ ] Move ROADMAP.md, CONTEXT.md, DATA_SOURCES.md, TURKEY_LEADERS.md to root
- [ ] Initialize git repository (`git init`)
- [ ] Create `.gitignore` excluding `data/raw/`, `data/processed/`, `output/`, `*.RData`, `*.tif`
- [ ] First commit: "Initial structure and planning documents"

**Done when:** `ls -la regional_favoritism/` shows the planned structure and `git log` shows one commit.

### Task 1.2: R environment
- [ ] Install or verify R version 4.3 or later
- [ ] Install core packages:
  ```r
  install.packages(c(
    "fixest", "modelsummary", "tidyverse", "data.table",
    "sf", "terra", "spdep", "spatialreg",
    "wbstats", "vdemdata",
    "reticulate", "arrow"
  ))
  ```
- [ ] Verify each package loads without error
- [ ] Document R version and package versions in `R/00_session_info.R`

**Done when:** `R/00_session_info.R` runs and outputs sessionInfo() without errors.

### Task 1.3: Python environment for GEE
- [ ] Verify reticulate can access Python 3 with earthengine-api
- [ ] If reusing from SDG project: confirm path `/Library/Frameworks/Python.framework/Versions/3.14/bin/python3` works
- [ ] Test authentication: `earthengine authenticate` in terminal
- [ ] Set default project: `earthengine set_project ee-turkey-research`
- [ ] Test in R: `reticulate::py_run_string("import ee; ee.Initialize(); print(ee.String('Hello GEE').getInfo())")`

**Done when:** R prints "Hello GEE" via reticulate.

---

## Day 2: Administrative boundaries

### Task 2.1: GADM 4.1 Turkey
- [ ] Download GADM 4.1 Turkey shapefile from `https://gadm.org/download_country.html`
- [ ] Extract to `data/raw/gadm_4.1/turkey/`
- [ ] Load in R:
  ```r
  library(sf)
  tur_adm1 <- st_read("data/raw/gadm_4.1/turkey/gadm41_TUR_1.shp")
  print(nrow(tur_adm1))  # should be 81
  print(names(tur_adm1))
  ```
- [ ] Verify 81 provinces present
- [ ] Verify post-1990 provinces present: Bartin, Karabuk, Yalova, Kilis, Osmaniye, Duzce
- [ ] Plot map and save as `output/figures/turkey_adm1_check.pdf`

**Done when:** Map plotted, 81 provinces confirmed.

### Task 2.2: GADM 4.1 global ADM2 (placeholder)
- [ ] Note: full global ADM2 is large (~1.5 GB). Defer download to Week 3.
- [ ] Decision: download per-country or use single global file?
  - Single file simpler but heavier
  - Per-country requires loop but more flexible
- [ ] Document decision in CONTEXT.md addendum

**Done when:** Decision documented, no download yet.

---

## Day 3: Leader birth places for Turkey

### Task 3.1: PLAD acquisition
- [ ] Visit Bomprezzi et al. 2025 CESifo Working Paper page: https://www.cesifo.org/en/publications/2024/working-paper/wedded-prosperity-informal-influence-and-regional-favoritism
- [ ] Check for replication data link in paper
- [ ] If not public, search Harvard Dataverse for "PLAD" or "Political Leaders Affiliation Database"
- [ ] Alternative: contact Bomprezzi directly via paper email (defer until Week 2 if needed)
- [ ] Download PLAD, place in `data/raw/plad/`
- [ ] Document PLAD version number in DATA_SOURCES.md

**Done when:** PLAD dataset available locally or alternative plan in place.

### Task 3.2: Turkey subset and validation
- [ ] Filter PLAD to Turkey (country code TUR or 640)
- [ ] List effective leaders 1992 to 2024
- [ ] Compare against TURKEY_LEADERS.md draft list
- [ ] Note discrepancies:
  - Missing leaders in PLAD?
  - Different birth place coding?
  - Different tenure dates?
- [ ] Update TURKEY_LEADERS.md with PLAD's coding marked clearly

**Done when:** TURKEY_LEADERS.md updated with PLAD-validated entries.

### Task 3.3: Manual cross-validation for ambiguous cases
- [ ] For each of: Erdoğan (Istanbul or Rize), Demirel (was he effective as President?), Davutoğlu and Yıldırım (were they effective with Erdoğan as President?), check three independent sources
- [ ] Document decision and reasoning in TURKEY_LEADERS.md Section 7

**Done when:** All ambiguous cases have a primary coding and a documented alternative.

---

## Day 4: Test GEE pipeline with NTL

### Task 4.1: DMSP-OLS test query
- [ ] In R via reticulate, query GEE for one year of DMSP-OLS for Turkey:
  ```r
  library(reticulate)
  ee <- import("ee")
  ee$Initialize()
  
  # DMSP-OLS for 2000
  dmsp <- ee$ImageCollection("NOAA/DMSP-OLS/NIGHTTIME_LIGHTS") $ 
    filterDate("2000-01-01", "2000-12-31") $ 
    select("stable_lights") $ 
    first()
  
  # Turkey boundaries as ee.FeatureCollection
  tur_geojson <- # convert tur_adm1 sf to GeoJSON, send to ee
  
  # Zonal statistics: mean per province
  zonal <- dmsp$reduceRegions(
    collection = tur_fc,
    reducer = ee$Reducer$mean(),
    scale = 1000
  )
  ```
- [ ] Export results to local CSV
- [ ] Verify 81 rows of output, one per province
- [ ] Save as `data/processed/turkey_dmsp_2000_test.csv`

**Done when:** CSV exists with 81 rows and DMSP-OLS mean values per Turkey province for year 2000.

### Task 4.2: VIIRS test query
- [ ] In R via reticulate, query GEE for one month of VIIRS for Turkey (June 2020):
  ```r
  viirs <- ee$ImageCollection("NOAA/VIIRS/DNB/MONTHLY_V1") $ 
    filterDate("2020-06-01", "2020-06-30") $ 
    select("avg_rad") $ 
    first()
  # similar zonal stats
  ```
- [ ] Export and save as `data/processed/turkey_viirs_2020_06_test.csv`
- [ ] Verify reasonable values (positive, varying across provinces)

**Done when:** CSV exists with 81 rows and VIIRS mean radiance values per Turkey province for June 2020.

### Task 4.3: Sanity check Erdoğan-Rize pattern
- [ ] Compare VIIRS values for Rize vs Turkey average in 2012 vs 2020
- [ ] Compute simple difference-in-differences:
  - (Rize 2020 minus Rize 2012) minus (Turkey average 2020 minus Turkey average 2012)
- [ ] Positive value suggests Rize disproportionate brightening during Erdoğan tenure
- [ ] Document result in `output/notes/sanity_check_rize.md`

**Done when:** Diff-in-diff calculated and documented. Result is informative regardless of sign.

---

## Day 5: Reference materials (DHR replication package) and institutional quality data

### Task 5.1: DHR replication package
- [ ] Visit https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/RRIN3P
- [ ] Download replication package (likely a zip file)
- [ ] Extract to `data/raw/dhr_replication/`
- [ ] Read README or documentation file
- [ ] Document structure: what files are there, what language (Stata, R, Python), what tables/figures they produce
- [ ] Write summary in `data/raw/dhr_replication/STRUCTURE_NOTES.md`
- [ ] **Important:** DHR is not the primary replication target (HR 2014 is). DHR's package serves as a reference for: (a) data construction choices we adopt, (b) modern coefficient benchmarks to compare against, (c) sample period extension methodology. We do not directly run DHR's code as primary specification.

**Done when:** DHR package downloaded, structure documented, role clarified in notes.

### Task 5.2: QoG Standard Dataset
- [ ] Download QoG Standard Dataset Jan26 from https://www.gu.se/en/quality-government/qog-data/data-downloads
- [ ] Place in `data/raw/qog/`
- [ ] Load in R:
  ```r
  library(haven)
  qog <- read_dta("data/raw/qog/qog_std_ts_jan26.dta")
  ```
- [ ] Identify columns needed:
  - p_polity2 (Polity5)
  - vdem_libdem (V-Dem Liberal Democracy)
  - wbgi_gee (WGI Government Effectiveness, may be coded differently)
  - bl_asyt15 (Barro-Lee schooling)
  - al_ethnic (Alesina ethnic fractionalization)
  - wdi_gdpcapcon2015 (GDP per capita)
- [ ] Document column names in DATA_SOURCES.md

**Done when:** QoG loaded, relevant columns identified.

### Task 5.3: Week 1 wrap up commit
- [ ] Commit all progress:
  ```
  git add R/ data/processed/*.csv output/notes/ data/raw/*/STRUCTURE_NOTES.md
  git commit -m "Week 1: environment setup, Turkey GADM and NTL pipeline validated"
  ```
- [ ] Update CONTEXT.md if any decisions changed
- [ ] Write `output/notes/week1_summary.md` with:
  - What was accomplished
  - What blockers exist (e.g. PLAD not yet acquired)
  - Adjusted plan for Week 2

**Done when:** Git commit pushed, week1_summary.md exists.

---

## Critical path

The most important tasks in Week 1, ordered by criticality:

1. **Task 1.3 (Python GEE access)** is critical. Without GEE, downloading NTL data manually is hours per year of data.
2. **Task 4.1 (DMSP-OLS test)** validates the entire data pipeline. If this fails, debug before proceeding.
3. **Task 3.1 (PLAD acquisition)** is the data dependency for Layer 2. If PLAD is hard to obtain, contact authors early.
4. **Task 5.1 (DHR replication package)** is the reference for Layer 1. Without it, replicating their numbers is harder.

If anything blocks progress, document the blocker in `output/notes/blockers.md` and proceed with non-blocked tasks.

---

## End of week deliverables

By end of Week 1, the user should have:

1. Working project structure with git
2. Validated R and Python environments
3. Turkey GADM 4.1 loaded and verified (81 provinces)
4. PLAD acquired and Turkey subset extracted (or fallback plan documented)
5. DMSP-OLS and VIIRS test queries successful for Turkey
6. DHR replication package downloaded and structure documented
7. QoG Standard Dataset loaded with relevant columns identified
8. week1_summary.md written, blockers documented
9. Git commit completed

**Deferred to later weeks:**
- EM-DAT academic registration and Turkey earthquake data download: Week 11 (start of Layer 4)
- Ohsome API feasibility test for OSM: Week 12 (Layer 4b decision point)

**Ready for Week 2:** Manual harmonization of PLAD ADM2 codes against GADM 4.1 for Turkey leaders.
