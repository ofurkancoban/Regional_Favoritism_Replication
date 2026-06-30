# Data Sources: Where, What, How

**Project:** Regional Favoritism Replication and Extension
**Last updated:** 30 June 2026

This document is the authoritative reference for every dataset used in the project. Each entry contains: source URL, format, size, temporal coverage, spatial coverage, preprocessing required, and the role it plays in the analysis.

---

## 1. Administrative boundaries

### GADM 4.1
- **URL:** https://gadm.org/data.html
- **Format:** Shapefile and GeoPackage (gpkg)
- **Size:** Global ADM2 around 1.5 GB
- **Temporal coverage:** Single snapshot (current boundaries)
- **Spatial coverage:** Global, 290 countries and territories
- **Use:** Layer 1 (global ADM2), Layer 2 (Turkey ADM1)
- **Preprocessing:** Filter to ADM2 globally for Layer 1, filter to TUR ADM1 for Layer 2. For countries without ADM2 in GADM, upcast ADM1 to serve as ADM2 (following Bora 2025 Section 3.3).
- **Notes:** Turkey has 81 provinces at ADM1 level. Verify Bartin (created 1991), Karabuk (1995), Yalova (1995), Kilis (1995), Osmaniye (1996), Duzce (1999) are all present. These are post-1990 provincial reorganizations that affect contiguity matrix.

---

## 2. Leader birthplaces

### PLAD (Political Leaders' Affiliation Database)
- **Source:** Bomprezzi et al. 2025, CESifo Working Paper 10969 (v.2)
- **URL:** Check authors' personal pages for public version, or contact authors. Some versions on Harvard Dataverse.
- **Format:** CSV or Stata dta
- **Temporal coverage:** 1989 to 2023 (Bora extended to March 2025 manually)
- **Spatial coverage:** Global, 177 countries
- **Use:** Layer 1 (global Leader_ict variable), Layer 2 (Turkey leader history)
- **Preprocessing:**
  - Filter to effective leaders only (matching Archigos definition)
  - Geocode birthplaces to ADM2 level matching GADM 4.1
  - For Turkey, manual cross-validation against three independent biographical sources per leader
  - Define Leader_ict = 1 if region i is birthplace of country c's leader in period t, 0 otherwise
- **Notes:** If exact ADM2 match fails (different boundary versions), fall back to nearest centroid match. Document all manual decisions in TURKEY_LEADERS.md.

---

## 3. Nighttime lights

### DMSP-OLS Stable Lights (1992 to 2013)
- **Source:** Earth Observation Group, Payne Institute, Colorado School of Mines
- **URL:** https://eogdata.mines.edu/products/dmsp/
- **Format:** GeoTIFF raster, 30 arc-second resolution
- **Size:** Each annual composite around 700 MB compressed, around 3 GB uncompressed
- **Temporal coverage:** 1992 to 2013 (22 years)
- **Spatial coverage:** Global
- **Use:** Layer 1 historical period, comparison bridge between sensors
- **Preprocessing:**
  - Use newest satellite per year (F10, F12, F14, F15, F16, F18) when overlap exists
  - Zonal statistics: mean DN value per ADM2 polygon
  - Outcome variable: log(mean_DN + 0.01) following HR 2014
- **Alternative:** Google Earth Engine collection `NOAA/DMSP-OLS/NIGHTTIME_LIGHTS` is the easiest way

### VIIRS Black Marble (2012 to present)
- **Source:** NASA LAADS DAAC
- **URL:** https://blackmarble.gsfc.nasa.gov/ or LAADS data archive
- **Format:** HDF5 tiles, 15 arc-second resolution
- **Size:** Monthly composites around 80 GB for full archive
- **Temporal coverage:** January 2012 to present
- **Spatial coverage:** Global, delivered in 10x10 degree tiles
- **Use:** Layer 1 modern period, Layer 2 monthly Turkey panel, Layer 3
- **Preprocessing:**
  - Use VNP46A3 (monthly composites) and VNP46A4 (annual composites)
  - Select near-nadir sublayer (sublayer 15) following Bora 2025
  - Filter snow-free observations (mandatory in Bora's approach)
  - Stitch tiles for each month, zonal statistics on ADM polygons
  - Outcome variable: log(mean_radiance + 0.01)
- **Alternative:** GEE collection `NOAA/VIIRS/DNB/MONTHLY_V1` (note: less comprehensive than Black Marble, lacks viewing angle stratification)
- **Critical note:** Black Marble via direct download requires LAADS account (free). GEE is faster but does not include all Black Marble layers.

### Chiovelli et al. 2026 harmonized dataset
- **Source:** Chiovelli, Michalopoulos, Papaioannou, Regan, "Illuminating the Global South", Economic Journal forthcoming
- **URL:** Check authors' replication package on Harvard Dataverse or similar
- **Format:** Likely processed panel CSV at ADM2 level
- **Use:** Layer 1 robustness across NTL datasets (DHR's preferred dataset)
- **Notes:** DHR found this gives the largest coefficient (0.054 vs 0.044 for raw DMSP-OLS). Including this in Layer 1 robustness is important.

### Li et al. 2020 and Nechaev et al. 2021 harmonized datasets
- **URLs:**
  - Li et al.: Figshare or similar, search for "harmonized global nighttime light dataset 1992 2018"
  - Nechaev et al.: Mendeley Data
- **Use:** Layer 1 robustness, secondary datasets in DHR Table 2
- **Notes:** Optional. Including all 5 NTL datasets DHR uses is the gold standard but not strictly necessary if at least DMSP-OLS, VIIRS, and Chiovelli are covered.

---

## 4. Population

### GPWv4 Revision 11 (Gridded Population of the World)
- **Source:** CIESIN, Columbia University
- **URL:** https://sedac.ciesin.columbia.edu/data/collection/gpw-v4
- **Format:** GeoTIFF raster, 30 arc-second resolution
- **Temporal coverage:** Available for 2000, 2005, 2010, 2015, 2020 (5-year intervals)
- **Use:** Population control in regression (DHR Panel C), density deciles for Bora-style fixed effects
- **Preprocessing:** Zonal statistics on ADM polygons, linear interpolation between 5-year intervals
- **Notes:** Bora uses 2015 UN-WPP adjusted population count specifically. We follow same for consistency.

### GHS-POP R2023A (alternative)
- **Source:** EU JRC
- **URL:** https://human-settlement.emergency.copernicus.eu/ghs_pop.php
- **Use:** Optional alternative population source for robustness
- **Notes:** Available at finer temporal granularity (5-year intervals 1975 to 2030). User has prior experience with this from SDG 11.3.1 project.

---

## 5. Institutional quality

### Polity5
- **Source:** Center for Systemic Peace, Marshall and Gurr 2020
- **URL:** http://www.systemicpeace.org/inscrdata.html
- **Format:** Excel xls, also available in QoG Standard Dataset
- **Temporal coverage:** 1800 to 2018
- **Variable used:** polity2 (range -10 to +10, computed as democ minus autoc)
- **Use:** Layer 1 interaction (DHR Panel B), Layer 2 Turkey time-varying
- **Notes:** Ends in 2018. Bora uses 2018 polity2 score specifically for high-vs-low democracy split.

### V-Dem v13
- **Source:** V-Dem Project
- **URL:** https://www.v-dem.net/data/the-v-dem-dataset/
- **Format:** CSV or Stata
- **Temporal coverage:** 1789 to present, updated annually
- **Variables used:**
  - v2x_libdem (Liberal Democracy Index, 0 to 1) for Layer 1
  - v2x_jucon (Judicial constraints on executive) for Turkey sub-index
  - v2xel_frefair (Free and fair elections) for Turkey sub-index
- **Use:** Layer 1 interaction (DHR Panel C), Layer 2 Turkey sub-index analysis
- **Notes:** Most comprehensive coverage. Use v13 release (matches DHR). Registration required but free.

### WGI Government Effectiveness
- **Source:** World Bank Worldwide Governance Indicators
- **URL:** https://info.worldbank.org/governance/wgi/
- **Format:** Excel or CSV
- **Temporal coverage:** 1996 to 2023 (annual since 2002, biennial 1996-2002)
- **Variable used:** ge.est (Government Effectiveness Estimate, around -2.5 to +2.5)
- **Use:** Layer 1 interaction (original contribution, Panel E), Layer 2 Turkey time-varying
- **Notes:** Perception-based composite. Critical to address in writing: limitations include perception bias, mid-2000s methodology change, post-2017 statistical break. Document these in CONTEXT.md.

### QoG Standard Dataset Jan26
- **Source:** Quality of Government Institute, University of Gothenburg
- **URL:** https://www.gu.se/en/quality-government/qog-data/data-downloads
- **Use:** Single source for ethnic fractionalization, Polity5, V-Dem, WGI, GDP per capita, schooling
- **Notes:** Convenient bundling. DHR explicitly says they take all controls from QoG. Match version Jan26 for compatibility.

---

## 6. Economic controls

### World Development Indicators (WDI)
- **Source:** World Bank
- **URL:** https://databank.worldbank.org/source/world-development-indicators or `wbstats` R package
- **Variables:**
  - NY.GDP.PCAP.PP.KD: GDP per capita PPP, constant 2021 international dollars
- **Use:** Layer 1 interaction (DHR Panel E), Layer 2 Turkey time series
- **Notes:** Accessed via QoG Standard Dataset for DHR comparability.

### Barro-Lee schooling
- **Source:** Barro and Lee 2013
- **URL:** http://www.barrolee.com/
- **Variable:** yr_sch (average years of schooling, population 15+)
- **Temporal coverage:** 1950 to 2015 (5-year intervals), DHR extrapolates to 2023
- **Use:** Layer 1 interaction (DHR Panel D)
- **Notes:** Linear interpolation between 5-year data points, extrapolation using 2010-2015 trend for post-2015 (matches DHR approach).

### Ethnic Fractionalization (Alesina et al. 2003)
- **Source:** Alesina, Devleeschauwer, Easterly, Kurlat, Wacziarg 2003
- **URL:** Available in QoG Standard Dataset, code: al_ethnic
- **Use:** Layer 1 interaction (DHR Panel A)
- **Notes:** Cross-sectional (time-invariant). Single value per country.

---

## 7. Layer 4 inputs: Disaster events and physical infrastructure

### EM-DAT (Centre for Research on the Epidemiology of Disasters)
- **Source:** Université catholique de Louvain, Brussels
- **URL:** https://www.emdat.be (free academic registration required)
- **Format:** Excel xlsx download after query
- **Temporal coverage:** 1900 to present, but reliable from 1980s
- **Spatial coverage:** Global, country level with subnational notes
- **Use:** Layer 4 earthquake event identification and affected province lists
- **Variables needed:**
  - Country: Turkey
  - Disaster type: Earthquake
  - Date, magnitude, deaths, affected count
  - Subnational location text (free-form, requires manual ADM1 mapping)
- **Three target events:**
  - 1999-08-17 Marmara: affected provinces Kocaeli, Sakarya, Yalova, Istanbul, Bolu, Düzce
  - 2011-10-23 Van: affected provinces Van, Bitlis
  - 2023-02-06 Kahramanmaraş (twin quakes 7.8 and 7.5): affected provinces Kahramanmaraş, Hatay, Adıyaman, Gaziantep, Şanlıurfa, Diyarbakır, Malatya, Osmaniye, Adana, Kilis
- **Preprocessing:** Manual cross-reference of EM-DAT free-text location field against GADM 4.1 ADM1 codes. Build `data/processed/earthquake_events.parquet` with columns: event_id, date, province_adm1, magnitude, deaths, affected_population.

### OpenStreetMap Historical Data
- **Source:** OpenStreetMap contributors, accessed via Ohsome API or Planet PBF
- **URLs:**
  - Ohsome API (recommended): https://api.ohsome.org (free, no auth, by HeiGIT)
  - OSM Planet PBF: https://planet.openstreetmap.org (heavy, around 80 GB)
- **Format:** GeoJSON via API or PBF binary
- **Temporal coverage:** 2007 to present (Turkey usable from 2016 onwards)
- **Spatial coverage:** Global, Turkey coverage variable
- **Use:** Layer 4b infrastructure validation, 2023 Kahramanmaraş only
- **Variables needed (OSM tags):**
  - amenity=hospital, amenity=clinic
  - amenity=school, amenity=university
  - highway=primary, highway=secondary (new road segments)
  - building=public, building=civic
- **Two snapshots needed:**
  - Pre-quake: 2023-01-31 (1 week before earthquake)
  - Post-quake: most recent available (2024 or 2025)
- **Outcome variable for Layer 4b:**
  - Count of new feature instances per province between snapshots
  - Optional: length of new road segments (in km)
- **Critical caveats:**
  - OSM coverage varies by region; Hatay has poorer coverage than Gaziantep
  - "New" in OSM means "newly mapped" not necessarily "newly constructed". Volunteer mappers may add existing buildings over time. Use OSM tag `start_date` if available, otherwise interpret carefully.
  - 2023 earthquake destroyed many existing OSM-tagged buildings. We need to distinguish "destroyed and removed from OSM" from "destroyed and not removed" from "rebuilt as new entry".
- **Decision rule:** If pre-quake OSM Hatay/Kahramanmaraş has fewer than 100 amenity=hospital + amenity=school entries combined, OSM is too sparse and Layer 4b drops out. Document and proceed with NTL-only.

### Alternative for OSM: HOT (Humanitarian OpenStreetMap Team) Tasking Manager data
- **URL:** https://tasks.hotosm.org
- **Notes:** After major disasters, HOT activates mapping campaigns. The 2023 Kahramanmaraş earthquake triggered intensive HOT mapping. This may provide higher-quality post-quake snapshots than baseline OSM. Worth investigating in Week 12.

---

## 8. Spatial econometrics inputs

### Contiguity-based spatial weights matrix W for Turkey

Constructed in R using:
```r
library(sf)
library(spdep)
turkey_adm1 <- st_read("data/raw/gadm_4.1/gadm41_TUR_1.shp")
W_neighbors <- poly2nb(turkey_adm1, queen = TRUE)
W_listw <- nb2listw(W_neighbors, style = "W")  # row-standardized
```

**Notes:**
- Queen contiguity: provinces sharing any border or vertex are neighbors
- Row-standardization makes rows sum to 1, standard practice
- No islands in Turkey provincial structure, so no zero-row issues
- Check: Istanbul-Kocaeli, Ankara-Konya, Erzurum-Kars should be neighbors

### Alternative W matrices for robustness

- Rook contiguity (shared border only, no vertex)
- K-nearest neighbors (k = 5)
- Inverse distance with cutoff at 250 km

---

## 9. Pipeline summary by layer

### Layer 1: Global replication
- GADM 4.1 ADM2 polygons (around 45000 globally)
- PLAD effective leader birthplaces
- DMSP-OLS yearly 1992 to 2013
- VIIRS yearly 2012 to 2024 (and ideally Chiovelli for top robustness)
- QoG Standard Dataset for Polity5, V-Dem, WGI, schooling, ethnic frac, GDP

### Layer 2: Turkey case study
- GADM 4.1 ADM1 polygons for Turkey (81 provinces)
- TURKEY_LEADERS.csv (manually validated)
- DMSP-OLS yearly 1992 to 2013 + VIIRS monthly 2012 to 2024
- WGI, V-Dem, Polity5 for Turkey time series
- WDI GDP per capita for Turkey

### Layer 3: Spatial spillovers
- Turkey ADM1 polygons (from Layer 2)
- Turkey annual or monthly NTL panel (from Layer 2)
- TURKEY_LEADERS.csv (from Layer 2)
- W matrix constructed in R

### Layer 4: Crisis premium and OSM
- Turkey panels from Layer 2
- EM-DAT earthquake events (1999, 2011, 2023)
- Manual affected-province coding per event
- OSM via Ohsome API for 2023 Kahramanmaraş only (conditional on feasibility)

---

## 10. Data acquisition checklist (Week 1 to 3)

- [ ] Download GADM 4.1 global ADM2 shapefile
- [ ] Download GADM 4.1 Turkey ADM1 shapefile separately
- [ ] Download PLAD from Bomprezzi et al. (search Dataverse, contact authors if private)
- [ ] Download DHR replication package from Harvard Dataverse RRIN3P
- [ ] Set up GEE authentication (reuse from SDG project: `ee-turkey-research`)
- [ ] Test DMSP-OLS GEE collection access for one year (1995)
- [ ] Test VIIRS GEE collection access for one month (June 2020)
- [ ] Download QoG Standard Dataset Jan26 (single zip)
- [ ] Register for EM-DAT academic access and download Turkey earthquakes
- [ ] Test Ohsome API with a small Turkey query (Week 12, not Week 1)
- [ ] Optional: download Chiovelli et al. processed panel if public
- [ ] Optional: download GPWv4 2015 raster for Bora-style density bins

---

## 11. Storage planning

Estimated total disk usage:
- Raw rasters (DMSP-OLS local copies): 60 GB
- Raw VIIRS Black Marble (if downloaded directly): 80 GB
- Processed panels: under 5 GB
- EM-DAT (xlsx): under 50 MB
- OSM snapshots for 2023 Kahramanmaraş region: under 2 GB
- Total worst case: around 150 GB

**Recommendation:** Use GEE for zonal statistics whenever possible. Only download raw rasters for verification or if GEE collection lacks required layers (e.g. Black Marble viewing angle stratification not in GEE).

If using GEE exclusively, local storage need drops to under 12 GB.
