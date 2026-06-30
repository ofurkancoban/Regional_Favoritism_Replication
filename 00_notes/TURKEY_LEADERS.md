# Turkey Effective Leaders: Birth Places and Coding

**Project:** Regional Favoritism Replication and Extension, Layer 2
**Last updated:** 30 June 2026
**Status:** Draft, requires manual validation in Week 2

This document defines the universe of "effective political leaders" for Turkey during the sample period (1992 to 2024), their birth places, and the coding rules for the Leader_it dummy variable. Each entry must be cross-validated against three independent biographical sources before use in regression.

---

## 1. Coding definition

**Effective leader:** Following Archigos and PLAD definition, the person who holds ultimate executive power.

For Turkey, the effective leader is:
- The Prime Minister, from 1923 to August 2014
- The President, from August 2014 onwards (when Erdogan moved from PM to popularly-elected President with expanded powers)

**Note:** Turkey transitioned from parliamentary to presidential system formally in July 2018 (after the April 2017 constitutional referendum). However, Erdogan held executive power from 2003 onwards continuously, first as PM then as President. PLAD's coding should be cross-checked for this transition.

**Birth place definition:** Province (ADM1) of birth based on the leader's official biographical record. Where the leader was born in a place that is now in a different province (due to provincial reorganization), use the province as defined at the time of birth.

**Leader_it = 1** if and only if province i was the birth province of the effective leader during year (or month) t, AND that leader held office for at least a quarter of the period (90 days for yearly, 8 days for monthly), following Bora 2025 convention.

---

## 2. Sample period leaders

### Süleyman Demirel
- **Office:** President (1993-2000), previously PM multiple times in 1960s, 1970s, 1991-1993
- **Sample tenure as effective leader:** 1991 to 16 May 2000
- **Birth:** 1 November 1924, Islamkoy village, Atabey district, Isparta province
- **GADM ADM1:** Isparta (TUR.32_1 or similar code, verify in Week 1)
- **Notes:** Was PM 1991-1993 then succeeded Ozal as President. Verify whether PLAD codes him from 1991 or 1993.

### Tansu Çiller
- **Office:** Prime Minister (June 1993 to March 1996)
- **Birth:** 24 May 1946, Istanbul
- **GADM ADM1:** Istanbul
- **Notes:** First female PM of Turkey. Tenure 33 months.

### Mesut Yılmaz
- **Office:** Prime Minister (multiple times: June-July 1991, March-June 1996, June 1997 to January 1999)
- **Birth:** 6 November 1947, Istanbul
- **GADM ADM1:** Istanbul
- **Notes:** Three separate PM stints. Each handled separately in panel.

### Necmettin Erbakan
- **Office:** Prime Minister (June 1996 to June 1997)
- **Birth:** 29 October 1926, Sinop
- **GADM ADM1:** Sinop
- **Notes:** Welfare Party (Refah Partisi) PM, removed via military memorandum (28 February 1997 process).

### Bülent Ecevit
- **Office:** Prime Minister (multiple: 1974, 1977, 1978-79, January 1999 to November 2002)
- **Birth:** 28 May 1925, Istanbul
- **GADM ADM1:** Istanbul
- **Notes:** Long career. Sample period stint 1999-2002.

### Abdullah Gül
- **Office:** Prime Minister (November 2002 to March 2003), then President (August 2007 to August 2014)
- **Birth:** 29 October 1950, Kayseri
- **GADM ADM1:** Kayseri
- **Notes:** Brief PM stint (3 months) while Erdogan was banned from politics. PLAD likely codes him as effective leader for both periods. Cross-check whether PLAD treats 2007-2014 presidency as effective leader (since constitutional powers were limited).

### Recep Tayyip Erdoğan
- **Office:** Prime Minister (March 2003 to August 2014), President (August 2014 to present)
- **Birth:** 26 February 1954, Kasimpasa, Istanbul (officially), though family roots in Rize
- **GADM ADM1:** Istanbul (by official birth registration) — but PLAD coding ambiguous
- **CRITICAL CODING DECISION:** 
  - Option A: Code as Istanbul (matches official birth certificate)
  - Option B: Code as Rize (matches family origins, commonly identified as hometown)
  - Bora 2025 likely uses PLAD's coding, which we will verify in Week 2
  - HR 2014 sample ends in 2009, did not face this decision
- **Recommended approach:** Use PLAD coding as primary, conduct robustness check with the alternative

### Ahmet Davutoğlu
- **Office:** Prime Minister (August 2014 to May 2016)
- **Birth:** 26 February 1959, Taşkent, Konya
- **GADM ADM1:** Konya
- **Notes:** Foreign Minister before becoming PM. Resigned after political conflict with Erdogan.

### Binali Yıldırım
- **Office:** Prime Minister (May 2016 to July 2018)
- **Birth:** 20 December 1955, Refahiye, Erzincan
- **GADM ADM1:** Erzincan
- **Notes:** Last PM before transition to presidential system. After July 2018, the PM position was abolished.

---

## 3. Coding table (draft, to be validated)

| Period start | Period end | Leader | Birth ADM1 | Notes |
|--------------|-----------|--------|------------|-------|
| 1992-01-01 | 1993-05-16 | Demirel (President) + Yilmaz/Demirel as PM | Mixed | Pre-presidency Demirel as PM until June 1991, then Yilmaz until November 1991, Demirel returns... CONFUSING TRANSITIONS |
| 1993-05-16 | 1993-06-25 | Demirel becomes President | Isparta | Transition gap before Ciller becomes PM |
| 1993-06-25 | 1996-03-06 | Çiller (PM) | Istanbul | |
| 1996-03-06 | 1996-06-28 | Yılmaz (PM) | Istanbul | Brief coalition |
| 1996-06-28 | 1997-06-30 | Erbakan (PM) | Sinop | Welfare Party |
| 1997-06-30 | 1999-01-11 | Yılmaz (PM) | Istanbul | Third PM stint |
| 1999-01-11 | 2002-11-18 | Ecevit (PM) | Istanbul | |
| 2002-11-18 | 2003-03-14 | Gül (PM) | Kayseri | Caretaker for Erdogan |
| 2003-03-14 | 2014-08-28 | Erdoğan (PM) | Istanbul or Rize | LONG TENURE, KEY VARIATION |
| 2014-08-28 | 2016-05-24 | Davutoğlu (PM) under Erdogan presidency | Konya | But Erdogan is now President |
| 2016-05-24 | 2018-07-09 | Yıldırım (PM) under Erdogan presidency | Erzincan | Final PM |
| 2018-07-09 | present | Erdoğan (President) | Istanbul or Rize | Sole executive |

**Major coding challenges to resolve:**
1. The 1991-1993 multiple transitions need careful PM-by-PM coding
2. Erdoğan-Davutoğlu-Yıldırım period: who is the "effective leader" — President Erdoğan or sitting PM? PLAD will define this; we follow PLAD.
3. Erdoğan's birth ADM1: Istanbul (de jure) or Rize (de facto family)? Robustness check both.
4. Demirel as President 1993-2000: was he "effective" during this period? PLAD likely says yes, given he was a former PM and politically active.

---

## 4. PLAD validation procedure (Week 2 task)

For each leader listed above, perform the following validation:

1. Open PLAD database, locate leader's entry
2. Record PLAD's coding for:
   - Tenure start and end dates
   - Birth place ADM1 and ADM2 (with PLAD's geocoding precision flag)
   - Whether classified as "effective leader" or supporting figure
3. Cross-validate birth place against three sources:
   - English-language source (Britannica, official government bio)
   - Turkish-language source (TBMM website, Cumhurbaşkanlığı website)
   - Independent source (Wikipedia, news media)
4. If discrepancy exists, document in this file with resolution rule

---

## 5. Variation structure

To preview identification:

**Years with no leader (or unclear leader) effect:** 1992 to early 1993 (multiple transitions)

**Distinct leader birth provinces in sample:** Isparta, Istanbul, Sinop, Kayseri, Erzincan, Konya, and possibly Rize. That is 6 to 7 distinct provinces out of 81.

**Provinces that are ALWAYS leader province in some sub-period:**
- Istanbul: 1993-1996 (Çiller), 1996 (Yılmaz), 1997-1999 (Yılmaz), 1999-2002 (Ecevit), 2003-2014 (Erdoğan, if Istanbul coding), 2014-present (Erdoğan)
- Kayseri: only 2002-2003 (Gül, very brief, 4 months)
- Konya: only 2014-2016 (Davutoğlu, 21 months)
- Erzincan: only 2016-2018 (Yıldırım, 26 months)
- Isparta: 1993-2000 (Demirel as President, if coded as effective)
- Sinop: 1996-1997 (Erbakan, 12 months)
- Rize: contingent on Erdoğan coding

**Provinces that are NEVER leader province:** 74+ out of 81 — these are the natural controls.

**Identification concern:** Istanbul is overrepresented as a leader birth province. This is realistic (Istanbul has historically produced many Turkish PMs) but creates a strong fixed-effect issue. Robustness check: drop Istanbul as a leader province and re-estimate.

---

## 6. Open questions for Week 2 validation

- [ ] How does PLAD code Demirel during his presidency? As effective leader or not?
- [ ] How does PLAD code Erdoğan: Istanbul or Rize?
- [ ] How does PLAD treat the 2014-2018 period: is Erdoğan or the sitting PM the effective leader?
- [ ] What threshold does PLAD use for partial-period tenures? (Bora uses 25% of period, DHR not specified)
- [ ] Are there any leaders missing from this list that PLAD includes?
- [ ] Are there any leaders in this list that PLAD excludes (e.g. because too brief)?
