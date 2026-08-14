# R/10b_comparison.R
# Purpose: Compare our GEE DMSP estimate against all 5 NTL sources in DHR dataset.
# DHR adm_2.csv.gz already contains zonal means for: OLS, Chen, Chiovelli, Li, Nechaev.

library(data.table)
library(fixest)

cat("=== Loading DHR dataset ===\n")
d <- data.table::fread("01_literature/dataverse_files/data/analysis/adm_2.csv.gz")
d_hr <- d[year %between% c(1992L, 2013L)]

# Create log variables for all NTL sources
ntl_sources <- c("ols", "chen", "chiovelli", "li", "nechaev")
for (s in ntl_sources) {
  col_raw <- paste0("light_mean_", s)
  col_ln  <- paste0("ln_", s)
  d_hr[, (col_ln) := log(get(col_raw) + 0.01)]
}

d_hr[, gid_0year := paste0(gid_0, "_", year)]
cat(sprintf("DHR HR window: %d rows | %d countries | %d regions\n",
    nrow(d_hr), uniqueN(d_hr$gid_0), uniqueN(d_hr$gid_2)))

cat("\n=== DHR regressions: all 5 NTL sources ===\n")
dhr_models <- lapply(ntl_sources, function(s) {
  yvar <- paste0("ln_", s)
  dat  <- fixest::panel(d_hr[!is.na(get(yvar))], ~gid_2 + year)
  fixest::feols(
    stats::as.formula(paste0(yvar, " ~ fixest::l(is_birthregion) | gid_2 + gid_0^year")),
    data = dat, vcov = ~gid_0
  )
})
names(dhr_models) <- ntl_sources

fixest::etable(dhr_models,
  digits  = 3,
  keep    = "is_birthregion",
  headers = c("OLS", "Chen", "Chiovelli", "Li", "Nechaev")
)

cat("\n=== Our GEE DMSP estimate ===\n")
panel    <- data.table::fread("data/processed/analysis_panel.csv")
panel_fe <- fixest::panel(panel, ~gid_2 + year)
our_m1   <- fixest::feols(
  ln_ntl ~ fixest::l(is_birthregion) | gid_2 + gid_0^year,
  data = panel_fe, vcov = ~gid_0
)
fixest::etable(our_m1, digits = 3)

cat("\n=== Full comparison ===\n")
all_models <- c(dhr_models, list(our_gee = our_m1))
fixest::etable(all_models,
  digits  = 3,
  keep    = "is_birthregion",
  headers = c("DHR OLS", "DHR Chen", "DHR Chiovelli", "DHR Li", "DHR Nechaev", "Our GEE DMSP")
)

cat("\nCoefficients:\n")
for (nm in names(all_models)) {
  m  <- all_models[[nm]]
  cf <- stats::coef(m)[1]
  se <- sqrt(diag(stats::vcov(m)))[1]
  pv <- summary(m)$coeftable[1, 4]
  sig <- dplyr::case_when(pv < 0.001 ~ "***", pv < 0.01 ~ "**", pv < 0.05 ~ "*", pv < 0.1 ~ ".", TRUE ~ "")
  cat(sprintf("  %-16s  coef=%7.4f  se=%6.4f  p=%5.3f%s  N=%d\n",
      nm, cf, se, pv, sig, m$nobs))
}
