# R/utils/gee_helpers.R
# Purpose: helper functions for Google Earth Engine access via reticulate.
#
# SETUP (one-time per machine):
#   1. pip install earthengine-api
#   2. Run gee_authenticate() once -- opens browser for Google login
#   3. Copy your GEE cloud project ID into .env: GEE_PROJECT=your-project-id
#   4. Call gee_initialize() at the start of each script

# Load GEE_PROJECT from .env if dotenv package is available, else use Sys.getenv
.load_env <- function() {
  env_file <- file.path(getwd(), ".env")
  if (!file.exists(env_file)) return(invisible(NULL))
  lines <- readLines(env_file, warn = FALSE)
  lines <- lines[grepl("^[A-Z_]+=", lines)]
  for (ln in lines) {
    parts <- strsplit(ln, "=", fixed = TRUE)[[1]]
    if (length(parts) >= 2) {
      key <- trimws(parts[1])
      val <- trimws(paste(parts[-1], collapse = "="))
      val <- gsub('^"|"$|^\'|\'$', "", val)
      if (Sys.getenv(key) == "") do.call(Sys.setenv, stats::setNames(list(val), key))
    }
  }
}

# One-time OAuth authentication (opens browser).
# Stores credentials in ~/.config/earthengine/credentials (never in repo).
gee_authenticate <- function() {
  reticulate::py_run_string("import ee; ee.Authenticate()")
  message("Authentication complete. Credentials stored in ~/.config/earthengine/")
}

# Initialize GEE. Reads project from GEE_PROJECT env var (set in .env).
gee_initialize <- function(project = NULL) {
  .load_env()
  if (is.null(project)) project <- Sys.getenv("GEE_PROJECT")
  if (project == "" || project == "your-gee-project-id") {
    stop(
      "GEE project not set.\n",
      "Add your project ID to .env:\n",
      "  GEE_PROJECT=your-actual-project-id\n",
      "Or pass it directly: gee_initialize('your-project-id')"
    )
  }
  reticulate::py_run_string(paste0(
    "import ee; ee.Initialize(project='", project, "')"
  ))
  message("GEE initialized: ", project)
}

gee_hello <- function() {
  result <- reticulate::py_eval("ee.String('GEE OK').getInfo()")
  message(result)
  invisible(result)
}

# Convert sf object to GEE FeatureCollection via in-memory GeoJSON parsing.
sf_to_ee_fc <- function(sf_obj) {
  tmp <- tempfile(fileext = ".geojson")
  on.exit(unlink(tmp))
  sf::st_write(sf_obj, tmp, driver = "GeoJSON", quiet = TRUE)
  gjson <- paste(readLines(tmp, warn = FALSE), collapse = "")
  reticulate::py_run_string(paste0(
    "import json, ee\n",
    "fc = ee.FeatureCollection(json.loads('",
    gsub("'", "\\'", gjson, fixed = TRUE),
    "'))"
  ))
  reticulate::py$fc
}

# Zonal mean for an ee.Image over a FeatureCollection; returns data.frame.
zonal_mean <- function(image, fc, scale = 1000) {
  ee     <- reticulate::import("ee")
  result <- image$reduceRegions(
    collection = fc,
    reducer    = ee$Reducer$mean(),
    scale      = as.integer(scale)
  )
  feats <- result$getInfo()[["features"]]
  do.call(rbind, lapply(feats, function(f) {
    as.data.frame(f[["properties"]], stringsAsFactors = FALSE)
  }))
}
