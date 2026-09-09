# Regional Favoritism

## A Replication and Extension of Hodler & Raschky (2014)

This package reproduces every table reported in the paper and its
supplementary materials, from raw data through the final PDF and
presentation, following a 41-stage numbered pipeline. Figures 1 and 2
ship pre-built rather than regenerating on every run (see "Scope" below).

Hodler and Raschky (2014, *QJE*) find that a region grows brighter at
night while it is the birth region of the sitting political leader,
evidence of regional favoritism. This package rebuilds that finding on an
independently constructed pipeline (GADM boundaries instead of the
authors' CIESIN source, PLAD plus a Wikidata supplement for birthplaces,
DMSP-OLS composites extracted locally), then extends it to a harmonized
DMSP/VIIRS panel running through 2023. See `04_paper/paper.qmd` for the
full text and `04_paper/supplementary.qmd` for the supplementary tables --
both, and the `05_presentation/` slide deck, ship inside this package (see
"Paper and presentation" below), and are also published as a website (see
"Website" below).

### Website

The paper, supplementary materials, and presentation are also published
via GitHub Pages, built from the `docs/` folder on this repository's
`main` branch (Settings > Pages). `docs/` holds plain copies of the
already self-contained (`embed-resources: true`) HTML/PDF outputs from
`04_paper/` and `05_presentation/` -- `make site` refreshes them after
`make render`; commit and push `docs/` to publish an update.

### Scope

The package is organized in two analysis phases:

- **Core** (`03a_analysis_core/`, Stages 22-30): what the main paper
  reads — Table 1 (descriptive statistics), Table 2 (HR 2014 Table II
  replication), Table 3/Figure 2 (HR 2014 Table IV replication, all seven
  columns), and the 1992-2023 extension table.
- **Supplementary** (`03b_analysis_supplementary/`, Stages 33-39): what
  `supplementary.qmd` additionally reads — the FamilyTies WVS/EVS index,
  the Table V/VII covariates, and HR 2014 Table III (dynamics), Table V
  (determinants), Table VI (continents), and Table VII (aid/oil).

Side-investigations not reported in either document (the ethnic-homeland
extension, the Turkey earthquake case study, non-exact-sample regression
variants) and HR 2014's own Online Appendix are out of scope for this
package.

Figures 1 and 2 (`02_scripts/03a_analysis_core/31_figure1_goh.R` and
`32_figure2_erdogan_units.R`) are not wired into `make core` or any
`--stage` target: they need raw inputs `make preprocess` doesn't provide
(GADM 3.6, and DMSP rasters kept past their preprocess-stage lifetime).
Their outputs ship pre-built at `04_paper/img/goh_combined_paper.{pdf,svg}`
and `04_paper/img/erdogan_gis_units_paper.pdf` -- already embedded in
`paper.pdf`/`paper.html` -- so a normal run of this package never needs
to touch them. Run either script directly, with that raw data in place,
only if you want to regenerate a figure from source.

---

## Quickstart

The large files this pipeline produces are tracked with Git LFS and
shipped in this repository, so a fresh clone can reproduce every table
(Figures 1 and 2 ship pre-built, see "Scope" above) without downloading
or processing any raw data:

```bash
git lfs install                                  # once per machine
git clone https://github.com/ofurkancoban/Regional_Favoritism_Replication.git
cd replication_package
make init                                              # install R packages
Rscript 02_scripts/01_setup/setup_environment.R --stage=core
Rscript 02_scripts/01_setup/setup_environment.R --stage=supplementary
Rscript 02_scripts/01_setup/verify_outputs.R           # checks headline numbers
```

Reproducing the upstream pipeline that builds these files from raw data
(Stages 01-21: downloads, geometry, nighttime-lights extraction) is a
slower, partly manual path, described below under "Raw data that cannot
be downloaded automatically."

Stages 24, 25, 29, and 30 also write a standalone, browsable HTML view of
Table 1, Table 2, Table 4, and the extension table to
`03_results/tables/html/`, viewable in a browser without compiling
`paper.pdf`.

---

## Reproducibility Guide

This package uses `renv` for dependency management and a `Makefile` for
pipeline orchestration.

### Method 1: Make (recommended)

```bash
make init          # install exact package versions from renv.lock
make preprocess     # stages 01-21
make core           # stages 22-30: main paper's tables, extension
make extension      # stage 30 only: the 1992-2023 extension, already in make core
make supplementary  # stages 33-39: supplementary.qmd's Table III, V, VI, VII
make render         # stages 40-41: paper + supplementary + presentation
```

GADM 3.6, G-Econ, GPWv3, GPWv4, and GHS-POP require a manual,
registration-gated download before `make preprocess` (see below). GADM
4.1, DMSP, and VIIRS download automatically as part of `make preprocess`.
`make core`, `make extension`, and `make supplementary` need nothing
manual: PLAD, Archigos, QoG, and the WVS/EVS Trend Files ship with this
repository.

### Method 2: R orchestrator

```r
# from regional_favoritism_replication.Rproj
source("02_scripts/01_setup/setup_environment.R")
```

Pass `--stage=preprocess`, `--stage=core`, `--stage=extension`,
`--stage=supplementary`, or `--stage=render` via `commandArgs()` to run
a subset.

### Method 3: Granular targets

| Target                                           | Stages | Description                                                                                       |
| ------------------------------------------------ | ------ | ------------------------------------------------------------------------------------------------- |
| `make init`                                    | —     | Install package versions pinned in`renv.lock`                                                   |
| `make preprocess`                              | 01-21b | Geometry, nighttime-lights extraction, covariates, panel assembly                                 |
| `make core`                                    | 22-30  | Main paper's regression tables, extension                                                         |
| `make extension`                               | 30     | The 1992-2023 extension table alone, already included in`make core`                             |
| `make supplementary`                           | 33-39  | supplementary.qmd's Table III, V, VI, VII                                                         |
| `make paper`                                   | 40     | Render the paper and supplementary materials (PDF)                                                |
| `make presentation`                            | 41     | Render the Reveal.js presentation (HTML)                                                          |
| `Rscript 02_scripts/01_setup/verify_outputs.R` | —     | Checks every headline coefficient against the paper's reported values; exits non-zero on mismatch |

---

## Pipeline Overview

```mermaid
flowchart LR
    RAW["<b>RAW DATA</b><br/>GADM · DMSP · VIIRS<br/>G-Econ · GPW"]

    subgraph PRE["📥 PREPROCESS — Stages 01–21"]
        direction TB
        PRE1["Download GADM · DMSP · VIIRS"]
        PRE2["Fill Wikidata birthplace gaps"]
        PRE3["Build grid cells & hole-punch<br/>ADM1 geometry"]
        PRE4["Extract nighttime lights<br/>(DMSP / VIIRS zonal stats)"]
        PRE5["Build GDP & population covariates"]
        PRE6["<b>Assemble the analysis panel</b>"]
        PRE1 --> PRE2 --> PRE3 --> PRE4 --> PRE5 --> PRE6
    end

    PANEL[("analysis_panel.csv")]

    subgraph CORE["📊 CORE — Stages 22–30"]
        direction TB
        C1["Table I — descriptives"]
        C2["Table II — replication"]
        C3["Table IV — circles/grid"]
        C4["Extension table 1992–2023"]
    end

    FIGS["🖼️ Figures 1 &amp; 2<br/><i>pre-built, shipped</i><br/>Stages 31–32, manual only"]

    subgraph SUPP["📁 SUPPLEMENTARY — Stages 33–39"]
        direction TB
        S1["FamilyTies index (WVS+EVS)"]
        S2["Table III — dynamics"]
        S3["Table V — determinants"]
        S4["Table VI — continents"]
        S5["Table VII — aid / oil"]
    end

    subgraph REND["📄 RENDER — Stages 40–41"]
        direction TB
        R1["paper.qmd + supplementary.qmd → PDF"]
        R2["05_presentation/index.qmd → HTML slide deck"]
    end

    OUT["<b>OUTPUTS</b><br/>paper.pdf + slides.html"]

    RAW --> PRE --> PANEL
    PANEL --> CORE --> REND
    PANEL --> SUPP --> REND
    FIGS -.-> REND
    REND --> OUT

    style RAW fill:#1f2937,stroke:#64748b,color:#e2e8f0
    style PANEL fill:#0f766e,stroke:#2dd4bf,color:#e6fffb
    style FIGS fill:#1e1b2e,stroke:#8b7fd6,color:#e8e4ff,stroke-dasharray: 4 3
    style PRE fill:#16233a,stroke:#5aa9e6,color:#eaf4ff
    style CORE fill:#3d3113,stroke:#f2b544,color:#fff8e6
    style SUPP fill:#0f3d3a,stroke:#4fd1c5,color:#ecfffe
    style REND fill:#3d1729,stroke:#e0729a,color:#fff0f6
    style OUT fill:#7c2d12,stroke:#fb923c,color:#fff7ed
```

`make preprocess` produces `analysis_panel.csv`, the single shared input
for both `make core` and `make supplementary`. The two analysis phases
are independent of each other and can run in either order or in
parallel; both must complete before `make render` produces a PDF that
reflects current results.

---

## Project Structure

```text
.
├── 01_datasets/
│   ├── raw/                        # inputs under ~50MB tracked directly;
│   │                                #   larger files via Git LFS or symlink
│   ├── processed/                  # same convention as raw/
│   └── final/                      # small package-local outputs
├── 02_scripts/
│   ├── 01_setup/                   # pipeline orchestrator, pre-flight checks
│   ├── 02_data_preprocessing/      # Stages 01-21
│   ├── 03a_analysis_core/          # Stages 22-32
│   ├── 03b_analysis_supplementary/ # Stages 33-39
│   └── 04_tools/                   # shared helper functions (utils.R)
├── 03_results/
│   ├── figures/                    # Figure 1 and Figure 2
│   └── tables/html/                # Table 1, 2, 4, and the extension table (gt)
├── 04_paper/                       # the paper and supplementary materials
│   ├── 40_Render_Paper.R           # renders paper.qmd, supplementary.qmd
│   ├── paper.qmd, supplementary.qmd
│   ├── paper.pdf, paper.html, supplementary.pdf, supplementary.html
│   ├── references.bib, elsarticle.cls, elsarticle-harv.bst, before-body.tex
│   ├── img/, R/, _extensions/
├── 05_presentation/                # the Reveal.js slide deck
│   ├── 41_Render_Presentation.R    # renders index.qmd
│   ├── index.qmd, index.html, Coban_RegionalFavoritism.pdf
│   ├── theme.scss, references.bib, apa.csl
│   ├── img/, _assets/, _extensions/
├── Makefile
├── renv.lock
└── regional_favoritism_replication.Rproj
```

### Paper and presentation

`04_paper/` and `05_presentation/` ship as real, physical copies inside
this package -- not symlinks, not rendered from an outside "main
repository" -- since this package is itself the repository root on
GitHub. Both PDF and HTML are already built and included, so opening
`04_paper/paper.pdf` or `05_presentation/index.html` needs no rendering
step at all; `make paper` / `make presentation` (Stages 40-41) only matter
if you edit the `.qmd` source and want to rebuild. The four result
tables `paper.qmd` reads (Table I/II/IV, the extension table) and the
supplementary tables `supplementary.qmd` reads point at this package's
own `01_datasets/processed/ntl/` outputs, so re-running `make core` /
`make supplementary` before re-rendering the paper picks up any new
numbers automatically.

---

## Data

### Shipped with this package

Every input under ~50MB that a script in this package reads is tracked
directly as git content. Ten larger, project-derived files (the analysis
panel, the harmonized DMSP/VIIRS panel, hole-punched ADM1 geometry, grid
cells at four resolutions, the extension's fitted models, and the QoG
Time-Series dataset) are tracked via Git LFS, gzip-compressed except the
`.rds`. The WVS Trend File, EVS Trend File, PLAD, and Archigos also ship
with the package. Git LFS must be installed once per machine
(`git lfs install`) before cloning; `git clone` then pulls all LFS files
automatically.

`setup_environment.R` decompresses whichever shipped files the requested
`--stage` needs before running any stage (`ensure_shipped_inputs()` in
`02_scripts/01_setup/check_raw_data.R`), so every consuming script reads
each file in its plain, uncompressed form regardless of how it is
tracked.

### Excluded: third-party raw geometry and rasters

`gadm_3.6/`, `dmsp_raster_eog_manual/`, `viirs_raster_eog_manual/`, and
`harmonized_dmsp_viirs_li2020/` are excluded from version control
(multi-GB to hundreds of GB, and some sources restrict redistribution).
DMSP and VIIRS download automatically via Stages 03-04; GADM 3.6 and the
harmonized DMSP/VIIRS rasters require a manual download (see below).

### Raw data that cannot be downloaded automatically

Every `setup_environment.R` run checks required files against the
requested `--stage` before running anything, and reports any missing
file with its download link, registration requirement, and destination
path, rather than failing later with an opaque error.

| Dataset                                | Link                                                                                                                | Registration                                                                       | Used by                                            | Destination                                                 |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | -------------------------------------------------- | ----------------------------------------------------------- |
| GADM 3.6 (levels 0-2)                  | [https://geodata.ucdavis.edu/gadm/gadm3.6/](https://geodata.ucdavis.edu/gadm/gadm3.6/)                               | Free                                                                               | Hole-punched geometry, Table IV Cols 2-3, Figure 2 | `01_datasets/raw/gadm_3.6/gadm36_levels.gpkg`             |
| G-Econ 4.0 (Nordhaus et al.)           | [https://gecon.yale.edu](https://gecon.yale.edu)                                                                     | Free                                                                               | Gridded regional GDP, Table II Column 8            | `01_datasets/raw/gecon/`                                  |
| GPWv3 population count, 1990/1995      | [https://sedac.ciesin.columbia.edu/data/collection/gpw-v3](https://sedac.ciesin.columbia.edu/data/collection/gpw-v3) | Free, NASA Earthdata login                                                         | Population covariates                              | `01_datasets/raw/GPWv3_pcount/`                           |
| GPWv4 population count, 2000/2005/2010 | [https://sedac.ciesin.columbia.edu/data/collection/gpw-v4](https://sedac.ciesin.columbia.edu/data/collection/gpw-v4) | Free, NASA Earthdata login                                                         | Population covariates                              | `01_datasets/raw/gpw/population/pop/`                     |
| GHS-POP (Global Human Settlement)      | Google Earth Engine catalog                                                                                         | Free, Google account +[Earth Engine signup](https://earthengine.google.com/signup/) | Population interpolation                           | Accessed live via GEE; run`earthengine authenticate` once |
| Li et al. (2020) harmonized DMSP/VIIRS NTL | [figshare, article 9828827](https://figshare.com/articles/dataset/Harmonization_of_DMSP_and_VIIRS_nighttime_light_data_from_1992-2018_at_the_global_scale/9828827) | Free | Harmonized 1992-2024 NTL extension panel (Stage 16) | `01_datasets/raw/harmonized_dmsp_viirs_li2020/`, one GeoTIFF per year (see naming below) |

GADM 4.1, DMSP, and VIIRS download automatically (Stages 01-04) and need
no manual step.

**Li et al. (2020) file naming.** The figshare item ships one GeoTIFF per
year, already named `Harmonized_DN_NTL_<year>_<suffix>.tif`
(`<suffix>` is `calDMSP` for 1992-2013, `simVIIRS` for 2014 onward) --
download the years 1992-2024 and place them, unrenamed, directly under
`01_datasets/raw/harmonized_dmsp_viirs_li2020/`, e.g.:

```
01_datasets/raw/harmonized_dmsp_viirs_li2020/
├── Harmonized_DN_NTL_1992_calDMSP.tif
├── Harmonized_DN_NTL_1993_calDMSP.tif
├── ...
├── Harmonized_DN_NTL_2013_calDMSP.tif
├── Harmonized_DN_NTL_2014_simVIIRS.tif
├── ...
└── Harmonized_DN_NTL_2024_simVIIRS.tif
```

Stage 16 (`02_data_preprocessing/16_harmonized_dmsp_viirs_adm2.R`) checks
for the first expected file before running and reports the exact missing
path if the folder isn't populated yet.

---

## System Requirements

- **R (>= 4.3)**: [https://cran.r-project.org/](https://cran.r-project.org/)
- **Git LFS**: [https://git-lfs.com/](https://git-lfs.com/), then `git lfs install` once per machine
- **Quarto CLI**: [https://quarto.org/get-started/](https://quarto.org/get-started/)
- **TinyTeX**: installed automatically by `setup_environment.R` if missing
- **A Chrome, Chromium, or Edge binary**: for rasterizing Figures 1 and 2; auto-detected, or set `REGIONAL_FAVORITISM_CHROME_BIN`
- **Python 3 + `earthengine-api`** (via `reticulate`), with an authenticated Earth Engine account, needed only for `02_data_preprocessing/19_ghs_pop_gee.R`
- **System libraries** for `sf`/`terra`:
  - macOS: `brew install gdal geos proj`
  - Linux: `sudo apt-get install libgdal-dev libgeos-dev libproj-dev`

---

## Key Dependencies

Version-pinned in `renv.lock`, installed via `make init`.

- `fixest`: fixed-effects estimation for every regression table
- `data.table`: panel construction and zonal-statistics output
- `sf` / `terra` / `exactextractr`: boundary geometry and raster zonal statistics
- `here`: package-relative file paths
- `gt`: styled HTML export for Tables 1, 2, 4, and the extension table

`make init` installs the versions pinned in `renv.lock` into the active R
library rather than an isolated renv environment, so scripts run against
whatever R installation is already active.

---

**Author:** Ömer Furkan Çoban
**Course:** Applied Econometrics Using GIS Techniques, Uni Oldenburg (SoSe 2026)
**Lecturer:** Prof. Dr. Erkan Gören
