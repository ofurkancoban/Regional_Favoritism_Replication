# R/10_replication_regression.R
# Purpose: Replicate HR 2014 Table II Panel A following DHR methodology.
# Spec: ln_ntl ~ l(is_birthregion) | gid_2 + gid_0^year, vcov = ~gid_0
# - gid_2:       ADM2 region fixed effects
# - gid_0^year:  country-year fixed effects (absorbs all country-level controls)
# - l():         one-period lag (fixest panel syntax)
# - vcov ~gid_0: SE clustered at country level

library(data.table)
library(fixest)

cat("=== Loading panel ===\n")
panel <- data.table::fread("data/processed/analysis_panel.csv")
cat(sprintf("Rows: %d | ADM2 regions: %d | Countries: %d | Years: %d-%d\n",
    nrow(panel), uniqueN(panel$gid_2), uniqueN(panel$iso3),
    min(panel$year), max(panel$year)))

# Declare panel structure for fixest l() lag operator
panel_fe <- fixest::panel(panel, ~gid_2 + year)

cat("\n=== Panel A: Main results (HR Table II replication) ===\n")

# Col 1: baseline -- ln(NTL+0.01) ~ lag(birthplace) | region FE + country-year FE
m1 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
  data = panel_fe,
  vcov = ~gid_0
)

# Col 2: extensive margin -- ln(NTL), drops zero-light obs
m2 <- fixest::feols(
  ln_ntl_00 ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
  data = panel_fe[is.finite(panel_fe$ln_ntl_00), ],
  vcov = ~gid_0
)

# Col 3: dynamics -- leads and lags of is_birthregion
# Pre-create lead/lag dummies (DHR approach)
panel_dyn <- data.table::copy(panel_fe)
data.table::setorder(panel_dyn, gid_2, year)
for (k in 1:3) {
  panel_dyn[, paste0("pre",  k) := data.table::shift(is_birthregion, -k, type = "lead"), by = gid_2]
  panel_dyn[, paste0("post", k) := data.table::shift(is_birthregion,  k, type = "lag"),  by = gid_2]
}
panel_dyn <- fixest::panel(panel_dyn, ~gid_2 + year)

m3 <- fixest::feols(
  ln_ntl ~ fixest::l(pre3) + fixest::l(pre2) + fixest::l(pre1) +
           fixest::l(is_birthregion) +
           fixest::l(post1) + fixest::l(post2) + fixest::l(post3) | gid_2 + gid_0^year,
  data = panel_dyn,
  vcov = ~gid_0
)

cat("\n--- Model 1: Baseline ---\n")
fixest::etable(m1, digits = 3)

cat("\n--- Model 2: Extensive margin ---\n")
fixest::etable(m2, digits = 3)

cat("\n--- Model 3: Dynamics (pre/post) ---\n")
fixest::etable(m3, digits = 3)

cat("\n=== Extension A: WGI Government Effectiveness interaction ===\n")
wgi <- data.table::fread("data/raw/qog/qog_std_ts_jan26.csv",
  select = c("ccodealp", "year", "wbgi_gee"))
data.table::setnames(wgi, c("iso3", "year", "wbgi_gee"))

panel_wgi <- merge(data.table::copy(panel), wgi, by = c("iso3", "year"), all.x = TRUE)
panel_wgi[, z_wbgi_gee := as.numeric(scale(wbgi_gee))]
panel_wgi <- fixest::panel(panel_wgi, ~gid_2 + year)

m4 <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) +
           fixest::l(is_birthregion * z_wbgi_gee) | gid_2 + gid_0^year,
  data = panel_wgi,
  vcov = ~gid_0
)
fixest::etable(m4, digits = 3)

cat("\n=== Summary across models ===\n")
fixest::etable(m1, m2, m3,
  digits  = 3,
  keep    = "is_birthregion",
  headers = c("Baseline", "Extensive", "Dynamics")
)

cat(sprintf("\nHR 2014 Table II Panel A benchmark: coef ~ 0.08 (se ~ 0.03)\n"))
cat(sprintf("Our estimate (M1):               coef = %.4f  se = %.4f  p = %.4f\n",
    stats::coef(m1)[1],
    sqrt(diag(stats::vcov(m1)))[1],
    summary(m1)$coeftable[1, 4]))
