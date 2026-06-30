# Regional Favoritism Replication and Extension: ROADMAP

**Course:** Applied Econometrics using GIS Techniques
**Author:** Furkan
**Status:** Planning phase, Week 0
**Last updated:** 30 June 2026

---

## 0. One paragraph summary

This project is a replication and extension of Hodler and Raschky 2014 (henceforth HR), the foundational paper on regional favoritism in the Quarterly Journal of Economics. The replication uses an open-source pipeline built on PLAD leader birthplaces and GADM 4.1 administrative boundaries, incorporating methodological updates from Düben, Hodler and Raschky 2026 (henceforth DHR) and Bora 2025. Four original extensions are added on top of the replication: a Turkey case study at the province (ADM1) level using monthly VIIRS Black Marble data, a spatial spillovers analysis using Spatial Durbin Model on the Turkey panel, a crisis premium analysis around three major Turkish earthquakes (1999 Marmara, 2011 Van, 2023 Kahramanmaraş) combining NTL with EM-DAT disaster data, and OpenStreetMap validation of physical infrastructure changes where temporal coverage permits. A robustness check across three institutional quality measures (Polity5, V-Dem Liberal Democracy, WGI Government Effectiveness) runs throughout.

The paper validates HR's main finding (leader birthplaces are brighter during tenure), confirms that the pattern survives modern NTL data and extended sample (per DHR), shows that it holds in a specific national context with rich within-country variation (Turkey 1992 to 2024), demonstrates that favoritism effects spill over to neighboring provinces, documents whether crisis contexts amplify favoritism (extending HR's disaster analysis and Bora's COVID analysis to a Turkish earthquake setting), and cross-validates the NTL-based results with physical infrastructure data from OSM where feasible.

---

## 1. Three-layer architecture

### Layer 1: Global Replication of HR 2014 with Modern Updates (External Validity)

**Length:** 3 to 4 pages
**Purpose:** Replicate HR 2014's main result using the open-source pipeline, incorporate DHR's data extensions and Bora's methodological refinements as updates
**Deliverables:**
- Replication of HR 2014 Table II Column 1 (baseline result, 126 countries, 1992-2009)
- Extension following DHR: extend sample to 1992-2023, expand country coverage to 147+ countries
- Compare against multiple NTL datasets per DHR Table 2 (DMSP-OLS, VIIRS, ideally Chiovelli et al. 2026)
- Replicate HR Table V heterogeneity (Polity, schooling, etc.) and DHR Table 3 V-Dem extension
- Add Panel E: WGI Government Effectiveness interaction (original contribution, not in HR or DHR)
- Comparison table: my coefficients vs HR 2014 vs DHR 2026 vs Bora 2025

**Specification (HR 2014 Equation 1):**
```
ln(Light_ict) = alpha_i + beta_ct + gamma * Leader_ict-1 + epsilon_ict
```
Region fixed effects, country-year fixed effects, standard errors clustered at the country level (following DHR's more conservative choice than HR's leader-period clustering).

### Layer 2: Turkey Case Study (Main Contribution)

**Length:** 5 to 6 pages
**Purpose:** Apply the HR 2014 framework with modern monthly VIIRS data to a single country with rich leader variation, going beyond what HR, DHR, or Bora did
**Deliverables:**
- Province-month panel for Turkey, 81 provinces times around 280 months (1992 to 2024)
- Event study around each leader transition (8 transitions in the sample)
- Calendar-time profile of leader premium (similar to Bora Figure 2 but for a single country)
- Comparison: yearly DMSP-OLS panel (as in HR) vs monthly VIIRS panel (modern data)

**Specification (annual):**
```
ln(Light_it) = alpha_i + beta_t + gamma * Leader_it-1 + epsilon_it
```
where i is province (1 to 81), t is year. Province fixed effects, year fixed effects, standard errors clustered at the province level.

**Specification (monthly with VIIRS):**
```
ln(Light_im) = alpha_i + beta_m + gamma * Leader_im + epsilon_im
```
where m is month. Province fixed effects, year-month fixed effects.

### Layer 3: Spatial Spillovers (Methodological Extension)

**Length:** 2 to 3 pages
**Purpose:** Test whether the leader birthplace premium spills over to neighboring provinces. Neither HR, DHR, nor Bora apply spatial econometrics; HR Table IV uses alternative spatial units but not formal spatial models.
**Deliverables:**
- Contiguity-based spatial weights matrix W for Turkey provinces, row-standardized
- Moran's I test for residual spatial autocorrelation in baseline OLS
- LM tests to choose between Spatial Lag Model (SAR), Spatial Error Model (SEM), Spatial Durbin Model (SDM)
- Estimation of preferred spatial model with leader dummies
- Direct, indirect, and total impact decomposition (LeSage and Pace 2009)

**SDM specification:**
```
ln(Light_it) = alpha_i + beta_t + rho * W * ln(Light_it) + gamma * Leader_it + theta * W * Leader_it + epsilon_it
```
where rho captures spatial dependence in outcomes, theta captures spillover from leader status of neighbors.

### Layer 4: Crisis Premium and Physical Infrastructure Validation (Original Contribution)

**Length:** 3 to 4 pages
**Purpose:** Test whether crisis contexts amplify regional favoritism in Turkey, extending HR's natural disaster analysis (Supplementary Material Table S.10) and Bora's COVID premium framework to three major Turkish earthquakes. Where data permits, cross-validate NTL findings with OSM physical infrastructure changes.

**Three earthquake events:**

| Event | Date | Affected provinces | Death toll | Sample period coverage |
|-------|------|---------------------|------------|------------------------|
| Marmara | 17 August 1999 | Kocaeli, Sakarya, Yalova, Istanbul, Bolu | ~17,000 | Yes (within 1992-2024) |
| Van | 23 October 2011 | Van, Bitlis | ~600 | Yes |
| Kahramanmaraş | 6 February 2023 | Kahramanmaraş, Hatay, Adıyaman, Gaziantep, Şanlıurfa, Diyarbakır, Malatya, Osmaniye, Adana, Kilis | ~50,000 | Yes |

**Specification 4a: Earthquake premium (NTL-based, all three events):**
```
ln(Light_it) = alpha_i + beta_t + gamma_0 * Leader_it + gamma_1 * (Leader_it × Affected_it × PostQuake_it) + delta * (Affected_it × PostQuake_it) + epsilon_it
```
where Affected_it = 1 for provinces in the disaster zone, PostQuake_it = 1 for 24 months after the event, and the triple interaction captures whether leader birthplaces in the affected zone (or nearby) receive disproportionate reconstruction.

**Specification 4b: OSM physical infrastructure (2023 Kahramanmaraş only, if feasible):**
- Extract pre-quake (early Feb 2023) and post-quake snapshots (late 2024) for hospitals, schools, roads
- Compute count and density of new infrastructure per affected province
- Compare leader-affiliated province (Erdoğan's effective base) to other affected provinces
- This is a "stretch goal" depending on OSM History API tractability

**Data requirements:**
- EM-DAT: Centre for Research on the Epidemiology of Disasters, free academic access
- OSM Historical: OSM Planet history file or Ohsome API by HeiGIT
- NTL: same Layer 2 panel

**Critical scope note for OSM:** Turkey OSM coverage is sparse pre-2012, partial 2012-2015, robust 2016 onwards. This means OSM validation is feasible only for the 2023 Kahramanmaraş event. For 1999 Marmara and 2011 Van, we rely on NTL only. This asymmetry is acknowledged in the paper as a limitation.

---

## 2. Three institutional quality measures

Each measure is used in Layer 1 as an interaction term. Layer 2 (Turkey) also uses time-varying versions where data permits.

| Measure | Source | Conceptual focus | Use in Layer 1 | Use in Layer 2 |
|---------|--------|------------------|----------------|----------------|
| Polity5 (polity2 index) | Center for Systemic Peace | Democratic vs autocratic regime type | Interaction in country-year panel | Turkey polity2 over time, 1992 to 2018 |
| V-Dem Liberal Democracy Index | V-Dem Project v13 | Liberal democracy (incl. judicial constraints) | Interaction in country-year panel | Sub-indices: judicial constraints, electoral component |
| WGI Government Effectiveness | World Bank | Bureaucratic capacity, perception based | Interaction in country-year panel (original contribution) | Turkey WGI GE.EST over time, 1996 to 2023 |

**Original contribution:** HR 2014 uses Polity2. DHR 2026 uses both Polity5 and V-Dem Liberal Democracy. WGI Government Effectiveness is in neither HR, DHR, nor Bora. Adding it tests whether bureaucratic capacity (not just democratic regime type) constrains favoritism, engaging with the perception-based vs structural distinction.

---

## 3. Fourteen week timeline

Total: 14 weeks. Each week has a primary deliverable and an exit criterion.

### Phase A: Foundation (weeks 1 to 3)

**Week 1: Pipeline setup and data inventory**
- Reuse SDG 11.3.1 reticulate-Python earthengine-api pipeline
- Download GADM 4.1 ADM2 shapefile (global) and ADM1 shapefile (Turkey)
- Download PLAD from Bomprezzi et al. 2025 (whatever public version exists)
- Set up Harvard Dataverse DHR replication package (download manually, extract structure)
- Exit: pipeline runs end-to-end on one test country (Turkey)

**Week 2: Leader birthplace harmonization**
- Manual harmonization of PLAD ADM2 codes against GADM 4.1 (following Bora's approach)
- Build Turkey-specific leader table with birth provinces verified from biographical sources
- Cross-check: PLAD entry for Erdogan should be Rize province (ADM1) and Guneysu district (ADM2)
- Exit: TURKEY_LEADERS.csv complete, validated against three independent sources per leader

**Week 3: Global panel construction**
- DMSP-OLS yearly composites 1992 to 2013, zonal statistics on ADM2 polygons
- VIIRS Black Marble yearly 2012 to 2024, zonal statistics on ADM2 polygons
- DHR replication package download and structure documentation
- Exit: global panel with 45000+ regions, 33 years, NTL columns for at least DMSP-OLS and VIIRS

### Phase B: Layer 1 (weeks 4 to 5)

**Week 4: Global replication estimation**
- HR 2014 Equation 1 baseline estimation (primary target)
- Replicate HR Table II Column 1: 1992-2009 sample, 126 countries
- Then extend to DHR's 1992-2023 sample, 147 countries
- Compare against multiple NTL datasets (DMSP-OLS, VIIRS, ideally Chiovelli)
- Comparison table: my coefficients vs HR 2014, DHR 2026, Bora 2025
- Exit: HR baseline coefficient within 15% of original, extended sample shows DHR-consistent pattern

**Week 5: Heterogeneity analysis**
- Polity, V-Dem, WGI interactions
- Replicate HR Table V (Polity interaction) and extend per DHR Table 3
- Add WGI Government Effectiveness as original contribution
- Write Layer 1 results section
- Exit: Layer 1 complete (3 to 4 pages, with tables)

### Phase C: Layer 2 (weeks 6 to 8)

**Week 6: Turkey panel construction**
- 81 provinces times 33 years (DMSP-OLS), or times 12 months times 13 years (VIIRS)
- Province leader dummies based on TURKEY_LEADERS.csv
- Validate Erdogan-Rize pattern visually (NTL choropleth, 2002 vs 2014)
- Exit: Turkey panel ready, descriptive statistics produced

**Week 7: Turkey baseline analysis**
- Annual DMSP-OLS specification
- Monthly VIIRS specification
- Event study around each leader transition
- Calendar-time profile (Bora Figure 2 style)
- Exit: Turkey baseline coefficients estimated, event study figures produced

**Week 8: Turkey extensions**
- Heterogeneity in Turkey: Polity5 time-varying interaction
- V-Dem sub-indices for Turkey (focus on judicial constraints)
- WGI GE.EST for Turkey 1996 onwards
- Write Layer 2 results section
- Exit: Layer 2 complete (5 to 6 pages, with tables and figures)

### Phase D: Layer 3 (weeks 9 to 10)

**Week 9: Spatial econometrics setup**
- Contiguity-based W matrix for Turkey ADM1
- Moran's I test on baseline OLS residuals
- LM tests for model selection
- Exit: model selection done, preferred specification chosen

**Week 10: Spatial model estimation**
- Estimate SDM (or whichever model LM tests favor)
- Direct, indirect, total impact decomposition
- Robustness: distance-based W, k-nearest neighbors W
- Write Layer 3 results section
- Exit: Layer 3 complete (2 to 3 pages, with tables)

### Phase E: Layer 4 (weeks 11 to 12)

**Week 11: Earthquake panel and NTL crisis premium**
- Download EM-DAT data for Turkey, 1992-2024
- Define Affected_it dummy for each of 1999 Marmara, 2011 Van, 2023 Kahramanmaraş
- Stack three earthquake events into event-study panel
- Estimate Specification 4a (triple interaction Leader × Affected × PostQuake)
- Robustness: 12-month, 24-month, 36-month post-quake windows
- Heterogeneity by leader birthplace location (in affected zone vs outside)
- Exit: Layer 4a (NTL crisis premium) complete

**Week 12: OSM physical infrastructure validation**
- Feasibility check: query Ohsome API for hospitals/schools/roads in Kahramanmaraş region as of Feb 2023
- If 2023 data is rich enough:
  - Extract pre-quake (Feb 2023) snapshot
  - Extract post-quake snapshot (most recent available)
  - Count new hospitals, schools, road segments per province
  - Compare leader-affiliated provinces (in our case: provinces with effective leader birth ties) vs others
- If 2023 OSM data is sparse:
  - Document the limitation
  - Drop OSM validation, report Layer 4 as NTL-only
- Write Layer 4 results section
- Exit: Layer 4 complete (3 to 4 pages with NTL findings, OSM if feasible)

### Phase F: Writing and revision (weeks 13 to 14)

**Week 13: First full draft**
- Introduction, literature review, data, methodology, results, discussion, conclusion
- All tables and figures finalized
- Bibliography in APA format
- Exit: first complete draft

**Week 14: Revision and submission prep**
- Internal review and refinement
- Code reproducibility check
- Replication archive structure
- Exit: final submission

---

## 4. Page budget

**No hard page limit per user preference.** Target range is 18 to 22 pages including references.

| Section | Pages |
|---------|-------|
| Introduction | 1.5 to 2 |
| Literature and theoretical framework | 1.5 to 2 |
| Data | 2 |
| Empirical strategy | 2 |
| Layer 1: Global replication | 2 |
| Layer 2: Turkey case study | 4 to 5 |
| Layer 3: Spatial spillovers | 2 to 3 |
| Layer 4: Crisis premium and OSM validation | 3 to 4 |
| Discussion and conclusion | 1.5 |
| References | 2 |
| Total | 21 to 25 |

Appendix with additional tables and robustness checks can extend beyond this. Targets are not hard caps; if Layer 2 needs more space for the Erdoğan-Rize narrative, it gets more space.

---

## 5. Code structure

```
regional_favoritism/
├── ROADMAP.md
├── CONTEXT.md
├── DATA_SOURCES.md
├── TURKEY_LEADERS.md
├── WEEK1_TASKS.md
├── data/
│   ├── raw/
│   │   ├── gadm_4.1/
│   │   ├── plad/
│   │   ├── dhr_replication/
│   │   ├── dmsp_ols/
│   │   ├── viirs/
│   │   ├── polity5/
│   │   ├── vdem/
│   │   ├── wgi/
│   │   ├── emdat/
│   │   └── osm/
│   ├── processed/
│   │   ├── global_panel_annual.parquet
│   │   ├── turkey_panel_annual.parquet
│   │   ├── turkey_panel_monthly.parquet
│   │   ├── earthquake_events.parquet
│   │   └── osm_kahramanmaras_2023.parquet
├── R/
│   ├── 01_data_download.R
│   ├── 02_zonal_stats_global.R
│   ├── 03_zonal_stats_turkey.R
│   ├── 04_panel_construction.R
│   ├── 05_layer1_global_replication.R
│   ├── 06_layer2_turkey_analysis.R
│   ├── 07_layer3_spatial_spillovers.R
│   ├── 08_layer4_earthquakes_ntl.R
│   ├── 09_layer4_osm_validation.R
│   ├── 10_tables_and_figures.R
│   └── utils/
│       ├── gee_helpers.R
│       ├── spatial_helpers.R
│       ├── emdat_helpers.R
│       └── osm_helpers.R
├── output/
│   ├── tables/
│   └── figures/
└── paper/
    ├── main.tex
    └── references.bib
```

---

## 6. Software and language choices

**Primary language:** R (for spatial econometrics, plm, fixest, spdep, spatialreg)
**Secondary language:** Python via reticulate (for Google Earth Engine API)
**Reasoning:** Bora uses an unspecified mix, DHR replication package likely uses Stata. Course context (Applied Econometrics + GIS) makes R the natural choice. R has the best spatial econometrics ecosystem (spatialreg, spdep, sf, terra). All code in English, all comments in English.

Key packages:
- fixest: high-performance fixed effects regression (much faster than plm for large panels)
- spatialreg, spdep: spatial econometrics
- sf, terra: geospatial data handling
- reticulate: GEE Python API wrapper
- modelsummary: regression tables
- ggplot2: figures

---

## 7. What is NOT in scope

To prevent scope creep, the following are explicitly out of scope:

- Daily VIIRS analysis (VNP46A2) — only monthly and annual composites
- Ethnic favoritism extension (De Luca et al. 2018) — only birthplace favoritism
- Spouse birthplace effects (Bomprezzi et al. 2025) — only effective leader
- COVID premium global analysis — Bora already did this, mention but do not extend
- Other countries beyond Turkey — global panel is descriptive, Turkey is the deep case
- Causal mechanisms (transfers, public goods, etc.) — observational evidence only
- Synthetic control or matching methods — fixed effects panel only
- Continuous treatment definitions — binary Leader_it only
- Pre-1992 historical analysis — NTL data starts in 1992
- Post-2024 analysis — sample ends with available VIIRS yearly composite
- Cabinet ministers and opposition leaders — only effective leader (Asatryan et al. 2023 already covers cabinet ministers globally)
- Earthquakes outside Turkey — Layer 4 is Turkey-only
- OSM historical analysis for pre-2020 events — coverage is insufficient
- Building damage assessments from earthquake — only new construction visible in OSM (and only for 2023 event)

---

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| GADM 4.1 ADM1 for Turkey misaligns with leader birth provinces | Medium | High | Cross-validate against PLAD entries; manual harmonization |
| VIIRS zonal statistics computation too slow | Medium | Medium | Aggregate to monthly first, parallelize by year |
| DHR replication package is Stata-only, hard to convert | High | Medium | Build from DHR paper's specification text, not their code |
| Spatial weights matrix singular due to disconnected islands | Low | Medium | Turkey has no islands as separate provinces; not relevant |
| Polity5 ends in 2018, V-Dem ends in 2023, WGI ends in 2023 | High | Low | Document sample restrictions per measure clearly |
| Turkey leader birth places ambiguous (Erdogan's case is debated) | Medium | Medium | Use PLAD's coding consistently; flag in appendix |
| Spatial Durbin model interpretation complex | Medium | Low | Follow LeSage and Pace 2009 chapter 2 step by step |
| Course deadline conflicts with other coursework | High | Medium | Build buffer into weeks 13 and 14, start drafting early |
| OSM historical data sparse for 1999 and 2011 earthquakes | Certain | Low | Pre-committed to OSM only for 2023 Kahramanmaraş |
| OSM 2023 Kahramanmaraş data also insufficient | Medium | Medium | Drop Layer 4b OSM validation, report Layer 4 as NTL-only |
| Ohsome API rate limits or downtime | Medium | Low | Cache pulled snapshots; alternative: OSM Planet PBF download |
| EM-DAT geocoding mismatches with GADM 4.1 ADM1 codes | Medium | Medium | Manual cross-reference for affected provinces per quake |
| NTL post-quake reading confounded by destruction (not just reconstruction) | High | High | Explicitly model both phases; report 0-6 months (destruction) and 12-24 months (reconstruction) separately |

---

## 9. References

Core references that must be cited:

- Hodler, R. and Raschky, P. A. (2014). Regional favoritism. Quarterly Journal of Economics, 129(2), 995 to 1033.
- Düben, C., Hodler, R. and Raschky, P. A. (2026). Regional favoritism: New data, larger sample, same pattern. CEPR Discussion Paper 21239.
- Bora, R. (2025). Birthplace favoritism revisited: Replication, modern evidence, and crisis dynamics. UQ School of Economics Discussion Paper 671.
- Bomprezzi, P. et al. (2025). Wedded to prosperity? Informal influence and regional favoritism. CESifo Working Paper 10969.
- Chiovelli, G. et al. (2026). Illuminating the Global South. Economic Journal, forthcoming.
- Henderson, V. J., Storeygard, A. and Weil, D. (2012). Measuring economic growth from outer space. American Economic Review, 102(2), 994 to 1028.
- LeSage, J. and Pace, R. K. (2009). Introduction to Spatial Econometrics. CRC Press.

Layer 4 (crisis premium and OSM) references:

- Bommer, C., Dreher, A., and Perez-Alvarez, M. (2022). Home bias in humanitarian aid: The role of regional favoritism in the allocation of international disaster relief. Journal of Public Economics, 208, 104604.
- Morales-Arilla, J. (2024). Sub-Saharan African leader birth regions emit more night lights during drought conditions. (Working paper, citation in Bora 2025).
- Schneider, T. and Kunze, S. (2023). The political economy of disaster relief: Ambiguity as a chance for partisan allocations. (Working paper, citation in Bora 2025).
- Centre for Research on the Epidemiology of Disasters (CRED). EM-DAT: The International Disaster Database. https://www.emdat.be
- OpenStreetMap contributors. (2024). Planet dump. https://planet.openstreetmap.org
- Raifer, M. et al. (2019). OSHDB: A framework for spatio-temporal analysis of OpenStreetMap history data. Open Geospatial Data, Software and Standards, 4(1), 3.

Additional references for Turkey context, Polity5, V-Dem, WGI, and spatial econometrics will be added in CONTEXT.md and the bibliography file.
