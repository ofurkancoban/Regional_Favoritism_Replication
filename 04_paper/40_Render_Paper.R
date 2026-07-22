# ==============================================================================
# File:          40_Render_Paper.R
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
# Description:   Renders the Quarto research paper and its Supplementary
#                Materials to PDF and HTML. paper.qmd and supplementary.qmd
#                live inside this package (04_paper/../paper/, i.e.
#                replication_package/paper/), which is the package's own
#                self-contained copy -- this package is the repository root
#                on GitHub, so there is no outside "main repository" to
#                render in place against anymore.
#
# Inputs:        ../paper/paper.qmd, ../paper/supplementary.qmd
# Outputs:       ../paper/paper.pdf, ../paper/paper.html,
#                ../paper/supplementary.pdf, ../paper/supplementary.html
# ==============================================================================

if (!requireNamespace("quarto", quietly = TRUE)) install.packages("quarto")

paper_dir <- here::here("..", "paper")
if (!dir.exists(paper_dir)) {
  stop("Could not find ../paper relative to this package. Set the working ",
       "directory to replication_package/ before running this script.")
}

old_wd <- getwd()
setwd(paper_dir)

message("Starting Quarto Render: Research Paper (PDF + HTML)...")
quarto::quarto_render(input = "paper.qmd", output_format = "elsevier-pdf")
quarto::quarto_render(input = "paper.qmd", output_format = "html")

message("Starting Quarto Render: Supplementary Materials (PDF + HTML)...")
quarto::quarto_render(input = "supplementary.qmd", output_format = "elsevier-pdf")
quarto::quarto_render(input = "supplementary.qmd", output_format = "html")

setwd(old_wd)

message("✓ Paper rendering complete. Check the '../paper/' directory.")
