# 02_crosswalk/04_wikidata_missing_leaders.R
# Purpose: fill the ~120 Archigos leader-spells (1992-2013 window) that PLAD
# has no birthplace for (see RESEARCH_JOURNAL.md, "PLAD coverage gap"
# analysis, 2026-08-17) using Wikidata's structured "place of birth" (P19)
# + place coordinates (P625) as a supplementary, automatable source -- the
# same spirit as HR 2014's own hand-collection ("various Internet sites"),
# just scripted against Wikidata instead of done by hand.
#
# Method per leader:
#   1. wbsearchentities for the Archigos surname/name string.
#   2. Keep only candidates whose Wikidata description plausibly matches a
#      head of state/government of the right country (country name or
#      president/prime minister/king/emir/etc. in the description).
#   3. For a single unambiguous match, fetch P19 (place of birth) via
#      wbgetentities, then that place's P625 (coordinate location).
#   4. Leaders with zero or multiple plausible candidates are left
#      unresolved and reported for manual review -- no guessing.
#
# Output: data/processed/wikidata_missing_leaders.csv
#   Columns: leader, iso3, startyear, endyear, wikidata_qid, birthplace_label,
#            birthplace_qid, lat, lon, status ("resolved"/"ambiguous"/"not_found"/"no_coords")

library(data.table)
library(httr)
library(jsonlite)
library(countrycode)

missing <- data.table::fread("/tmp/missing_leaders.csv")
missing[, country_name := countrycode::countrycode(iso3, "iso3c", "country.name")]
leaders <- unique(missing[, .(leader, iso3, country_name)])
cat(sprintf("Unique (leader, country) pairs to resolve: %d\n", nrow(leaders)))

ua <- httr::user_agent("RegionalFavoritismReplication/1.0 (academic research)")

wd_search <- function(query) {
  res <- tryCatch(httr::GET("https://www.wikidata.org/w/api.php", ua, query = list(
    action = "wbsearchentities", search = query, language = "en", format = "json", limit = 10
  )), error = function(e) NULL)
  if (is.null(res) || httr::status_code(res) != 200) return(NULL)
  jsonlite::fromJSON(httr::content(res, as = "text", encoding = "UTF-8"), simplifyVector = FALSE)$search
}

wd_entity <- function(qid) {
  res <- tryCatch(httr::GET("https://www.wikidata.org/w/api.php", ua, query = list(
    action = "wbgetentities", ids = qid, props = "claims", format = "json"
  )), error = function(e) NULL)
  if (is.null(res) || httr::status_code(res) != 200) return(NULL)
  jsonlite::fromJSON(httr::content(res, as = "text", encoding = "UTF-8"), simplifyVector = FALSE)$entities[[qid]]$claims
}

title_words <- c("president", "prime minister", "king", "queen", "emir", "sultan",
                  "chief minister", "head of state", "head of government", "premier",
                  "chairman", "governor-general", "monarch")

leaders[, `:=`(wikidata_qid = NA_character_, birthplace_label = NA_character_,
               birthplace_qid = NA_character_, lat = NA_real_, lon = NA_real_,
               status = "not_found")]

for (i in seq_len(nrow(leaders))) {
  nm <- leaders$leader[i]; cn <- leaders$country_name[i]
  cat(sprintf("[%d/%d] %s (%s)... ", i, nrow(leaders), nm, cn))
  hits <- wd_search(nm)
  Sys.sleep(0.3)
  if (is.null(hits) || length(hits) == 0) {
    # fallback: append the country name to the search string -- helps for
    # short/partial Archigos surnames that alone return nothing
    hits <- wd_search(paste(nm, cn))
    Sys.sleep(0.3)
  }
  if (is.null(hits) || length(hits) == 0) { cat("no search results\n"); next }

  # Strict: the Wikidata description must literally name the country --
  # matching on a bare title word ("king", "president") alone is not
  # sufficient disambiguation (e.g. "Stuart" alone matched a Scottish
  # monarch, not a Barbadian prime minister, in an earlier looser version
  # of this filter).
  plausible <- Filter(function(h) {
    desc <- tolower(if (!is.null(h$description)) h$description else "")
    grepl(tolower(cn), desc, fixed = TRUE)
  }, hits)

  if (length(plausible) == 0) { cat("no plausible candidate\n"); next }
  if (length(plausible) > 1) {
    # narrow further: description should also carry a head-of-state/government title
    narrowed <- Filter(function(h) {
      desc <- tolower(if (!is.null(h$description)) h$description else "")
      any(vapply(title_words, grepl, logical(1), x = desc, fixed = TRUE))
    }, plausible)
    if (length(narrowed) == 1) plausible <- narrowed
  }
  if (length(plausible) != 1) { leaders[i, status := "ambiguous"]; cat(sprintf("ambiguous (%d candidates)\n", length(plausible))); next }

  qid <- plausible[[1]]$id
  leaders[i, wikidata_qid := qid]
  claims <- wd_entity(qid)
  Sys.sleep(0.3)
  if (is.null(claims) || is.null(claims[["P19"]])) { leaders[i, status := "not_found"]; cat("no P19\n"); next }

  bp_qid <- claims[["P19"]][[1]]$mainsnak$datavalue$value$id
  leaders[i, birthplace_qid := bp_qid]

  bp_claims <- wd_entity(bp_qid)
  Sys.sleep(0.3)
  if (is.null(bp_claims) || is.null(bp_claims[["P625"]])) { leaders[i, status := "no_coords"]; cat("no P625 on birthplace\n"); next }

  coord <- bp_claims[["P625"]][[1]]$mainsnak$datavalue$value
  leaders[i, `:=`(lat = coord$latitude, lon = coord$longitude, status = "resolved")]
  cat(sprintf("resolved (%.3f, %.3f)\n", coord$latitude, coord$longitude))
}

cat("\n=== Summary ===\n")
print(leaders[, .N, by = status])

data.table::fwrite(leaders, "data/processed/wikidata_missing_leaders.csv")
cat("\nSaved: data/processed/wikidata_missing_leaders.csv\n")
