# R/08b_bhs_chunk3_download.R -- monitor and download BHS features 21-30

library(reticulate)
library(data.table)

source("R/utils/gee_helpers.R")
gee_initialize()

out_dir  <- "data/processed/ntl/viirs_by_country"
task_log <- "data/processed/ntl/viirs_task_log.csv"

tlog <- data.table::fread(task_log)
bhs3 <- tlog[grepl("viirs_BHS_3f", description) & status == "submitted"]
cat(sprintf("Monitoring %d BHS chunk3 tasks...\n", nrow(bhs3)))

reticulate::py_run_string("
import ee, os, json, io
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request

CLIENT_ID     = ee.oauth.CLIENT_ID
CLIENT_SECRET = ee.oauth.CLIENT_SECRET
TOKEN_URI     = 'https://oauth2.googleapis.com/token'

with open(os.path.expanduser('~/.config/earthengine/credentials')) as f:
    raw = json.load(f)

_creds = Credentials(
    token=None, refresh_token=raw['refresh_token'],
    token_uri=TOKEN_URI, client_id=CLIENT_ID, client_secret=CLIENT_SECRET,
    scopes=['https://www.googleapis.com/auth/drive',
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

repeat {
  statuses <- sapply(bhs3$task_id, function(tid) {
    reticulate::py_run_string(sprintf("_st = get_task_status('%s')", tid))
    reticulate::py$`_st`
  })

  n_done    <- sum(statuses == "COMPLETED")
  n_running <- sum(statuses %in% c("RUNNING", "READY", "UNSUBMITTED"))
  cat(sprintf("[%s] COMPLETED: %d | RUNNING: %d | TOTAL: %d\n",
              format(Sys.time(), "%H:%M:%S"), n_done, n_running, nrow(bhs3)))

  for (i in seq_along(bhs3$task_id)) {
    if (statuses[i] != "COMPLETED") next
    dest <- file.path(out_dir, paste0(bhs3$description[i], ".csv"))
    if (file.exists(dest)) next
    reticulate::py_run_string(sprintf("_dl_ok = download_from_drive('%s', '%s')",
                                      bhs3$description[i], dest))
    if (isTRUE(reticulate::py$`_dl_ok`))
      cat(sprintf("  Downloaded: %s\n", bhs3$description[i]))
  }

  if (n_running == 0) break
  Sys.sleep(60)
}

cat("\nDone. Merging BHS files...\n")
bhs_files <- list.files(out_dir, pattern = "viirs_BHS", full.names = TRUE)
bhs_panel <- data.table::rbindlist(lapply(bhs_files, data.table::fread), fill = TRUE)
cat(sprintf("BHS rows: %d | features: %d | years: %d-%d\n",
    nrow(bhs_panel), uniqueN(bhs_panel$region_id),
    min(bhs_panel$year), max(bhs_panel$year)))
