# 07_regression/turkey_earthquake/01_crisis_premium.R
# Crisis-premium extension: does the 6 Feb 2023 Kahramanmaras earthquake,
# as a national fiscal/discretionary-spending shock, produce a temporary
# increase in nighttime-light favoritism for the sitting leader's own
# birth province -- following Bora (2025)'s COVID-premium logic
# (671.pdf), applied to a localized natural disaster instead of a global
# pandemic.
#
# Identification note (differs from Bora's cross-country COVID design):
# Turkey has a single sitting leader (Erdogan, born Istanbul per PLAD,
# see 00_notes/TURKEY_LEADERS.md) throughout the entire 2022-02/2024-02
# window -- no leader turnover. Leader_i is therefore TIME-INVARIANT
# (Istanbul=1, all other provinces=0, every month), so it cannot be
# identified on its own once province fixed effects are included (they
# absorb it completely). This is not a problem for the actual object of
# interest, though: Leader_i x Post_t is NOT collinear with province FE
# (Post_t varies over time), so the crisis-premium interaction is a
# perfectly standard difference-in-differences design -- "did Istanbul's
# gap to other provinces widen after the earthquake, beyond Istanbul's
# own pre-existing trend." Affected_i x Post_t (the 4 quake-hit provinces:
# Kahramanmaras, Hatay, Adiyaman, Malatya) is included throughout to net
# out the direct physical-damage effect on light (power outages,
# destruction, later reconstruction) from the leader-favoritism channel,
# since these are two entirely different sets of provinces (Istanbul is
# not earthquake-affected) with no collinearity between the two.
#
# Data: data/processed/ntl/turkey_luna_blackmarble_monthly_adm1.csv
#   (VNP46A3 NearNadir Composite, 81 provinces x 25 months, 2022-02 to
#   2024-02, downloaded via luna+blackmarbler -- see
#   04_extraction/10_turkey_luna_blackmarble_monthly.R)
#
# Specifications:
#   (1) Simple DiD: Leader_i x Post_t, controlling for Affected_i x Post_t,
#       province + month FE.
#   (2) Event-study: Leader_i x RelMonth_t (dummies for each month
#       relative to the earthquake, omitting t=-1 as reference), same
#       controls, to see the dynamic pattern (does the premium appear
#       immediately, build up, or fade) rather than a single average.

library(data.table)
library(fixest)

cat("=== Load Turkey monthly NTL panel ===\n")
panel <- data.table::fread("data/processed/ntl/turkey_luna_blackmarble_monthly_adm1.csv")
panel[, date := as.Date(sprintf("%d-%02d-01", year, month))]
panel[, ln_ntl := log(pmax(viirs_ntl, 0) + 0.01)]

quake_date <- as.Date("2023-02-01")  # month of the 6 Feb 2023 earthquake
affected   <- c("K.Maras", "Hatay", "Adiyaman", "Malatya")
leader_province <- "Istanbul"  # Erdogan's PLAD-coded birth province throughout this window

panel[, leader   := as.integer(NAME_1 == leader_province)]
panel[, affected := as.integer(NAME_1 %in% affected)]
panel[, post     := as.integer(date >= quake_date)]

# Months relative to the earthquake (0 = Feb 2023), for the event-study
# spec. Range: -12 to +12 given the panel window.
panel[, rel_month := (year - 2023L) * 12L + (month - 2L)]

cat(sprintf("Provinces: %d | Months: %d | Leader province: %s | Affected: %s\n",
    data.table::uniqueN(panel$NAME_1), data.table::uniqueN(panel$date),
    leader_province, paste(affected, collapse = ", ")))

cat("\n=== Spec (1): Simple DiD -- Leader x Post ===\n")
m1 <- fixest::feols(
  ln_ntl ~ leader:post + affected:post | NAME_1 + date,
  data = panel, vcov = ~NAME_1
)
print(fixest::etable(m1, digits = 4))

cat("\n=== Spec (2): Event-study -- Leader x RelMonth (ref: t = -1) ===\n")
panel[, rel_f := factor(rel_month)]
panel[, rel_f := stats::relevel(rel_f, ref = "-1")]
m2 <- fixest::feols(
  ln_ntl ~ leader:rel_f + affected:post | NAME_1 + date,
  data = panel, vcov = ~NAME_1
)
print(fixest::etable(m2, digits = 4))

cat("\n=== Coefficient plot data (Spec 2, leader x rel_month terms only) ===\n")
coefs <- as.data.table(broom::tidy(m2), keep.rownames = TRUE)
coefs <- coefs[grepl("^leader:rel_f", term)]
coefs[, rel_month := as.integer(sub("^leader:rel_f", "", term))]
data.table::setorder(coefs, rel_month)
print(coefs[, .(rel_month, estimate, std.error, p.value)])
data.table::fwrite(coefs[, .(rel_month, estimate, std.error, p.value)],
    "data/processed/ntl/turkey_earthquake_event_study_coefs.csv")

cat("\nModels saved for later reference.\n")
saveRDS(list(m1 = m1, m2 = m2), "data/processed/ntl/turkey_earthquake_crisis_premium_models.rds")
