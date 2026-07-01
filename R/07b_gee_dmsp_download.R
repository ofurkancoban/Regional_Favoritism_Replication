# R/07b_gee_dmsp_download.R
# Purpose: Monitor GEE export tasks and download completed CSVs from Drive.
# Run after 07a_gee_dmsp_submit.R. Polls every 60 seconds until all done.
# Downloads CSVs to data/processed/ntl/dmsp_by_country/ then assembles panel.

library(reticulate)
library(data.table)

source("R/utils/gee_helpers.R")
gee_initialize()

task_log <- "data/processed/ntl/dmsp_task_log.csv"
out_dir  <- "data/processed/ntl/dmsp_by_country"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

if (!file.exists(task_log)) stop("Task log not found. Run 07a_gee_dmsp_submit.R first.")
tlog <- data.table::fread(task_log)
tlog <- tlog[status == "submitted" & !is.na(task_id)]
cat(sprintf("Monitoring %d tasks (%d countries)...\n", nrow(tlog), uniqueN(tlog$iso3)))

# Setup Drive API + helper functions in one Python block
reticulate::py_run_string("
import ee, os, json, io, time
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request

CLIENT_ID     = ee.oauth.CLIENT_ID
CLIENT_SECRET = ee.oauth.CLIENT_SECRET
TOKEN_URI     = 'https://oauth2.googleapis.com/token'

creds_path = os.path.expanduser('~/.config/earthengine/credentials')
with open(creds_path) as f:
    raw = json.load(f)

_creds = Credentials(
    token         = None,
    refresh_token = raw['refresh_token'],
    token_uri     = TOKEN_URI,
    client_id     = CLIENT_ID,
    client_secret = CLIENT_SECRET,
    scopes        = ['https://www.googleapis.com/auth/drive',
                     'https://www.googleapis.com/auth/earthengine']
)
_creds.refresh(Request())
_drive = build('drive', 'v3', credentials=_creds)
print('Drive API ready')

def get_task_status(task_id):
    try:
        return ee.data.getTaskStatus([task_id])[0]['state']
    except:
        return 'UNKNOWN'

def download_from_drive(filename, dest_path):
    results = _drive.files().list(
        q=\"name='\" + filename + \".csv' and trashed=false\",
        fields='files(id, name)'
    ).execute()
    files = results.get('files', [])
    if not files:
        return False
    fid = files[0]['id']
    req = _drive.files().get_media(fileId=fid)
    buf = io.BytesIO()
    dl  = MediaIoBaseDownload(buf, req)
    done = False
    while not done:
        _, done = dl.next_chunk()
    with open(dest_path, 'wb') as f:
        f.write(buf.getvalue())
    return True
")

poll_interval <- 60

repeat {
  task_ids <- tlog$task_id
  descs    <- tlog$description
  iso3s    <- tlog$iso3

  statuses <- sapply(task_ids, function(tid) {
    reticulate::py_run_string(sprintf("_st = get_task_status('%s')", tid))
    reticulate::py$`_st`
  })

  n_done    <- sum(statuses == "COMPLETED")
  n_failed  <- sum(statuses == "FAILED")
  n_running <- sum(statuses %in% c("RUNNING", "READY", "UNSUBMITTED"))
  n_total   <- length(statuses)

  cat(sprintf("\r[%s] COMPLETED: %d | RUNNING: %d | FAILED: %d | TOTAL: %d",
              format(Sys.time(), "%H:%M:%S"), n_done, n_running, n_failed, n_total))

  # Download completed tasks not yet on disk
  for (i in seq_along(task_ids)) {
    if (statuses[i] != "COMPLETED") next
    is_chunk <- grepl("_\\d{3}$", descs[i])
    dest <- if (is_chunk) {
      file.path(out_dir, paste0(descs[i], ".csv"))
    } else {
      file.path(out_dir, paste0(iso3s[i], "_dmsp.csv"))
    }
    if (file.exists(dest)) next
    reticulate::py_run_string(sprintf(
      "_dl_ok = download_from_drive('%s', '%s')", descs[i], dest
    ))
    if (isTRUE(reticulate::py$`_dl_ok`)) {
      cat(sprintf("\n  Downloaded: %s\n", descs[i]))
    }
  }

  if (n_running == 0) break
  Sys.sleep(poll_interval)
}

cat("\n\nAll tasks finished.\n")
cat(sprintf("CSVs on disk: %d\n", length(list.files(out_dir, "\\.csv$"))))

if (sum(statuses == "FAILED") > 0) {
  cat("Failed:", paste(iso3s[statuses == "FAILED"], collapse = ", "), "\n")
}

# Assemble global panel
cat("\nAssembling global panel...\n")
csv_files <- list.files(out_dir, pattern = "\\.csv$", full.names = TRUE)
panel <- data.table::rbindlist(lapply(csv_files, data.table::fread), fill = TRUE)
data.table::fwrite(panel, "data/processed/ntl/dmsp_global_panel.csv")
cat(sprintf("Panel: %d rows | %d countries | years %d-%d\n",
    nrow(panel), uniqueN(panel$iso3),
    min(panel$year, na.rm = TRUE), max(panel$year, na.rm = TRUE)))
