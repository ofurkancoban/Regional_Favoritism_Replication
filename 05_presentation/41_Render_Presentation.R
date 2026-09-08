# ==============================================================================
# File:          41_Render_Presentation.R
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
# Category:      Document Rendering
#
# Description:   Renders the Quarto Reveal.js presentation to HTML.
#                index.qmd lives alongside this script in 05_presentation/,
#                this package's own self-contained copy. The presentation is
#                entirely static (hardcoded numbers and pre-rendered images,
#                no live R chunks), so this step needs no upstream pipeline
#                stage to have run first.
#
# Inputs:        index.qmd (this directory)
# Outputs:       index.html (this directory)
# ==============================================================================

if (!requireNamespace("quarto", quietly = TRUE)) install.packages("quarto")

presentation_dir <- here::here("05_presentation")
if (!dir.exists(presentation_dir)) {
  stop("Could not find 05_presentation relative to this package. Set the ",
       "working directory to replication_package/ before running this script.")
}

old_wd <- getwd()
setwd(presentation_dir)

message("Starting Quarto Render: Presentation...")
quarto::quarto_render(input = "index.qmd")

setwd(old_wd)

message("✓ Presentation rendering complete. Check the '05_presentation/' directory.")
