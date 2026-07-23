# ==============================================================================
# File:          utils.R
# Project:       Regional Favoritism: A Replication and Extension of
#                Hodler & Raschky (2014)
# Author:        Ömer Furkan Çoban
#
# University:    Carl von Ossietzky University of Oldenburg
# Department:    Applied Economics and Data Science
# Course:        Applied Econometrics Using GIS Techniques
# Semester:      SoSe 2026
# Lecturer:      Prof. Dr. Erkan Gören
#
# Category:      Tools & Utilities
#
# Description:   Centralized helper functions shared by every regression
#                table script in both 02_scripts/03a_analysis_core/ and
#                02_scripts/03b_analysis_supplementary/: the project's
#                within-R2 convention, significance stars, and a single-
#                coefficient row extractor. Consolidated here from near-
#                identical copies that had accumulated across the
#                individual table scripts during development.
#
# Inputs:        fixest model objects and their estimation data
# Outputs:       Formatted coefficient rows and within-R2 statistics
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))

#' Significance stars at the 1%/5%/10% levels (HR 2014's own convention)
#' @param pv Numeric p-value.
sig_of <- function(pv) {
  ifelse(pv < 0.01, "***", ifelse(pv < 0.05, "**", ifelse(pv < 0.10, "*", "")))
}

#' Ensure a shipped, gzip-compressed file is available in its expected
#' plain form, decompressing it once if needed. Several large binary
#' formats this package ships (.gpkg vector geometry, in particular the
#' four grid_cells_*km.gpkg files) cannot be streamed from gzip directly
#' by their own readers (sf::st_read() has no gzip support, unlike
#' data.table::fread()'s in-stream CSV/TSV handling), so the plain file
#' has to exist on disk before reading. Ships as `<path>.gz` (tracked via
#' Git LFS), decompresses to `<path>` the first time it's needed, and
#' leaves the plain file there for every later stage/run in the same
#' checkout (`.gitignore`d, so it isn't re-committed).
#'
#' @param path The expected plain (uncompressed) file path.
ensure_decompressed <- function(path) {
  if (file.exists(path)) {
    return(invisible(path))
  }
  gz_path <- paste0(path, ".gz")
  if (!file.exists(gz_path)) {
    stop(sprintf("Neither %s nor %s found.", path, gz_path), call. = FALSE)
  }
  message(sprintf("Decompressing %s (one-time, ~10-15s)...", basename(gz_path)))
  R.utils::gunzip(gz_path, destname = path, remove = FALSE, overwrite = TRUE)
  invisible(path)
}

#' Check that a manually-downloaded raw input file exists; if not, stop
#' with a clear, actionable message (what's missing, where to get it, and
#' where to put it) instead of letting the failure surface later as an
#' opaque fread()/read_dta() error deep inside a stage script. Several of
#' this package's raw sources (PLAD, Archigos, G-Econ, GPWv3/v4, GHS-POP,
#' WVS/EVS) have no download API and must be fetched by hand -- see
#' README.md, "Raw data that cannot be downloaded automatically" -- so
#' every stage that reads one of them should call this first.
#'
#' @param path The expected local file path (already here::here()-resolved).
#' @param name Human-readable dataset name, e.g. "PLAD (Political Leaders'
#'   Affiliation Database), April 2024 release".
#' @param url Where to get it.
#' @param registration One-line registration note, e.g. "Free, academic
#'   use" or "Free, NASA Earthdata login".
#' @param note Optional extra instructions (exactly which file to
#'   download, any renaming needed, an alternate/optional source).
require_input_file <- function(path, name, url, registration = "Free", note = NULL) {
  if (file.exists(path)) {
    return(invisible(TRUE))
  }
  msg <- c(
    "",
    strrep("=", 78),
    sprintf("MISSING RAW DATA: %s", name),
    strrep("=", 78),
    sprintf("Expected at:   %s", path),
    sprintf("Download from: %s", url),
    sprintf("Registration:  %s", registration),
    if (!is.null(note)) sprintf("Note:          %s", note),
    "",
    "This file cannot be downloaded automatically by this pipeline. See",
    "README.md, 'Raw data that cannot be downloaded automatically', for",
    "the complete list and where each one goes.",
    strrep("=", 78),
    ""
  )
  stop(paste(msg, collapse = "\n"), call. = FALSE)
}

#' Within R2, HR/Stata xtreg-fe convention: 1 - deviance(m) / deviance(a
#' null model with only the region fixed effect). NOT fixest::r2(m, "wr2"),
#' which nets out every fixed effect (region AND country-year) from both
#' the model and the null, and is mechanically near zero for a single
#' binary regressor once the much larger country-year FE set already
#' explains most of the variance.
#' @param m A fitted fixest model.
#' @param dd The exact data.table/data.frame used to fit `m`.
#' @param yvar Character. Name of the dependent variable in `dd`.
#' @param unit Character. Name of the region-fixed-effect column in `dd`.
wr2 <- function(m, dd, yvar, unit = "gid_2") {
  null_dev <- {
    f <- stats::as.formula(sprintf("%s ~ 1 | %s", yvar, unit))
    stats::deviance(fixest::feols(f, data = dd))
  }
  1 - stats::deviance(m) / null_dev
}

#' Export a data.frame/data.table as a styled, browsable HTML table.
#'
#' A lightweight, independent HTML view of each final table this package
#' produces -- NOT a copy of paper.qmd's own kableExtra/LaTeX formatting
#' (side-by-side Orig./Repl. columns, multi-line coefficient cells, etc.),
#' which stays defined only in paper.qmd itself to avoid two versions of
#' the same layout logic drifting apart. This is a simpler, standalone
#' table meant for browsing a stage's output without opening the PDF.
#'
#' @param dt A data.frame/data.table to render.
#' @param title Table title, shown above the table.
#' @param subtitle Optional subtitle/caption, shown under the title.
#' @param file_name Output filename (no path), written under
#'   03_results/tables/html/.
export_html_table <- function(dt, title, file_name, subtitle = NULL) {
  out_dir <- here::here("03_results", "tables", "html")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  out_path <- file.path(out_dir, file_name)

  gt_tbl <- gt::gt(as.data.frame(dt)) |>
    gt::tab_header(title = gt::md(paste0("**", title, "**")),
                    subtitle = subtitle) |>
    gt::tab_options(
      table.font.size = gt::px(13),
      heading.title.font.size = gt::px(17),
      column_labels.font.weight = "bold",
      table.border.top.width = gt::px(2),
      table.border.top.color = "black",
      table.border.bottom.width = gt::px(2),
      table.border.bottom.color = "black",
      column_labels.border.bottom.width = gt::px(1.5),
      column_labels.border.bottom.color = "black"
    ) |>
    gt::opt_row_striping()

  gt::gtsave(gt_tbl, out_path)
  message(sprintf("HTML table saved: %s", out_path))
  invisible(out_path)
}

#' Build a full replication table as gt/HTML, mirroring paper.qmd's own
#' Orig./Repl. side-by-side layout (numbered column spanners, a DV-name
#' group spanner, shaded alternating columns, multi-line coefficient
#' cells, and a footer summary panel) rather than the flatter one-column
#' view the earlier version of this helper produced.
#'
#' @param coefs data.table with columns row, col, b, se, sig, source
#'   ("hr"/"own"), one row per coefficient cell -- the schema every
#'   table*_full*.csv this package writes already uses.
#' @param row_order Character vector of `coefs$row` values, in the order
#'   they should appear (top to bottom).
#' @param row_labels Named character vector: row_order value -> HTML
#'   display label (e.g. c("Leader_t-1" = "Leader<sub>ict-1</sub>")).
#' @param n_cols Integer number of numbered columns, (1) through (n_cols).
#' @param dv_spans Named integer vector: DV label -> how many consecutive
#'   numbered columns it spans, summing to n_cols (e.g.
#'   c(Light = 5, Light0 = 1, Lightpc = 1) for the extension table).
#' @param shaded_cols Integer vector of numbered columns (1-indexed) to
#'   shade, matching paper.qmd's own alternating pattern.
#' @param footer_rows A named list of extra footer rows to place under the
#'   coefficient block, before Region FE / Country-Year FE. Each element
#'   is a character vector of length n_cols (one value per numbered
#'   column, shown under both Orig. and Repl. -- e.g. "Units of
#'   observation" in Table IV) OR a data.table with col/value pairs per
#'   source (for Number of regions / Observations / Within R2, which
#'   differ between Orig. and Repl.). Pass `NULL` to skip.
#' @param region_fe Character vector of length n_cols, "Yes"/"No" per
#'   numbered column (Table II's Column 5 has no region FE).
#' @param single_panel If TRUE, only "own" values are shown (one column
#'   per numbered column, not an Orig./Repl. pair) -- used for the
#'   extension table, which has no published HR 2014 counterpart.
#' @param title,subtitle,notes,file_name As in export_html_table().
build_full_table_gt <- function(coefs, row_order, row_labels, n_cols,
                                 dv_spans, shaded_cols, footer_rows,
                                 region_fe, single_panel = FALSE,
                                 title, subtitle, notes, file_name) {
  sources <- if (single_panel) "own" else c("hr", "own")
  col_id <- function(co, src) sprintf("c%d_%s", co, src)

  fmt_coef <- function(row_key, co, src) {
    r <- coefs[coefs$row == row_key & coefs$col == co & coefs$source == src, ]
    if (nrow(r) == 0) return("")
    sprintf(
      "%.3f%s<br><span style='color:#666;font-size:0.85em'>(%.3f)</span>",
      r$b, r$sig, r$se
    )
  }

  # --- Coefficient body -------------------------------------------------
  # Cell values are built as plain strings containing raw HTML (<br>,
  # <sub>, <span>...) here, NOT wrapped in gt::html() at this point: gt's
  # "html"-classed objects only survive if they reach gt::gt() directly
  # inside the data.frame gt() is called on. Once passed through
  # do.call(rbind, lapply(..., as.data.frame)) below, as.data.frame.list()
  # silently drops that S3 class and the cell reverts to plain character
  # -- which is why the tags rendered as literal text rather than HTML
  # the first time this was written. Marking the columns as HTML happens
  # later instead, via gt::fmt(..., fns = gt::html) on the assembled gt
  # table, which applies at render time and isn't subject to this.
  body <- lapply(row_order, function(rk) {
    row <- lapply(seq_len(n_cols), function(co) {
      vals <- lapply(sources, function(src) fmt_coef(rk, co, src))
      names(vals) <- col_id(co, sources)
      vals
    })
    c(list(Variable = row_labels[[rk]]), do.call(c, row))
  })
  body_df <- do.call(rbind, lapply(body, as.data.frame, stringsAsFactors = FALSE))

  # --- Footer summary panel ----------------------------------------------
  footer_df_rows <- list()
  for (label in names(footer_rows)) {
    spec <- footer_rows[[label]]
    row <- list(Variable = label)
    if (is.character(spec)) {
      # Same value under both Orig. and Repl. (e.g. "Units of observation")
      for (co in seq_len(n_cols)) {
        for (src in sources) row[[col_id(co, src)]] <- spec[co]
      }
    } else {
      # data.table(col, hr, own) -- differs by source
      for (co in seq_len(n_cols)) {
        for (src in sources) {
          v <- spec[spec$col == co, ][[src]]
          row[[col_id(co, src)]] <- if (length(v) == 0) "" else v
        }
      }
    }
    footer_df_rows[[length(footer_df_rows) + 1]] <- row
  }
  fe_row <- list(Variable = "Region FE")
  cy_row <- list(Variable = "Country-Year FE")
  for (co in seq_len(n_cols)) {
    for (src in sources) {
      fe_row[[col_id(co, src)]] <- region_fe[co]
      cy_row[[col_id(co, src)]] <- "Yes"
    }
  }
  footer_df_rows[[length(footer_df_rows) + 1]] <- fe_row
  footer_df_rows[[length(footer_df_rows) + 1]] <- cy_row
  footer_df <- do.call(rbind, lapply(footer_df_rows, as.data.frame, stringsAsFactors = FALSE))

  full_df <- rbind(body_df, footer_df)
  all_cell_cols <- c("Variable", unlist(lapply(seq_len(n_cols), function(co) {
    vapply(sources, function(s) col_id(co, s), character(1), USE.NAMES = FALSE)
  })))

  gt_tbl <- gt::gt(full_df) |>
    gt::tab_header(title = gt::md(paste0("**", title, "**")), subtitle = subtitle) |>
    gt::cols_label(Variable = "") |>
    # Marks every cell's plain-string content as pre-rendered HTML at
    # format time -- see the comment above the body/footer construction
    # for why this can't just be gt::html() on the raw data instead.
    gt::fmt(columns = all_cell_cols, fns = function(x) lapply(x, gt::html))

  # Numbered-column spanners, e.g. "(1)" over c1_hr/c1_own.
  for (co in seq_len(n_cols)) {
    cols_here <- vapply(sources, function(s) col_id(co, s), character(1), USE.NAMES = FALSE)
    sub_labels <- stats::setNames(
      as.list(if (single_panel) "Estimate" else c("Orig.", "Repl.")),
      cols_here
    )
    gt_tbl <- gt_tbl |>
      gt::tab_spanner(label = sprintf("(%d)", co), columns = cols_here, level = 1) |>
      gt::cols_label(.list = sub_labels)
  }

  # DV-name group spanner, one level up, spanning several numbered columns.
  co_start <- 1
  for (dv in names(dv_spans)) {
    n <- dv_spans[[dv]]
    cols_here <- unlist(lapply(co_start:(co_start + n - 1), function(co) {
      vapply(sources, function(s) col_id(co, s), character(1), USE.NAMES = FALSE)
    }))
    gt_tbl <- gt_tbl |> gt::tab_spanner(label = gt::html(dv), columns = cols_here, level = 2)
    co_start <- co_start + n
  }

  # Shade the specified numbered columns, both Orig. and Repl. sub-columns.
  shade_cols_ids <- unlist(lapply(shaded_cols, function(co) vapply(sources, function(s) col_id(co, s), character(1), USE.NAMES = FALSE)))
  if (length(shade_cols_ids) > 0) {
    gt_tbl <- gt_tbl |>
      gt::tab_style(
        style = gt::cell_fill(color = "#f2f2f2"),
        locations = gt::cells_body(columns = shade_cols_ids)
      ) |>
      gt::tab_style(
        style = gt::cell_fill(color = "#f2f2f2"),
        locations = gt::cells_column_spanners(spanners = sprintf("(%d)", shaded_cols))
      )
  }

  # Rule between the coefficient block and the footer summary panel.
  gt_tbl <- gt_tbl |>
    gt::tab_style(
      style = gt::cell_borders(sides = "top", color = "black", weight = gt::px(1.5)),
      locations = gt::cells_body(rows = length(row_order) + 1)
    ) |>
    gt::tab_options(
      table.font.size = gt::px(12),
      heading.title.font.size = gt::px(17),
      column_labels.font.weight = "bold",
      table.border.top.width = gt::px(2),
      table.border.top.color = "black",
      table.border.bottom.width = gt::px(2),
      table.border.bottom.color = "black"
    )

  if (!is.null(notes)) {
    gt_tbl <- gt_tbl |> gt::tab_source_note(source_note = notes)
  }

  out_dir <- here::here("03_results", "tables", "html")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  out_path <- file.path(out_dir, file_name)
  gt::gtsave(gt_tbl, out_path)
  message(sprintf("HTML table saved: %s", out_path))
  invisible(out_path)
}

#' Extract one coefficient's estimate/SE/significance as a table row
#' @param m A fitted fixest model.
#' @param var Character. Coefficient name as it appears in `summary(m)$coeftable`.
#' @param col Integer. Table column number this row belongs to.
#' @param row_label Character. Row label for the assembled table.
extract_row <- function(m, var, col, row_label) {
  cft <- summary(m)$coeftable
  if (!var %in% rownames(cft)) return(NULL)
  data.table::data.table(
    row = row_label, col = col,
    b = cft[var, 1], se = cft[var, 2], sig = sig_of(cft[var, 4])
  )
}
