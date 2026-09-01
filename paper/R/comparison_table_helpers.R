# Shared helpers for the supplementary tables (S2/S3/S4), reproducing the
# Orig./Repl. paired-column, \shortstack-cell design paper.qmd's tbl-table2
# and tbl-table4 use, so the supplementary tables read the same way as the
# main paper's rather than in the plain kable layout used before.

stars_from_p <- function(p) {
    if (is.na(p)) {
        return("")
    }
    if (p < 0.01) {
        "***"
    } else if (p < 0.05) {
        "**"
    } else if (p < 0.1) {
        "*"
    } else {
        ""
    }
}

#' A hardcoded HR 2014 coefficient, formatted as a two-line cell --
#' \shortstack for LaTeX, a <br>-separated span for HTML (paper.qmd's
#' own HTML table branches use the same markup, styled by .ptbl-se).
#' `triplet` is c(b, se, sig) or NULL when the authors' table does not
#' report that cell.
sstack_hr <- function(triplet) {
    if (is.null(triplet)) {
        return("")
    }
    b <- as.numeric(triplet[1])
    se <- as.numeric(triplet[2])
    sig <- triplet[3]
    if (knitr::is_html_output()) {
        sprintf('%.3f%s<br><span class="ptbl-se">(%.3f)</span>', b, sig, se)
    } else {
        sprintf("\\shortstack{%.3f%s\\\\(%.3f)}", b, sig, se)
    }
}

#' The same cell, pulled live from a fitted fixest model + coefficient name.
sstack_own <- function(model, term) {
    if (is.null(model)) {
        return("")
    }
    cf <- tryCatch(stats::coef(model)[term], error = function(e) NA)
    if (is.na(cf)) {
        return("")
    }
    se <- sqrt(diag(stats::vcov(model)))[term]
    p <- fixest::pvalue(model)[term]
    if (knitr::is_html_output()) {
        sprintf('%.3f%s<br><span class="ptbl-se">(%.3f)</span>', cf, stars_from_p(p), se)
    } else {
        sprintf("\\shortstack{%.3f%s\\\\(%.3f)}", cf, stars_from_p(p), se)
    }
}

#' Converts LaTeX math markup to real MathJax inline math instead of
#' hand-rolled <sub>/<sup> HTML: each $...$ segment becomes \\(...\\),
#' which quarto's HTML output already loads MathJax for (the same
#' engine that renders the main equation), so _c, _{ict-1}, ^2, \\times,
#' \\sim, \\circ etc. all typeset natively with no per-symbol HTML
#' translation needed, braced or not. \\% and \\& are LaTeX's own
#' escapes for literal characters rather than math, so those still
#' convert directly to plain %/&amp; instead of being wrapped.
latex_to_html <- function(x) {
    x <- gsub("\\$([^$]*)\\$", "\\\\(\\1\\)", x)
    x <- gsub("\\\\&", "&amp;", x)
    x <- gsub("\\\\%", "%", x)
    x
}

#' Render a body+footer matrix (first column = row label, remaining columns
#' alternating Orig./Repl. per specification column) in the main paper's
#' comparison-table style: two-level header (an optional variable-name
#' spanner row, then a "(1)".."(n)" column-number row), alternating shaded
#' spec-column pairs, a midrule before the footer block, resized to the
#' text width, and a footnote appended as unscaled plain text below.
render_comparison_table <- function(out, n_cols, col_headers,
                                     spanner_label = NULL,
                                     hline_before_foot = NULL,
                                     notes = NULL, font_size = 8) {
    n_data_cols <- 2 * n_cols
    shaded_pairs <- seq(2, n_cols, by = 2) # every other spec-column pair
    shaded_idx <- as.vector(sapply(shaded_pairs, function(i) c(2 * i - 1, 2 * i)))

    if (knitr::is_html_output()) {
        # `out`'s cells already carry HTML-formatted coefficients
        # (sstack_hr/sstack_own branch on is_html_output() themselves);
        # this only has to build the surrounding table, mirroring
        # paper.qmd's own hand-built .ptbl markup so both documents'
        # tables share one CSS design.
        thead <- "<tr><th></th>"
        if (!is.null(spanner_label)) {
            thead <- paste0(thead, paste0(sprintf(
                '<th colspan="2">%s</th>', vapply(spanner_label, latex_to_html, character(1))
            ), collapse = ""), "</tr><tr><th></th>")
        }
        thead <- paste0(
            thead,
            paste0(sprintf('<th colspan="2">%s</th>', col_headers), collapse = ""),
            "</tr><tr><th></th>",
            paste0(rep("<th>Orig.</th><th>Repl.</th>", n_cols), collapse = ""),
            "</tr>"
        )

        n_body <- if (!is.null(hline_before_foot)) hline_before_foot else nrow(out)
        row_html <- function(i, foot_first = FALSE) {
            cells <- vapply(seq_len(n_data_cols), function(j) {
                shade <- if (j %in% shaded_idx) ' class="ptbl-shade"' else ""
                sprintf("<td%s>%s</td>", shade, out[i, 1 + j])
            }, character(1))
            cls <- if (foot_first) ' class="ptbl-foot-first"' else ""
            sprintf("<tr%s><td>%s</td>%s</tr>", cls, latex_to_html(out[i, 1]), paste(cells, collapse = ""))
        }
        body_rows <- vapply(seq_len(n_body), row_html, character(1))
        foot_rows <- if (n_body < nrow(out)) {
            vapply((n_body + 1):nrow(out), function(i) row_html(i, foot_first = (i == n_body + 1)), character(1))
        } else {
            character(0)
        }

        notes_html <- if (!is.null(notes)) {
            paste0('<p class="ptbl-notes"><em>Notes.</em> ', latex_to_html(notes), "</p>")
        } else {
            ""
        }

        return(knitr::asis_output(paste0(
            '<div class="ptbl-wrap"><table class="ptbl"><thead>', thead, "</thead><tbody>",
            paste(body_rows, collapse = ""), paste(foot_rows, collapse = ""),
            "</tbody></table></div>", notes_html
        )))
    }

    col_type <- vapply(
        seq_len(n_data_cols),
        function(i) if (i %in% shaded_idx) ">{\\columncolor{gray!10}}c" else "c",
        character(1)
    )
    align <- c("l", col_type)

    tbl <- knitr::kable(
        out,
        format = "latex",
        linesep = "",
        align = align,
        escape = FALSE,
        row.names = FALSE,
        booktabs = TRUE
    )

    if (!is.null(spanner_label)) {
        span <- stats::setNames(rep(2, n_cols), spanner_label)
        tbl <- kableExtra::add_header_above(tbl, c(" " = 1, span), escape = FALSE)
    }
    col_span <- stats::setNames(rep(2, n_cols), col_headers)
    tbl <- kableExtra::add_header_above(tbl, c(" " = 1, col_span))

    if (!is.null(hline_before_foot)) {
        tbl <- kableExtra::row_spec(tbl, hline_before_foot, extra_latex_after = "\\midrule")
    }
    tbl <- kableExtra::kable_styling(tbl, font_size = font_size)

    tbl_attrs <- attributes(tbl)
    tbl <- sub(
        "\\begin{tabular}",
        paste0(
            "\\resizebox{\\ifdim\\width>\\linewidth\\linewidth\\else\\width\\fi}{!}{",
            "\\begingroup\\setlength{\\tabcolsep}{2.5pt}\\begin{tabular}"
        ),
        tbl,
        fixed = TRUE
    )
    tbl <- sub("\\end{tabular}", "\\end{tabular}\\endgroup}", tbl, fixed = TRUE)
    attributes(tbl) <- tbl_attrs

    if (!is.null(notes)) {
        notes_latex <- paste0(
            "\n\n\\vspace{2mm}\n\n\\begingroup\\footnotesize\\textit{Notes.} ",
            notes, "\\endgroup\n"
        )
        tbl_final <- paste0(tbl, notes_latex)
        attributes(tbl_final) <- attributes(tbl)
        return(tbl_final)
    }
    tbl
}
