# Project Context: Decisions and Reasoning

**Read this together with ROADMAP.md, DATA_SOURCES.md, and TURKEY_LEADERS.md.**

ROADMAP says what we are doing. CONTEXT says why we made the decisions we made, and lists gotchas to remember. This is a handoff document, intended for use when migrating the project to Claude Code or revisiting after a break.

---

## 1. Course context

- **Course:** Applied Econometrics using GIS Techniques
- **Student:** Furkan
- **Replication target:** Hodler and Raschky 2014 (HR), Quarterly Journal of Economics, 129(2), 995-1033
- **Methodological updates from:** Düben, Hodler, Raschky 2026 (DHR) and Bora 2025
- **Key references:** HR 2014 (replicated paper), DHR 2026 (modern data extensions), Bora 2025 (open-source pipeline guide)
- **Language preference:** All code and comments in English. Communication may be Turkish in conversation but deliverables are English.
- **Tool preference:** R as primary language. Python via reticulate for Google Earth Engine.
- **Format preferences:** No em-dashes. No Claude as co-author or contributor in repos.

## 1.5 Framing hierarchy (critical for writing and Claude Code prompts)

This project is formally a **replication of HR 2014**, not DHR 2026. The distinction matters for how the paper is written and presented.

**Why HR 2014 as primary target:**
- It is the seminal paper that introduced the leader-birthplace-as-NTL approach
- A replication paper should target the foundational work, not the most recent iteration of a literature
- Framing as "I replicate HR with modern data and methodological updates from DHR and Bora" is academically stronger than "I replicate DHR" (the latter sounds like just repeating what was just done)

**How HR, DHR, and Bora fit together in the writing:**

| Paper | Role in this project |
|-------|---------------------|
| HR 2014 | The paper being replicated. Section "Replication strategy" describes my approach to reproducing their main result. |
| DHR 2026 | Source of data extensions (1992 to 2023 sample, expanded country coverage, multiple NTL datasets, V-Dem index). I adopt their data choices and methodological refinements (country clustering instead of leader-period clustering). |
| Bora 2025 | Source of open-source pipeline approach (PLAD instead of proprietary leader data, GADM 4.1 instead of CIESIN, transparent reproducibility). I follow Bora's data construction approach. |

**What this means in practice:**
- Layer 1 reports HR 2014 coefficients as the primary benchmark
- Tables compare my results to HR 2014 first, then DHR 2026, then Bora 2025
- The introduction cites HR 2014 as the paper being replicated
- DHR and Bora are positioned as "subsequent work that extended HR; we adopt their data and pipeline updates"
- Writing should never say "we replicate DHR" — always "we replicate HR using updated data following DHR and Bora"

---

## 2. Why four layers, not one

The original brainstorm considered three paths:
- Path A: Direct replication only (low risk, low contribution)
- Path B: Replication + methodological critique (medium contribution)
- Path C: Replication + extension (high contribution)

We chose Path C with four layers because:

1. **Bora 2025 already did a clean open-source replication.** Just repeating that contributes nothing beyond validating Bora.
2. **A Turkey case study is achievable in scope** because the user has prior infrastructure from SDG 11.3.1 project (GADM Level 1 for Turkey, reticulate-Python GEE pipeline already validated).
3. **Spatial spillovers add genuine methodological novelty** because HR 2014, DHR 2026, and Bora 2025 all use only standard panel fixed effects, none uses spatial econometrics.
4. **Crisis premium analysis extends Bora's COVID framework** to a different crisis context (Turkish earthquakes) and engages with HR's own Supplementary Material disaster analysis (Table S.10) that has been largely overlooked in subsequent literature.
5. **OSM validation** addresses an underexplored question: does the NTL signal correspond to actual physical infrastructure changes, or could it reflect electricity consumption patterns unrelated to construction? This is a methodological cross-check that the GIS-focused course will appreciate.
6. **Three institutional measures provide robustness depth** because HR uses Polity2, DHR adds V-Dem, but WGI is in neither. Adding WGI as a third measure tests whether the result is driven by specific operationalization of "institutional quality."

The user explicitly chose to keep all extensions. The course has no hard page limit, allowing the paper to grow to 20+ pages. Layer 4 packages both the earthquake premium and OSM validation under a single "crisis context" theme, paralleling Bora 2025's COVID work.

---

## 3. Why Turkey specifically

Multiple reasons converge:

1. **Existing infrastructure.** User completed an SDG 11.3.1 project at Oldenburg with 81 province ADM1 panel for Turkey, GADM Level 1 boundaries, reticulate + Python earthengine-api authentication. GEE project ID: `ee-turkey-research`. This pipeline can be redirected to NTL collections.

2. **Rich within-country variation.** Turkey has had effective leaders born in at least 6 distinct provinces during 1992 to 2024 (Isparta, Istanbul, Sinop, Kayseri, Konya, Erzincan, possibly Rize). This provides identification leverage that is rare for a single-country study.

3. **Long single-leader episodes.** Erdoğan's tenure from 2003 onward (PM then President) creates a long episode for a single birth province. Comparing parlaklık of his birth province vs others in his long tenure is a strong test.

4. **Pre-2002 vs post-2002 contrast.** Pre-2002 coalition governments rotated through several leaders quickly. Post-2002 AKP dominance is stable. This contrast itself is a research question (do favoritism effects amplify with leader durability?).

5. **Personal proximity for the author.** Easier to identify data quality issues, biographical ambiguities, and contextual nuances when one knows the country.

6. **Pedagogically motivating.** A reviewer can follow the Erdoğan story, the Rize-vs-Istanbul coding question, the long AKP period. Concrete narratives strengthen abstract empirical results.

---

## 4. Why three institutional quality measures

DHR uses Polity5 and V-Dem Liberal Democracy index, finds V-Dem stronger. They do not use WGI.

Bora uses only Polity5.

Adding WGI Government Effectiveness as a third measure does three things:

1. **Tests robustness across conceptually distinct operationalizations.** Polity5 measures regime type (democracy vs autocracy). V-Dem measures liberal democracy with judicial constraints. WGI measures bureaucratic capacity to deliver public goods. These are not interchangeable.

2. **Engages with perception-based vs structural distinction.** WGI is perception-based (expert surveys, business surveys, citizen surveys). Polity and V-Dem are structural (constitutional and electoral features). If WGI gives different results, this informs interpretation.

3. **Pedagogical bonus.** User has prior experience with WGI from SDG 11.3.1 project where WGI Government Effectiveness was discussed at length (perception bias, 1996 start date, expected sign). This knowledge transfers directly.

**Caveat:** WGI ends in 2023 like V-Dem. WGI starts in 1996 (vs 1992 for Polity5 and V-Dem). Sample restrictions documented per panel.

---

## 5. Why spatial spillovers in Turkey, not globally

Two reasons:

1. **Computational feasibility.** Building a contiguity matrix for 45000 ADM2 polygons globally is expensive in memory. SDM estimation on a panel of 45000 regions × 33 years would require sparse matrix specialized solvers. For Turkey, 81 provinces means trivial matrix construction and standard `spatialreg` package suffices.

2. **Theoretical plausibility.** Cross-country spillovers in DHR's framework are absorbed by country-year fixed effects (good thing for identification, but precludes spatial analysis). Within-country spillovers between neighboring provinces are an underexplored channel and theoretically meaningful (transport corridors, labor migration, supply chains connecting leader province to neighbors).

The SDM is the preferred model unless LM tests favor SAR or SEM. Direct vs indirect impact decomposition will quantify how much of the total leader effect spills over.

---

## 6. NTL dataset choices

DHR uses five datasets. We will not use all five. Decision tree:

**Mandatory:**
1. DMSP-OLS yearly 1992 to 2013 (historical period, replication anchor)
2. VIIRS Black Marble monthly and yearly 2012 to 2024 (modern period, supports Layer 2)

**Strongly recommended:**
3. Chiovelli et al. 2026 harmonized dataset (DHR's preferred, gives largest coefficient)

**Optional, time permitting:**
4. Li et al. 2020 harmonized (DMSP-OLS-like values for VIIRS)
5. Nechaev et al. 2021 harmonized

Layer 1 robustness table reports all available datasets. Layer 2 Turkey analysis uses DMSP-OLS for annual 1992-2013 and VIIRS for monthly 2012-2024. Layer 3 spatial analysis uses whichever Layer 2 specification is preferred.

**On the log(NTL + 0.01) issue:** DHR uses this transformation. Chen and Roth 2024 criticize log(x + c) as problematic for estimating semi-elasticities, particularly when c affects which units are at the "extensive margin." DHR Panel B addresses this by reporting results without the constant. We follow the same: main results with constant, robustness without constant. We do NOT pursue a full PPML implementation due to scope constraints (this would itself be a paper).

---

## 6.5 Layer 4 design decisions

Layer 4 has several scoping decisions that need to be remembered across sessions:

### 6.5.1 Why three earthquakes (1999, 2011, 2023)

The three events differ in magnitude, affected population, and political context, providing variation:

- **1999 Marmara (Aug 17):** Magnitude 7.6, ~17,000 deaths. Effective leader at the time: Bülent Ecevit (PM, Istanbul birth). Affected zone includes Istanbul itself — leader birth province is in affected zone. Coalition government context.
- **2011 Van (Oct 23):** Magnitude 7.2, ~600 deaths. Effective leader: Erdoğan (PM, Istanbul birth). Affected zone (Van, Bitlis) does NOT include leader birth province. AKP single-party majority context.
- **2023 Kahramanmaraş (Feb 6):** Twin quakes magnitude 7.8 and 7.5, ~50,000 deaths. Effective leader: Erdoğan (President, Istanbul/Rize). Affected zone is southeast Turkey, distant from leader birth provinces. Single-party context with declining democratic quality (per V-Dem).

Together they provide variation in: (a) leader political context (coalition vs single-party), (b) leader birthplace location relative to disaster zone (in vs out), (c) democratic institutional quality at time of event.

### 6.5.2 Pre-quake destruction vs post-quake reconstruction

Critical methodological point: a destructive earthquake REDUCES nighttime light immediately (because buildings stop emitting light). Then reconstruction may INCREASE nighttime light back to or beyond pre-quake levels. These two phases are conceptually distinct.

Implementation:
- Months 0-6 post-quake: "destruction phase" (expect negative coefficient on Affected_it × PostQuake_it for general affected region, leader bias might MITIGATE this if leader province gets faster restoration)
- Months 7-12 post-quake: "transition phase"
- Months 13-24 post-quake: "reconstruction phase" (expect positive coefficient as rebuilding completes; leader bias might amplify this)

Layer 4 should explicitly model these three phases. Failing to do so confounds the destructive and reconstructive effects.

### 6.5.3 Affected zone definition

EM-DAT lists affected provinces as free-text. We need a binary Affected_it = 1 if province i is in the official disaster zone for event e. Two options:

- **Option A (strict):** Use only provinces where EM-DAT explicitly lists significant damage
- **Option B (broad):** Include all provinces within X km of the epicenter

We use Option A as primary (more conservative, follows AFAD official disaster zone declarations), Option B as robustness.

### 6.5.4 OSM feasibility decision rule

This is a hard go/no-go decision in Week 12. The rule:

If pre-quake OSM Hatay + Kahramanmaraş + Adıyaman provinces have fewer than 100 combined entries for amenity=hospital + amenity=school + amenity=clinic + amenity=university, OSM is too sparse and Layer 4b drops out.

If OSM is feasible, the comparison is:
- New OSM features added between Feb 2023 and Dec 2024 in each affected province
- Compare provinces with stronger political ties (e.g. AKP electoral base) to others within the affected zone

This is descriptive, not causal. We are not running a regression on OSM counts; we are showing whether the pattern of NEW infrastructure matches the NTL pattern.

### 6.5.5 What Layer 4 does NOT do

- Does not measure damage assessment (that requires separate methodology, e.g. Copernicus EMS)
- Does not analyze short-term emergency aid (different time scale than NTL captures)
- Does not extend to floods, fires, or other Turkish disasters (only earthquakes for clean treatment definition)
- Does not test pre-trends with placebo earthquakes (HR supplementary Table S.10 did simulated placebos, we follow same intuition but skip explicit simulation due to scope)

---

## 7. Turkey leader coding gotchas

Three issues that will arise in Week 2:

### 7.1 Erdoğan's birth place: Istanbul or Rize?

**Facts:**
- Official birth certificate: Kasımpaşa neighborhood, Istanbul, 26 February 1954
- Family origins: Güneysu district, Rize province, Eastern Black Sea
- Self-identification: Erdoğan publicly identifies with Rize as hometown

**PLAD coding:** Unknown until validated in Week 2. Most likely Istanbul (matches birth certificate).

**Resolution rule:** Primary analysis uses PLAD's coding. Robustness check uses the alternative. Report both in appendix table.

### 7.2 Demirel as President 1993-2000: effective leader or not?

**Issue:** Turkey's pre-2017 parliamentary system had a President as head of state but PM as head of government. PMs held executive power. However, Demirel was a former PM, politically active President, and shaped major decisions.

**PLAD coding:** Unknown. Likely codes the sitting PM as effective leader, not Demirel. But this needs verification.

**Resolution rule:** Follow PLAD coding strictly. Document in appendix.

### 7.3 2014-2018: President Erdoğan or sitting PM Davutoğlu/Yıldırım?

**Issue:** Constitutionally still parliamentary until 2018, but Erdoğan as popularly-elected President wielded substantial influence, eventually leading to Davutoğlu's resignation in conflict with him.

**PLAD coding:** Likely complicated. Could code both, could code only PM, could code only Erdoğan.

**Resolution rule:** Whatever PLAD does, we follow. If PLAD codes both, our Leader_it dummy could equal 1 for two provinces in same year — explicitly handle this in panel construction.

---

## 8. Things NOT to do

To prevent scope creep and avoid wasted effort:

1. **Do not attempt full Bora 2025 replication including COVID premium identification.** Bora's COVID identification strategy with placebo simulations is computationally heavy and not in our scope. Mention Bora's COVID finding and move on.

2. **Do not download raw Black Marble HDF5 tiles to local storage if avoidable.** Use Google Earth Engine for zonal statistics. Only download tiles if a specific layer (e.g. viewing angle sublayer 15) is needed and GEE collection lacks it.

3. **Do not change PLAD coding decisions unilaterally.** Whatever PLAD codes for Turkey leaders, use it as primary. Robustness with alternatives only.

4. **Do not extend analysis beyond ADM1 for Turkey.** ADM2 (districts) for Turkey has 957 units, which is overkill for spatial analysis and creates data noise. Stay at ADM1 (81 provinces).

5. **Do not use OLS pooling across countries in Layer 1.** Always include country fixed effects (DHR uses country-year, we follow).

6. **Do not report continuous treatment definitions.** Leader_it is binary. Continuous definitions (years since taking office, intensity of presence) are extensions for future work.

7. **Do not test for ethnic favoritism (De Luca et al. 2018).** Ethnic homelands are different units. Stay with administrative regions.

8. **Do not use PPML estimator as primary.** Mention Chen and Roth 2024 in writing, defend log(NTL + 0.01) with reference to DHR Panel B extensive margin results.

9. **Do not write the paper in Turkish.** All deliverables in English per course expectation and user preference.

10. **Do not include Claude as contributor or co-author in any commit or document.** This is an explicit user preference.

11. **Do not include earthquakes outside Turkey in Layer 4.** Other countries had earthquakes in our sample period (Haiti 2010, Japan 2011, Nepal 2015, etc.) but extending to global earthquake panel is a separate paper. Turkey only.

12. **Do not interpret OSM "new feature" counts as causal evidence.** Layer 4b is DESCRIPTIVE validation, not a regression. The hypothesis is "if NTL says province X got more reconstruction, OSM should show more new infrastructure in X." This is a correlation check, not a causal claim.

13. **Do not pursue Layer 4b OSM analysis if pre-quake coverage is sparse.** Apply the decision rule strictly: under 100 combined entries means drop the analysis. Document the limitation honestly.

---

## 9. Open decisions deferred to Week 1 or 2

1. **DHR replication package format.** If Stata, we recreate specifications in R rather than translate code. If R or mixed, we may directly adapt portions.

2. **VIIRS access method.** Two options:
   - GEE collection `NOAA/VIIRS/DNB/MONTHLY_V1` (faster, but no viewing angle stratification)
   - Direct download from LAADS DAAC (slower, full Black Marble suite available)
   Decision: start with GEE, switch to LAADS only if Layer 2 results suggest viewing angle matters.

3. **Chiovelli et al. 2026 dataset availability.** Need to check if their replication package is public.

4. **PLAD version.** Multiple versions exist. We will use the most recent public version, document version number in code.

5. **Turkey time variation in WGI.** WGI starts 1996, but is biennial 1996-2002. Linear interpolation or omit early years?

6. **Province aggregation for new provinces.** Bartin (1991), Karabuk (1995), etc. Use post-2000 boundaries throughout and back-cast NTL accordingly.

---

## 10. First message for Claude Code handoff

When migrating this project to Claude Code, paste this as the first message:

> Read ROADMAP.md, CONTEXT.md, DATA_SOURCES.md, TURKEY_LEADERS.md, and WEEK1_TASKS.md in this directory and confirm you understand the project.
>
> This is a replication and extension of Hodler and Raschky 2014 (QJE), the foundational paper on regional favoritism. We replicate HR 2014 as the primary target, but adopt data extensions and methodological refinements from Düben, Hodler, Raschky 2026 (DHR) and Bora 2025. HR is the paper being replicated; DHR and Bora are sources of updates we incorporate.
>
> Four original extensions on top of the replication:
> (a) a global replication that adds WGI Government Effectiveness as a third institutional quality measure (HR uses Polity, DHR adds V-Dem, WGI is new)
> (b) a Turkey case study with monthly VIIRS data at the province level
> (c) a spatial spillovers analysis in Turkey using Spatial Durbin Model
> (d) a crisis premium analysis around three Turkish earthquakes (1999 Marmara, 2011 Van, 2023 Kahramanmaraş) combining NTL with EM-DAT, with optional OSM physical infrastructure validation for the 2023 event
>
> Style constraints: all code and comments in English, no em-dashes, no Claude as contributor in any commit. Primary language R, secondary Python via reticulate for GEE. Reuse SDG 11.3.1 GEE infrastructure (project ID: ee-turkey-research).
>
> Timeline: 14 weeks total. No hard page limit per user preference; target 18-22 pages.
>
> Confirm understanding by summarizing back: (1) the primary replication target, (2) the role of DHR and Bora, (3) the four extensions in order, (4) the framing rule (never say "we replicate DHR"), (5) the OSM feasibility decision rule for Layer 4b. Then begin Week 1 tasks per WEEK1_TASKS.md.

---

## 11. Style preferences for writing

- No em-dashes anywhere
- Sentence case in section headings
- APA reference format
- Tables in LaTeX, generated from R via modelsummary
- Figures via ggplot2, exported as PDF
- No bolding mid-sentence; entity names in code style
- Decimal point not comma (English convention)
- Statistical significance: stars at 10/5/1 percent (matches DHR)
