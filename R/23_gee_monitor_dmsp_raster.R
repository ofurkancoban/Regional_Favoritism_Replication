# R/23_gee_monitor_dmsp_raster.R
# Purpose: Poll GEE task status for the raw DMSP raster exports submitted by
# R/22_gee_export_dmsp_raster_submit.R and print live progress to the
# console/log. Read-only monitor: does not download, does not resubmit.
# Exits automatically once every task reaches a terminal state
# (COMPLETED/FAILED/CANCELLED) -- it does not loop again after that.

library(reticulate)
library(data.table)

source("R/utils/gee_helpers.R")
gee_initialize()

task_log <- "data/processed/ntl/dmsp_raster_task_log.csv"
if (!file.exists(task_log)) stop("Task log not found. Run R/22_gee_export_dmsp_raster_submit.R first.")

tlog <- data.table::fread(task_log)
tlog <- tlog[status == "submitted" & !is.na(task_id)]
cat(sprintf("Monitoring %d raster export tasks (years %d-%d)...\n\n",
    nrow(tlog), min(tlog$year), max(tlog$year)))

reticulate::py_run_string("
import ee

def get_task_status(task_id):
    try:
        return ee.data.getTaskStatus([task_id])[0]['state']
    except Exception:
        return 'UNKNOWN'
")

poll_interval <- 60

repeat {
  statuses <- sapply(tlog$task_id, function(tid) {
    reticulate::py_run_string(sprintf("_st = get_task_status('%s')", tid))
    reticulate::py$`_st`
  })

  n_done    <- sum(statuses == "COMPLETED")
  n_failed  <- sum(statuses %in% c("FAILED", "CANCELLED"))
  n_running <- sum(statuses %in% c("RUNNING", "READY", "UNSUBMITTED"))

  cat(sprintf("[%s] COMPLETED: %d | RUNNING: %d | FAILED: %d | TOTAL: %d\n",
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"), n_done, n_running, n_failed, nrow(tlog)))
  for (i in seq_len(nrow(tlog))) {
    cat(sprintf("   year %d  %-12s  %s\n", tlog$year[i], statuses[i], tlog$description[i]))
  }
  cat("\n")

  if (n_running == 0) break
  Sys.sleep(poll_interval)
}

cat("All tasks reached a terminal state. Monitor exiting (no restart).\n")
if (any(statuses %in% c("FAILED", "CANCELLED")))
  cat("Failed/cancelled years:", paste(tlog$year[statuses %in% c("FAILED", "CANCELLED")], collapse = ", "), "\n")
cat("Files are sitting in Google Drive folder 'GEE_DMSP_Raw_Global'.\n")
cat("Run R/24_gee_download_dmsp_raster.R whenever you want to pull them to local disk.\n")
