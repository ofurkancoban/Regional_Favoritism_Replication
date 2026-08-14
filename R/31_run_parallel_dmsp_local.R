# R/31_run_parallel_dmsp_local.R
# Launches R/30_local_terra_dmsp_grid.R across multiple background processes,
# each handling a disjoint subset of years, since years are fully independent
# (separate raw raster files, separate per-year output csv). Machine has 10
# CPU cores; splitting 22 years into N_BATCHES batches gives near-linear
# wall-clock speedup over a single-process year loop.
#
# Usage: Rscript R/31_run_parallel_dmsp_local.R <resolution_km> [n_batches]

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript R/31_run_parallel_dmsp_local.R <resolution_km> [n_batches]")
RES_KM <- as.integer(args[1])
N_BATCHES <- if (length(args) >= 2) as.integer(args[2]) else 8L

years <- c(1992:2013)
batches <- split(years, cut(seq_along(years), N_BATCHES, labels = FALSE))

log_dir <- sprintf("data/processed/ntl/grid_%dkm_dmsp_local_logs", RES_KM)
dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)

pids <- integer(0)
for (i in seq_along(batches)) {
  yr_arg <- paste(batches[[i]], collapse = ",")
  log_file <- file.path(log_dir, sprintf("batch_%02d.log", i))
  cmd <- sprintf(
    "nohup Rscript R/30_local_terra_dmsp_grid.R %d %s > %s 2>&1 &",
    RES_KM, yr_arg, log_file
  )
  system(cmd)
  cat(sprintf("Batch %d launched: years %s -> %s\n", i, yr_arg, log_file))
}

cat("\nAll batches launched. Panel will auto-assemble once every year's csv exists\n")
cat("(re-run R/30_local_terra_dmsp_grid.R once more after all batches finish to trigger assembly).\n")
