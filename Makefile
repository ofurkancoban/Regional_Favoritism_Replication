# Makefile for the Regional Favoritism replication package
# ------------------------------------------------------------------------------
# Orchestrates the 41-stage research pipeline. Requirements: R, Quarto, renv.
# Stage 01 (raw data download) is not wired into any target here: several
# sources (PLAD, Archigos, G-Econ, GPWv4, WVS/EVS) are manual,
# registration-gated downloads with no API -- see README.md, "Raw data" for
# the exact list.
#
# Two analysis phases after preprocessing: `core` builds the tables the
# main paper (paper.qmd) uses; `supplementary` builds the additional
# tables supplementary.qmd uses (Table III, V, VI, VII), which the main
# paper does not need. `render` renders both documents together (Stage 40
# covers paper.qmd and supplementary.qmd in one script), so
# `make supplementary` should run before `make paper` if supplementary.pdf's
# own tables need to be current.
#
# Figures 1 and 2 (Stages 31-32) are NOT part of `core`: they need raw
# inputs (GADM 3.6, and DMSP rasters kept past their preprocess-stage
# lifetime) that `make preprocess` doesn't provide. Their outputs ship
# pre-built in 04_paper/img/; run 02_scripts/03a_analysis_core/31_figure1_goh.R
# and 32_figure2_erdogan_units.R directly and manually if you need to
# regenerate a figure from source.

RSCRIPT = Rscript

.PHONY: help all init preprocess core supplementary analysis render paper presentation clean

help:
	@echo "Available commands:"
	@echo "  make init          : Install every R package listed in renv.lock into"
	@echo "                       your regular R library (see README.md, 'Package"
	@echo "                       management' for why this isn't renv::restore())"
	@echo "  make preprocess    : Run stages 01-21 (download, crosswalks, geometry, extraction, panel)"
	@echo "  make core          : Run stages 22-30 (main paper's tables, extension)"
	@echo "  make supplementary : Run stages 33-39 (supplementary.qmd's Table III, V, VI, VII)"
	@echo "  make paper         : Render the research paper + supplementary materials (PDF)"
	@echo "  make presentation  : Render the Reveal.js presentation (HTML)"
	@echo "  make render        : make paper + make presentation"
	@echo "  make all           : Run preprocess + core + supplementary + render (Stage 01 excluded, see README)"
	@echo "  make clean         : Remove temporary build artifacts and logs"

all: init preprocess core supplementary render

init:
	$(RSCRIPT) -e "if (!requireNamespace('renv', quietly = TRUE)) install.packages('renv'); renv::restore(library = .libPaths()[1])"

preprocess:
	@echo "Running Preprocessing Stages (01-21)..."
	$(RSCRIPT) 02_scripts/01_setup/setup_environment.R --stage=preprocess

core:
	@echo "Running Core Analysis Stages (22-30): main paper tables..."
	$(RSCRIPT) 02_scripts/01_setup/setup_environment.R --stage=core

supplementary:
	@echo "Running Supplementary Analysis Stages (33-39): Table III, V, VI, VII..."
	$(RSCRIPT) 02_scripts/01_setup/setup_environment.R --stage=supplementary

# Retained as an alias for `core` for backward compatibility with the
# previous single-phase analysis target.
analysis: core

render: paper presentation

paper:
	@echo "Rendering Research Paper + Supplementary Materials..."
	$(RSCRIPT) 04_paper/40_Render_Paper.R

presentation:
	@echo "Rendering Presentation..."
	$(RSCRIPT) 05_presentation/41_Render_Presentation.R

clean:
	@echo "Cleaning up temporary files..."
	find . -type d -name "*_cache" -exec rm -rf {} +
	find . -type d -name "*_files" -exec rm -rf {} +
	find . -type f -name "*.log" -delete
	find . -type f -name "*.aux" -delete
	find . -type f -name "*.out" -delete
	@echo "Cleanup complete."
