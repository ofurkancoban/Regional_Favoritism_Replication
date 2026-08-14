# R/24_gee_download_dmsp_raster.R
# Purpose: Pull completed raw DMSP raster exports (GeoTIFFs, possibly sharded
# by GEE into multiple files per year) from Google Drive folder
# 'GEE_DMSP_Raw_Global' to local disk. Run manually, on demand -- not part
# of any automatic/looping process. Skips files already present locally.

library(reticulate)
library(data.table)

source("R/utils/gee_helpers.R")
gee_initialize()

drive_folder <- "GEE_DMSP_Raw_Global"
out_dir      <- "data/raw/dmsp_raster_global"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

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

def list_drive_folder_files(folder_name, name_prefix):
    q_folder = _drive.files().list(
        q=\"name='\" + folder_name + \"' and mimeType='application/vnd.google-apps.folder' and trashed=false\",
        fields='files(id, name)'
    ).execute()
    folders = q_folder.get('files', [])
    if not folders:
        return []
    folder_id = folders[0]['id']
    files = []
    page_token = None
    while True:
        resp = _drive.files().list(
            q=\"'\" + folder_id + \"' in parents and name contains '\" + name_prefix + \"' and trashed=false\",
            fields='nextPageToken, files(id, name, size)',
            pageToken=page_token
        ).execute()
        files.extend(resp.get('files', []))
        page_token = resp.get('nextPageToken')
        if not page_token:
            break
    return files

def download_file(file_id, dest_path):
    req = _drive.files().get_media(fileId=file_id)
    buf = io.BytesIO()
    dl  = MediaIoBaseDownload(buf, req)
    done = False
    while not done:
        _, done = dl.next_chunk()
    with open(dest_path, 'wb') as f:
        f.write(buf.getvalue())
")

reticulate::py_run_string(sprintf(
  "_files = list_drive_folder_files('%s', 'dmsp_stable_')", drive_folder
))
files <- reticulate::py$`_files`
cat(sprintf("Found %d file(s) in Drive folder '%s'.\n", length(files), drive_folder))

if (length(files) == 0) {
  cat("Nothing to download yet -- check R/23_gee_monitor_dmsp_raster.R for export status.\n")
} else {
  n_downloaded <- 0L
  n_skipped    <- 0L
  for (f in files) {
    dest <- file.path(out_dir, f$name)
    if (file.exists(dest)) {
      n_skipped <- n_skipped + 1L
      next
    }
    cat(sprintf("Downloading %s ...\n", f$name))
    reticulate::py_run_string(sprintf(
      "download_file('%s', '%s')", f$id, dest
    ))
    n_downloaded <- n_downloaded + 1L
    cat(sprintf("  done: %s\n", dest))
  }
  cat(sprintf("\nDownloaded: %d | Already local (skipped): %d | Total in Drive: %d\n",
      n_downloaded, n_skipped, length(files)))
  cat(sprintf("Local raw raster dir: %s\n", out_dir))
}
