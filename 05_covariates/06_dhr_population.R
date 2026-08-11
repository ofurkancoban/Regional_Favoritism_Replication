# Purpose: Use DHR (2025/2026)'s own already-processed population covariate
# (lnpop, derived from GHS-POP, Schiavina et al. 2023) as an interim
# population source while our own GHS-POP VPS pipeline (raw raster
# download + terra::zonal to GADM 3.6 ADM2) runs in the background.
#
# gid_2 scheme check (2026-08-21): DHR's adm_2.csv gid_2 values are a
# 100% subset of our own GADM 3.6 level2 GID_2 values (45,490/45,490
# match exactly; we have 472 extra regions DHR excludes). No crosswalk
# needed -- this is a direct merge key.
#
# Output mirrors 05_covariates/02_gpw_population.R's schema (GID_2, GID_0,
# year, pop_count, lnpop) so downstream panel-build code can swap sources
# without changes.
library(data.table)

cat("=== Load DHR's adm_2.csv (gid_2, year, lnpop) ===\n")
dhr <- fread("01_literature/dataverse_files/data/analysis/adm_2.csv",
             select = c("gid_0", "gid_2", "year", "lnpop"))
dhr <- unique(dhr[!is.na(lnpop)])
cat(sprintf("Rows: %d | regions: %d | countries: %d | years %d-%d\n",
    nrow(dhr), uniqueN(dhr$gid_2), uniqueN(dhr$gid_0), min(dhr$year), max(dhr$year)))

# lnpop = log(population in thousands) -- reconstruct pop_count (persons)
dhr[, pop_count := round(exp(lnpop) * 1000)]

setnames(dhr, c("gid_0", "gid_2"), c("GID_0", "GID_2"))

cat("\n=== Save ===\n")
fwrite(dhr[, .(GID_2, GID_0, year, pop_count, lnpop)],
       "data/processed/population_adm2_dhr.csv")
cat("Saved: data/processed/population_adm2_dhr.csv\n")
cat(sprintf("Sample lnpop range: %.2f to %.2f\n",
    min(dhr$lnpop, na.rm = TRUE), max(dhr$lnpop, na.rm = TRUE)))
