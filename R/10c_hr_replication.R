# R/10c_hr_replication.R
# Purpose: Exact HR 2014 replication using DHR adm_2.csv.gz dataset.
# HR window: 1992-2009, OLS NTL source.
# Extended window: 1992-2013 (DMSP era), 1992-2023 (full).

library(data.table)
library(fixest)

cat("=== Loading DHR dataset ===\n")
d <- data.table::fread("01_literature/dataverse_files/data/analysis/adm_2.csv.gz")

ntl_sources <- c("ols", "chiovelli", "li", "chen", "nechaev")
for (s in ntl_sources) {
  d[, paste0("ln_", s) := log(get(paste0("light_mean_", s)) + 0.01)]
}

cat("\n=== Window 1: HR replication (1992-2009) ===\n")
d_hr <- fixest::panel(d[year %between% c(1992L, 2009L)], ~gid_2 + year)
m_hr <- lapply(ntl_sources, function(s) {
  fixest::feols(
    stats::as.formula(paste0("ln_", s, " ~ fixest::l(is_birthregion) | gid_2 + gid_0^year")),
    data = d_hr, vcov = ~gid_0
  )
})
names(m_hr) <- ntl_sources
fixest::etable(m_hr, digits = 3, keep = "is_birthregion",
  headers = c("OLS", "Chiovelli", "Li", "Chen", "Nechaev"),
  title = "HR window 1992-2009")

cat("\n=== Window 2: DMSP era (1992-2013) ===\n")
d_dmsp <- fixest::panel(d[year %between% c(1992L, 2013L)], ~gid_2 + year)
m_dmsp <- lapply(ntl_sources, function(s) {
  fixest::feols(
    stats::as.formula(paste0("ln_", s, " ~ fixest::l(is_birthregion) | gid_2 + gid_0^year")),
    data = d_dmsp, vcov = ~gid_0
  )
})
names(m_dmsp) <- ntl_sources
fixest::etable(m_dmsp, digits = 3, keep = "is_birthregion",
  headers = c("OLS", "Chiovelli", "Li", "Chen", "Nechaev"),
  title = "DMSP era 1992-2013")

cat("\n=== Window 3: Full period (1992-2023) ===\n")
d_full <- fixest::panel(d[year >= 1992L], ~gid_2 + year)
m_full <- lapply(ntl_sources, function(s) {
  fixest::feols(
    stats::as.formula(paste0("ln_", s, " ~ fixest::l(is_birthregion) | gid_2 + gid_0^year")),
    data = d_full, vcov = ~gid_0
  )
})
names(m_full) <- ntl_sources
fixest::etable(m_full, digits = 3, keep = "is_birthregion",
  headers = c("OLS", "Chiovelli", "Li", "Chen", "Nechaev"),
  title = "Full period 1992-2023")

cat("\n=== Summary: OLS across windows ===\n")
fixest::etable(m_hr$ols, m_dmsp$ols, m_full$ols,
  digits = 3, keep = "is_birthregion",
  headers = c("1992-2009 (HR)", "1992-2013 (DMSP)", "1992-2023 (Full)"))

cat("\nCoefficients:\n")
cat(sprintf("%-35s  %s\n", "Specification", "coef     se      p"))
cat(strrep("-", 65), "\n")
for (win in c("HR (1992-2009)", "DMSP (1992-2013)", "Full (1992-2023)")) {
  mlist <- list("HR (1992-2009)" = m_hr, "DMSP (1992-2013)" = m_dmsp, "Full (1992-2023)" = m_full)[[win]]
  for (s in ntl_sources) {
    m  <- mlist[[s]]
    cf <- stats::coef(m)[1]
    se <- sqrt(diag(stats::vcov(m)))[1]
    pv <- summary(m)$coeftable[1, 4]
    sig <- ifelse(pv < 0.001, "***", ifelse(pv < 0.01, "**", ifelse(pv < 0.05, "*", ifelse(pv < 0.1, ".", " "))))
    cat(sprintf("  %-12s %-20s  %6.4f  %6.4f  %5.3f%s\n", win, s, cf, se, pv, sig))
  }
  cat("\n")
}
