# ==============================================================================
# File:          31_figure1_goh.R
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
# Category:      Figures
#
# Description:   Figure 1: G-Econ 4.0 gridded regional GDP alongside this project's own regional GDP re-aggregation, for Turkey and a global inset, with a Table II Column (8) trend panel.
#
# Inputs:        data/raw/gadm_4.1/, data/raw/dmsp_raster_eog_manual/, data/processed/analysis_panel.csv (repo root)
# Outputs:       paper/img/goh_combined_paper.pdf (repo root); copied to 03_results/figures/
# ==============================================================================

source(here::here("02_scripts", "02_data_preprocessing", "00_import.R"))
source(here::here("02_scripts", "04_tools", "utils.R"))

# `root` resolves to the main repository root (this package's parent
# directory), since the DMSP rasters and analysis panel this figure reads
# are too large to duplicate inside the package -- see README.md.
# REGIONAL_FAVORITISM_ROOT overrides this for a different layout.
root <- Sys.getenv("REGIONAL_FAVORITISM_ROOT", unset = here::here(".."))


# --- Print geometry -----------------------------------------------------------
# The paper's \linewidth measured from the compiled PDF is 447.4pt = 6.214in,
# and the figure is included at width=0.95\linewidth. Building the figure at
# exactly that final width means the scale factor in the paper is 1.0, so every
# font size below is a TRUE printed point size -- no hidden shrinking.
FIG_W <- 0.95 * 6.214            # 5.90 in, the on-page width
COL_UNITS <- c(1, 1, 1, 1, 0.40) # 4 maps + a compact legend column
PANEL_MARGIN_IN <- 2 * 0.75 / 72 # 0.75pt each side: a hairline gap between maps
MAP_IMG_W <- FIG_W / sum(COL_UNITS) - PANEL_MARGIN_IN   # ~1.31 in per map
# The map panels are square (aspect.ratio = 1), so they are sized by whichever
# is smaller: the column width or the available panel height. Give the row a
# generous title allowance so WIDTH is the binding constraint -- otherwise the
# squares shrink to fit the height and leave white gaps between the maps.
TITLE_H <- 0.64
MAPS_ROW_H <- MAP_IMG_W + TITLE_H
TREND_H <- 2.45
FIG_H <- MAPS_ROW_H + TREND_H

# Latin Modern Roman font directory: TinyTeX ships it under
# texmf-dist/fonts/opentype/public/lm. REGIONAL_FAVORITISM_LM_DIR overrides
# the autodetected TinyTeX root (tinytex::tinytex_root()) for a non-TinyTeX
# LaTeX install.
lm_dir <- Sys.getenv("REGIONAL_FAVORITISM_LM_DIR", unset = NA)
if (is.na(lm_dir)) {
  tinytex_root <- tryCatch(tinytex::tinytex_root(), error = function(e) NA)
  if (is.na(tinytex_root)) {
    stop(
      "Could not locate a TinyTeX installation to find Latin Modern Roman.\n",
      "Install TinyTeX (tinytex::install_tinytex()) or set the\n",
      "REGIONAL_FAVORITISM_LM_DIR environment variable to the directory\n",
      "containing lmroman10-regular.otf etc."
    )
  }
  lm_dir <- file.path(tinytex_root, "texmf-dist/fonts/opentype/public/lm")
}
if (!file.exists(file.path(lm_dir, "lmroman10-regular.otf"))) {
  stop(sprintf(
    "Latin Modern Roman font files not found in %s.\nSet REGIONAL_FAVORITISM_LM_DIR to the correct directory.",
    lm_dir
  ))
}
systemfonts::register_font(
  name = "LM Roman",
  plain = file.path(lm_dir, "lmroman10-regular.otf"),
  bold = file.path(lm_dir, "lmroman10-bold.otf"),
  italic = file.path(lm_dir, "lmroman10-italic.otf"),
  bolditalic = file.path(lm_dir, "lmroman10-bolditalic.otf")
)
FONT <- "LM Roman"
PT <- 1 / 2.845  # ggplot geom_text `size` is in mm; multiply points by this

civ_adm2 <- sf::st_read(file.path(root, "data/raw/gadm_4.1/global/geoboundaries/CIV_ADM2.geojson"), quiet = TRUE)
goh <- civ_adm2 |> dplyr::filter(GID_2 == "CIV.5.1_1")
stopifnot(goh$NAME_2 == "Gôh")
goh_3857 <- sf::st_transform(goh, 3857)
goh_centroid_3857 <- sf::st_centroid(goh_3857)
goh_buf_3857 <- sf::st_buffer(goh_centroid_3857, 110000)
bb3857 <- sf::st_bbox(goh_buf_3857)
stopifnot(abs((bb3857["xmax"] - bb3857["xmin"]) - (bb3857["ymax"] - bb3857["ymin"])) < 1e-6)
goh_buf_wide_3857 <- sf::st_buffer(goh_centroid_3857, 110000 * 1.4)
bb_wide <- sf::st_bbox(sf::st_transform(goh_buf_wide_3857, 4326))

raster_template <- terra::rast(
  terra::ext(bb3857["xmin"], bb3857["xmax"], bb3857["ymin"], bb3857["ymax"]),
  resolution = 930, crs = "EPSG:3857"
)

year_raster <- function(year, files) {
  paths <- file.path(root, "data/raw/dmsp_raster_eog_manual", year, files)
  stopifnot(all(file.exists(paths)))
  rs <- terra::rast(paths)
  if (terra::nlyr(rs) > 1) rs <- terra::app(rs, mean, na.rm = TRUE)
  rs <- terra::crop(rs, terra::ext(bb_wide["xmin"], bb_wide["xmax"], bb_wide["ymin"], bb_wide["ymax"]))
  r <- terra::project(rs, raster_template, method = "near")
  stopifnot(sum(is.na(terra::values(r))) == 0)
  r
}

years <- list(
  "1996" = "F121996.v4b.global.stable_lights.avg_vis.tif",
  "2000" = c("F142000.v4b.global.stable_lights.avg_vis.tif", "F152000.v4b.global.stable_lights.avg_vis.tif"),
  "2005" = c("F152005.v4b.global.stable_lights.avg_vis.tif", "F162005.v4b.global.stable_lights.avg_vis.tif"),
  "2009" = "F162009.v4b.global.stable_lights.avg_vis.tif"
)

ink <- "#1F2937"
accent <- "#00406B"
grey_line <- "#6B6459"
paper_bg <- "#FFFFFF"

dn_breaks <- c(0, 3, 7, 10, 13, 17, 20, 23, 27, 30)
dn_colours <- c("#05070C", "#1D2F52", "#3A4D73", "#6B6459", "#A97E2F", "#C99A3F", "#E4B95A", "#F4C95D", "#FFF4CF")

north_arrow_grob <- function(x, y, size) {
  list(
    ggplot2::annotate("polygon",
      x = c(x, x - size * 0.35, x + size * 0.35), y = c(y + size, y - size * 0.4, y - size * 0.4),
      fill = "white", colour = NA
    ),
    ggplot2::annotate("text", x = x, y = y - size * 1.05, label = "N", colour = "white",
                      size = 9 * PT, family = FONT, fontface = "bold")
  )
}

round_corners <- function(img, px, px_h) {
  rr <- min(px, px_h) * 0.06
  base <- magick::image_blank(px, px_h, "black")
  rectH <- magick::image_blank(px, px_h - 2 * rr, "white")
  rectH <- magick::image_composite(base, rectH, offset = paste0("+0+", round(rr)))
  rectV <- magick::image_blank(px - 2 * rr, px_h, "white")
  rectV <- magick::image_composite(rectH, rectV, offset = paste0("+", round(rr), "+0"))
  circle <- magick::image_blank(round(2 * rr), round(2 * rr), "black")
  circle <- magick::image_draw(circle)
  theta <- seq(0, 2 * pi, length.out = 200)
  graphics::polygon(rr + rr * cos(theta), rr + rr * sin(theta), col = "white", border = NA)
  grDevices::dev.off()
  corners <- list(c(0, 0), c(px - 2 * rr, 0), c(0, px_h - 2 * rr), c(px - 2 * rr, px_h - 2 * rr))
  m <- rectV
  for (co in corners) m <- magick::image_composite(m, circle, offset = sprintf("+%d+%d", round(co[1]), round(co[2])), operator = "Lighten")
  img <- magick::image_convert(img, colorspace = "sRGB")
  img <- magick::image_composite(img, m, operator = "CopyOpacity")
  magick::image_background(img, paper_bg)
}

# Each tile is rendered at its FINAL printed size (MAP_IMG_W inches) at 300 dpi,
# so the scale bar / north arrow inside it come out at true point sizes too.
TILE_DPI <- 300
TILE_PX <- round(MAP_IMG_W * TILE_DPI)

render_map_tile_png <- function(yr) {
  r <- year_raster(yr, years[[yr]])
  xr <- bb3857["xmax"] - bb3857["xmin"]; yr_ <- bb3857["ymax"] - bb3857["ymin"]
  arrow_x <- bb3857["xmax"] - xr * 0.09; arrow_y <- bb3857["ymax"] - yr_ * 0.15

  p <- ggplot2::ggplot() +
    tidyterra::geom_spatraster(data = r, interpolate = FALSE) +
    # Same discrete DN bins the presentation uses, so the legend swatches
    # below are literally the colours that appear on the map.
    ggplot2::scale_fill_stepsn(
      colours = dn_colours, breaks = dn_breaks[-c(1, length(dn_breaks))],
      limits = c(0, 30), na.value = dn_colours[1],
      oob = scales::squish, guide = "none"
    ) +
    ggplot2::geom_sf(data = goh_3857, fill = NA, colour = "white", linewidth = 0.45) +
    north_arrow_grob(arrow_x, arrow_y, xr * 0.075) +
    ggspatial::annotation_scale(
      location = "bl", width_hint = 0.45, height = grid::unit(0.075, "cm"),
      text_col = "white", line_col = "white", text_family = FONT,
      text_cex = 0.75, line_width = 0.55,
      pad_x = grid::unit(0.17, "cm"), pad_y = grid::unit(0.17, "cm")
    ) +
    ggplot2::coord_sf(xlim = c(bb3857["xmin"], bb3857["xmax"]), ylim = c(bb3857["ymin"], bb3857["ymax"]),
                      expand = FALSE, datum = sf::st_crs(3857)) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.margin = ggplot2::margin(0, 0, 0, 0),
      plot.background = ggplot2::element_rect(fill = dn_colours[1], colour = NA)
    )

  tmp <- tempfile(fileext = ".png")
  ragg::agg_png(tmp, width = TILE_PX, height = TILE_PX, res = TILE_DPI, background = dn_colours[1])
  print(p)
  grDevices::dev.off()
  img <- round_corners(magick::image_read(tmp), TILE_PX, TILE_PX)
  out <- tempfile(fileext = ".png")
  magick::image_write(img, out)
  out
}

# The square tile sits in a square panel (aspect.ratio = 1) so it can never be
# stretched, with the year label as real vector text above it.
map_panel_plot <- function(yr) {
  raster_png <- png::readPNG(render_map_tile_png(yr))
  g <- grid::rasterGrob(raster_png, interpolate = FALSE)
  ggplot2::ggplot() +
    ggplot2::annotation_custom(g, xmin = 0, xmax = 1, ymin = 0, ymax = 1) +
    # The year rides just above the panel edge (clip = "off") rather than in
    # the plot-title slot: a square panel gets centred vertically in whatever
    # height the row gives it, so a real title would float away from the map.
    ggplot2::annotate("text", x = 0.5, y = 1.03, label = yr, vjust = 0,
                      family = FONT, fontface = "bold", size = 10 * PT, colour = ink) +
    ggplot2::coord_cartesian(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE, clip = "off") +
    ggplot2::theme_void() +
    ggplot2::theme(
      aspect.ratio = 1,
      plot.margin = ggplot2::margin(11, 0.75, 0, 0.75)
    )
}

map_plots <- lapply(names(years), map_panel_plot)

# --- Legend: the presentation's own discrete DN palette, one swatch per bin ---
bin_lo <- head(dn_breaks, -1); bin_hi <- tail(dn_breaks, -1)
legend_bins <- data.frame(
  ymin = seq_along(bin_lo) - 1, ymax = seq_along(bin_lo),
  label = paste0(bin_lo, "-", bin_hi, " DN"),
  colour = dn_colours
)
# The legend's heading goes in the plot-title slot, the same band the year
# labels sit in, so the colour bar starts level with the map images instead of
# fighting them for vertical space.
legend_plot <- ggplot2::ggplot(legend_bins) +
  ggplot2::geom_rect(ggplot2::aes(xmin = 0, xmax = 0.8, ymin = ymin, ymax = ymax), fill = legend_bins$colour) +
  ggplot2::geom_text(ggplot2::aes(x = 0.95, y = (ymin + ymax) / 2, label = label),
                     hjust = 0, size = 6.8 * PT, colour = ink, family = FONT) +
  ggplot2::coord_cartesian(xlim = c(0, 3.3), ylim = c(0, 9), expand = FALSE, clip = "off") +
  ggplot2::labs(title = "DMSP-OLS\nStable Lights") +
  ggplot2::theme_void() +
  ggplot2::theme(
    plot.title = ggplot2::element_text(family = FONT, face = "bold", size = 7,
                                       colour = ink, hjust = 0, lineheight = 1.05,
                                       margin = ggplot2::margin(b = 3)),
    plot.margin = ggplot2::margin(0, 0.5, 0, 0.7)
  )

# --- Trend chart --------------------------------------------------------------
panel <- readr::read_csv(file.path(root, "data/processed/analysis_panel.csv"), show_col_types = FALSE)
civ <- panel |> dplyr::filter(iso3 == "CIV", adm_level == "ADM2")
goh_ts <- civ |> dplyr::filter(region_id == "CIV.5.1_1") |> dplyr::transmute(year, series = "Goh", ln_ntl)
stopifnot(nrow(goh_ts) == 22, min(goh_ts$year) == 1992, max(goh_ts$year) == 2013)
avg_ts <- civ |> dplyr::group_by(year) |>
  dplyr::summarise(ln_ntl = mean(ln_ntl, na.rm = TRUE), .groups = "drop") |>
  dplyr::transmute(year, series = "Ivory Coast average", ln_ntl)
d <- dplyr::bind_rows(goh_ts, avg_ts)

divergence_2000 <- goh_ts$ln_ntl[goh_ts$year == 2000] - avg_ts$ln_ntl[avg_ts$year == 2000]
divergence_1999 <- goh_ts$ln_ntl[goh_ts$year == 1999] - avg_ts$ln_ntl[avg_ts$year == 1999]
stopifnot(divergence_2000 > divergence_1999)

trend <- ggplot2::ggplot(d, ggplot2::aes(x = year, y = ln_ntl, group = series)) +
  ggplot2::annotate("rect", xmin = 2000, xmax = 2011, ymin = -Inf, ymax = Inf, fill = accent, alpha = 0.07) +
  # the two period markers are drawn in the accent colour of their own
  # label, so they read as the Gbagbo window rather than as gridlines
  ggplot2::geom_vline(xintercept = c(2000, 2011), linewidth = 0.45, colour = accent,
                      linetype = "dashed", alpha = 0.75) +
  ggplot2::geom_line(data = dplyr::filter(d, series == "Ivory Coast average"),
                     colour = grey_line, linewidth = 0.45, linetype = "22") +
  ggplot2::geom_line(data = dplyr::filter(d, series == "Goh"), colour = ink, linewidth = 0.7) +
  ggplot2::annotate("text", x = 2013.35, y = dplyr::filter(d, series == "Goh", year == 2013)$ln_ntl,
                    label = "Gôh", hjust = 0, size = 8.5 * PT, colour = ink, fontface = "bold", family = FONT) +
  ggplot2::annotate("text", x = 2013.35, y = dplyr::filter(d, series == "Ivory Coast average", year == 2013)$ln_ntl,
                    label = "Country average", hjust = 0, size = 8.5 * PT, colour = ink, fontface = "bold", family = FONT) +
  ggplot2::annotate("text", x = 2000.25, y = max(d$ln_ntl) + 0.3,
                    label = "Laurent Gbagbo, in power 2000-2011", hjust = 0, size = 8.5 * PT,
                    colour = accent, fontface = "italic", family = FONT) +
  ggplot2::scale_x_continuous(breaks = seq(1992, 2013, 1), limits = c(1992, 2019.5), expand = c(0, 0)) +
  ggplot2::labs(x = NULL, y = "ln(Nighttime Light Intensity)") +
  ggplot2::theme_minimal(base_size = 9) +
  ggplot2::theme(
    text = ggplot2::element_text(family = FONT),
    panel.grid.minor = ggplot2::element_blank(),
    # one light vertical rule per year, matching the horizontal gridlines
    panel.grid.major.x = ggplot2::element_line(colour = "#E5E3DE", linewidth = 0.25),
    panel.grid.major.y = ggplot2::element_line(colour = "#E5E3DE", linewidth = 0.25),
    axis.text.y = ggplot2::element_text(colour = ink, size = 8, family = FONT),
    axis.text.x = ggplot2::element_text(colour = ink, size = 7.5, family = FONT, angle = 45, hjust = 1),
    axis.title.y = ggplot2::element_text(colour = ink, size = 8.5, family = FONT),
    plot.background = ggplot2::element_rect(fill = paper_bg, colour = NA),
    plot.margin = ggplot2::margin(8, 4, 2, 4)
  )

maps_row <- (map_plots[[1]] | map_plots[[2]] | map_plots[[3]] | map_plots[[4]] | legend_plot) +
  patchwork::plot_layout(widths = COL_UNITS)

# wrap_elements() takes the maps row out of patchwork's axis alignment, so it
# spans the full figure width instead of being indented to line up with the
# trend chart's y-axis (which was wasting ~1 inch on the left).
combined <- patchwork::wrap_elements(full = maps_row) / trend +
  patchwork::plot_layout(heights = c(MAPS_ROW_H, TREND_H)) &
  ggplot2::theme(plot.background = ggplot2::element_rect(fill = paper_bg, colour = NA))

svg_path <- file.path(root, "paper/img/goh_combined_paper.svg")
pdf_path <- file.path(root, "paper/img/goh_combined_paper.pdf")
svglite::svglite(svg_path, width = FIG_W, height = FIG_H, bg = paper_bg)
print(combined)
grDevices::dev.off()

# Embed the real font in the SVG so the renderer can't substitute one.
if (!requireNamespace("base64enc", quietly = TRUE)) install.packages("base64enc", repos = "https://cloud.r-project.org")
font_face_css <- function(family, weight, style, file) {
  sprintf(
    "@font-face{font-family:'%s';font-weight:%s;font-style:%s;src:url(data:font/opentype;base64,%s) format('opentype');}",
    family, weight, style, base64enc::base64encode(file)
  )
}
faces <- paste(c(
  font_face_css("Latin Modern Roman", "normal", "normal", file.path(lm_dir, "lmroman10-regular.otf")),
  font_face_css("Latin Modern Roman", "bold", "normal", file.path(lm_dir, "lmroman10-bold.otf")),
  font_face_css("Latin Modern Roman", "normal", "italic", file.path(lm_dir, "lmroman10-italic.otf")),
  font_face_css("Latin Modern Roman", "bold", "italic", file.path(lm_dir, "lmroman10-bolditalic.otf"))
), collapse = "\n")
svg_text <- paste(readLines(svg_path, warn = FALSE), collapse = "\n")
svg_text <- sub("(<svg[^>]*>)", paste0("\\1\n<style type=\"text/css\"><![CDATA[\n", faces, "\n]]></style>"), svg_text)
writeLines(svg_text, svg_path)

# rsvg-convert silently substitutes fonts on this machine (verified with an
# isolated test SVG), so print through headless Chrome, which honours the
# embedded @font-face and keeps all text as real vector glyphs.
html_path <- file.path(tempdir(), "goh_wrapper.html")

# Headless Chrome/Chromium for HTML->PDF rendering (used to rasterize the
# SVG built above with correct embedded-font metrics). REGIONAL_FAVORITISM_
# CHROME_BIN overrides autodetection; otherwise this looks for a system
# Chrome/Chromium/Edge install and falls back to Puppeteer's own cache.
find_chrome <- function() {
  env <- Sys.getenv("REGIONAL_FAVORITISM_CHROME_BIN", unset = NA)
  if (!is.na(env) && file.exists(env)) return(env)
  candidates <- c(
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    Sys.which("google-chrome"), Sys.which("chromium"), Sys.which("chromium-browser")
  )
  found <- candidates[nzchar(candidates) & file.exists(candidates)]
  if (length(found) > 0) return(found[1])
  puppeteer_cache <- path.expand("~/.cache/puppeteer/chrome")
  if (dir.exists(puppeteer_cache)) {
    hits <- Sys.glob(file.path(puppeteer_cache, "*", "*",
                                "Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"))
    if (length(hits) > 0) return(sort(hits, decreasing = TRUE)[1])
    hits <- Sys.glob(file.path(puppeteer_cache, "*", "chrome-linux64", "chrome"))
    if (length(hits) > 0) return(sort(hits, decreasing = TRUE)[1])
  }
  stop(
    "Could not find a Chrome/Chromium binary.\n",
    "Install Google Chrome, or run `npx puppeteer browsers install chrome`,\n",
    "or set REGIONAL_FAVORITISM_CHROME_BIN to the binary path."
  )
}
chrome_bin <- find_chrome()

write_wrapper <- function(w_in, h_in, dx_in = 0, dy_in = 0) {
  writeLines(sprintf(
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>@page{size:%.4fin %.4fin;margin:0;}*{margin:0;padding:0;}html,body{width:%.4fin;height:%.4fin;overflow:hidden;}#wrap{position:absolute;left:%.4fin;top:%.4fin;}svg{display:block;}</style></head><body><div id=\"wrap\">%s</div></body></html>",
    w_in, h_in, w_in, h_in, dx_in, dy_in,
    paste(readLines(svg_path, warn = FALSE), collapse = "\n")
  ), html_path)
}

print_pdf <- function(out) {
  st <- system(sprintf(
    "%s --headless --disable-gpu --no-pdf-header-footer --print-to-pdf=%s --print-to-pdf-no-header --no-margins %s 2>/dev/null",
    shQuote(chrome_bin), shQuote(out), shQuote(paste0("file://", html_path))
  ))
  stopifnot(st == 0, file.exists(out))
}

# Pass 1: print the figure as laid out, then measure how much blank paper
# patchwork left around the content (it centres the square map panels inside
# whatever height the row gets, which leaves a visible band above the years).
write_wrapper(FIG_W, FIG_H)
print_pdf(pdf_path)

measure_margins <- function(pdf, dpi = 200) {
  stem <- file.path(tempdir(), "figmeas")
  system(sprintf("pdftoppm -png -r %d %s %s", dpi, shQuote(pdf), shQuote(stem)))
  png_file <- list.files(tempdir(), pattern = "^figmeas.*\\.png$", full.names = TRUE)[1]
  m <- png::readPNG(png_file)
  inked <- m[, , 1] < 0.85 | m[, , 2] < 0.85 | m[, , 3] < 0.85
  rows <- which(apply(inked, 1, any)); cols <- which(apply(inked, 2, any))
  unlink(png_file)
  list(top = (min(rows) - 1) / dpi, bottom = (nrow(inked) - max(rows)) / dpi,
       left = (min(cols) - 1) / dpi, right = (ncol(inked) - max(cols)) / dpi)
}

# Pass 2: trim that blank paper away, keeping a hairline safety margin.
mg <- measure_margins(pdf_path)
PAD <- 0.02
trim_t <- max(0, mg$top - PAD); trim_b <- max(0, mg$bottom - PAD)
# Trim vertically only: the figure's width must stay exactly FIG_W so that
# width=0.95\\linewidth in the paper still renders it at 1:1 scale.
trim_l <- 0; trim_r <- 0
write_wrapper(FIG_W - trim_l - trim_r, FIG_H - trim_t - trim_b, -trim_l, -trim_t)
print_pdf(pdf_path)
cat(sprintf("trimmed blank paper: top %.3f, bottom %.3f, left %.3f, right %.3f in\n",
            trim_t, trim_b, trim_l, trim_r))
cat(sprintf("OK: figure built at true print size %.2f x %.2f in (scale 1.0 on the page)\n", FIG_W, FIG_H))

# Mirror the output(s) into this package's own results folder.
if (file.exists(pdf_path)) file.copy(pdf_path, here::here("03_results", "figures", basename(pdf_path)), overwrite = TRUE)
if (file.exists(svg_path)) file.copy(svg_path, here::here("03_results", "figures", basename(svg_path)), overwrite = TRUE)
