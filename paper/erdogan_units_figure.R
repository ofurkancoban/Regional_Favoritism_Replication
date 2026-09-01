# paper/erdogan_units_figure.R
# Figure for Section 5.2: the four GIS units of observation behind HR 2014's
# Table IV, drawn on one real birthplace (Recep Tayyip Erdogan, Kasimpasa,
# Beyoglu, Istanbul) using this project's own geometry pipeline.
#
#   Panel A -- Col (1): 5 km circle around the birthplace point, clipped to
#              the coastline (data/processed/birthplace_circles_5km.gpkg).
#   Panel B -- Col (2): the SN1 (GADM 3.6 ADM1) region containing the point.
#   Panel C -- Col (3): the same SN1 region with every ever-birth SN2 district
#              cut out (data/processed/gadm_holepunched_adm1.gpkg).
#   Panel D -- Cols (4)-(7): the equal-area grid cells containing the point at
#              50 / 100 / 200 / 400 km resolution.
#
# Each panel is zoomed to its own unit -- the four units differ in size by
# roughly four orders of magnitude, so a shared extent makes the small ones
# invisible. Every panel therefore carries its own scale bar.

library(sf)
library(ggplot2)
library(patchwork)
library(systemfonts)
library(svglite)
library(ggspatial)

# Repo root: like every other script in this pipeline, this one is meant
# to be run with the working directory set to the repository root (where
# data/ lives). REGIONAL_FAVORITISM_ROOT overrides that for callers that
# can't set the working directory themselves.
root <- Sys.getenv("REGIONAL_FAVORITISM_ROOT", unset = ".")
sf::sf_use_s2(FALSE)

# --- print geometry, same convention as goh_figure.R -------------------------
# Built at the exact on-page size so every font size below is a true point size.
FIG_W <- 0.95 * 6.214
PANEL_W <- FIG_W / 2
# Panels are wider than tall. Chosen so the whole figure comes out short
# enough to share a page with Table 3: at 0.80 the figure was 5.64 in high
# and the two could not fit together. Squashing the panels rather than
# scaling the finished figure down keeps every font at its true printed
# point size. It also suits the subjects, since Istanbul province and the
# grid cells are both wider than they are tall.
MAP_ASPECT <- 0.58          # map height / map width
TITLE_H <- 0.46             # title + subtitle allowance per panel
ROW_H <- PANEL_W * MAP_ASPECT + TITLE_H
FIG_H <- 2 * ROW_H

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
PT <- 1 / 2.845

ink <- "#1F2937"
accent <- "#00406B"
gold <- "#C99A3F"
paper_bg <- "#FFFFFF"
land <- "#F2EFE8"
land_edge <- "#C9C3B6"
water <- "#DFE9F1"

birth_pt <- sf::st_sfc(sf::st_point(c(28.968, 41.032)), crs = 4326)
birth_3857 <- sf::st_transform(birth_pt, 3857)

# --- geometry ---------------------------------------------------------------
adm1 <- sf::st_read(file.path(root, "data/raw/gadm_3.6/gadm36_level1_only.gpkg"), quiet = TRUE)
tur1 <- adm1[adm1$GID_0 == "TUR", ]
ist <- tur1[tur1$GID_1 == "TUR.40_1", ]

# Panel C illustrates the hole-punch operation on THIS leader's own birth
# district only. In estimation (07_regression/.../table4_col23_holepunch*.R)
# the same cut is applied to every SN2 that was ever any leader's birthplace,
# which for Istanbul is two districts; showing both here would clutter a panel
# whose job is to explain what st_difference does, on one worked example.
beyoglu <- sf::st_read(file.path(root, "data/raw/gadm_3.6/gadm36_levels.gpkg"),
                       query = "SELECT * FROM level2 WHERE GID_2 = 'TUR.40.13_1'",
                       quiet = TRUE)
removed <- sf::st_geometry(beyoglu)
ist_hp <- sf::st_difference(sf::st_geometry(ist), removed)

# Areas are reported in an equal-area CRS: measuring them in EPSG:3857 would
# inflate every figure by 1/cos^2(latitude), about 1.77x at Istanbul's 41N.
EQUAL_AREA <- "ESRI:54034"
km2 <- function(g) sum(as.numeric(sf::st_area(sf::st_transform(g, EQUAL_AREA)))) / 1e6
cat(sprintf("Panel C: %s (%.1f km2) cut from %.0f km2 (%.2f%%)\n",
    beyoglu$NAME_2, km2(removed), km2(ist), 100 * km2(removed) / km2(ist)))

# Panel A's circle is REDRAWN for the figure rather than taken from
# birthplace_circles_5km.gpkg. The stored polygon is an s2 geodesic buffer,
# whose boundary is a cell-based approximation that wobbles by about +/-109 m
# on a 5,017 m median radius (2.2%). That is far below the ~1 km DMSP pixel,
# so it does not matter for the Col (1) estimate, but it is plainly visible as
# a scalloped edge when the panel is enlarged. Here the same construction --
# 5 km around the same point, clipped to the same GADM 3.6 coastline -- is
# rebuilt as a smooth planar buffer in UTM 35N purely so the panel reads as a
# circle. Analysis geometry is untouched.
CIRCLE_R_M <- 5000
UTM_IST <- 32635
circle_smooth <- sf::st_buffer(sf::st_transform(birth_pt, UTM_IST),
                               dist = CIRCLE_R_M, nQuadSegs = 120)

# The stored grid cells are clipped to national borders and coastlines, so
# drawing them directly shows ragged coastline-shaped polygons -- which
# contradicts the point of Cols (4)-(7), that the cells are same-sized
# rectangles laid down independently of any boundary. Recover the unclipped
# rectangle instead: the grids live on a regular lattice in ESRI:54034, so the
# lattice origin can be read off the cells that were never clipped, and the
# cell containing the birth point rebuilt exactly.
GRID_CRS <- "ESRI:54034"
birth_ea <- as.numeric(sf::st_coordinates(sf::st_transform(birth_pt, GRID_CRS))[1, ])

full_cell <- function(res_km) {
  cell_m <- res_km * 1000
  g <- sf::st_read(file.path(root, sprintf("data/processed/grid_cells_%dkm.gpkg", res_km)),
                   quiet = TRUE)
  g_ea <- sf::st_transform(g, GRID_CRS)
  bb <- t(vapply(sf::st_geometry(g_ea), function(x) as.numeric(sf::st_bbox(x)), numeric(4)))
  unclipped <- abs((bb[, 3] - bb[, 1]) - cell_m) < 1 & abs((bb[, 4] - bb[, 2]) - cell_m) < 1
  x0 <- stats::median(bb[unclipped, 1] %% cell_m)
  y0 <- stats::median(bb[unclipped, 2] %% cell_m)
  xmin <- x0 + floor((birth_ea[1] - x0) / cell_m) * cell_m
  ymin <- y0 + floor((birth_ea[2] - y0) / cell_m) * cell_m
  rect <- sf::st_as_sfc(sf::st_bbox(c(xmin = xmin, ymin = ymin,
                                       xmax = xmin + cell_m, ymax = ymin + cell_m),
                                     crs = sf::st_crs(GRID_CRS)))
  stored <- g_ea[sf::st_intersects(g_ea, sf::st_transform(birth_pt, GRID_CRS),
                                    sparse = FALSE)[, 1], ]
  stopifnot(
    abs(as.numeric(sf::st_area(rect)) - cell_m^2) < 1e-6 * cell_m^2,
    sf::st_intersects(rect, sf::st_transform(birth_pt, GRID_CRS), sparse = FALSE)[1, 1],
    all(sf::st_covered_by(sf::st_buffer(stored, -1), rect, sparse = FALSE))
  )
  cat(sprintf("  %3d km cell rebuilt: %.0f km2 (stored, clipped: %.0f km2)\n",
      res_km, as.numeric(sf::st_area(rect)) / 1e6,
      sum(as.numeric(sf::st_area(stored))) / 1e6))
  rect
}

cat("Panel D grid cells (unclipped rectangles on the ESRI:54034 lattice):\n")
grid_cells <- lapply(c(50, 100, 200, 400), full_cell)
names(grid_cells) <- c("50", "100", "200", "400")

# Land for context: GADM 3.6 level0, read only near Istanbul.
ctx_wkt <- sf::st_as_text(sf::st_as_sfc(sf::st_bbox(c(
  xmin = 24, ymin = 37, xmax = 34, ymax = 45), crs = 4326)))
l0 <- sf::st_read(file.path(root, "data/raw/gadm_3.6/gadm36_levels.gpkg"),
                  layer = "level0", quiet = TRUE, wkt_filter = ctx_wkt)

# Clip the smooth display circle to the coastline, exactly as the pipeline
# clips the real one (st_intersection against GADM 3.6 level0).
tur0 <- sf::st_make_valid(l0[l0$GID_0 == "TUR", ])
circle <- sf::st_intersection(circle_smooth, sf::st_transform(sf::st_geometry(tur0), UTM_IST))
cat(sprintf("Panel A circle: %.1f km2 after coastline clip (unclipped 5 km disc = %.1f km2)\n",
    as.numeric(sf::st_area(circle)) / 1e6, pi * (CIRCLE_R_M / 1000)^2))

# --- helpers ----------------------------------------------------------------
# Expand a bbox (in 3857) to the panel's aspect ratio, with a proportional pad.
frame_bbox <- function(geom, pad_frac = 0.08, aspect = MAP_ASPECT) {
  bb <- sf::st_bbox(sf::st_transform(geom, 3857))
  w <- as.numeric(bb["xmax"] - bb["xmin"]); h <- as.numeric(bb["ymax"] - bb["ymin"])
  cx <- as.numeric(bb["xmax"] + bb["xmin"]) / 2
  cy <- as.numeric(bb["ymax"] + bb["ymin"]) / 2
  w <- w * (1 + 2 * pad_frac); h <- h * (1 + 2 * pad_frac)
  if (h / w > aspect) w <- h / aspect else h <- w * aspect
  c(xmin = cx - w / 2, xmax = cx + w / 2, ymin = cy - h / 2, ymax = cy + h / 2)
}

base_theme <- function() {
  ggplot2::theme_void(base_family = FONT) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0, face = "bold", colour = ink,
                                          size = 9.5, margin = ggplot2::margin(b = 2)),
      plot.subtitle = ggplot2::element_text(hjust = 0, colour = "#6B6459",
                                             size = 7, margin = ggplot2::margin(b = 4)),
      plot.background = ggplot2::element_rect(fill = paper_bg, colour = NA),
      panel.background = ggplot2::element_rect(fill = water, colour = NA),
      panel.border = ggplot2::element_rect(colour = land_edge, fill = NA, linewidth = 0.4),
      plot.margin = ggplot2::margin(3, 5, 2, 3)
    )
}

scale_bar <- function() {
  ggspatial::annotation_scale(
    location = "br", width_hint = 0.34, height = unit(0.055, "cm"),
    text_cex = 0.55, line_width = 0.5, text_family = FONT,
    pad_x = unit(0.12, "cm"), pad_y = unit(0.12, "cm"),
    bar_cols = c(ink, "white"), text_col = ink, line_col = ink
  )
}

pt_layer <- function(size = 1.5) {
  ggplot2::geom_sf(data = birth_3857, colour = "white", fill = ink,
                   shape = 21, size = size, stroke = 0.45)
}

framed <- function(p, bb) {
  p + ggplot2::coord_sf(xlim = c(bb["xmin"], bb["xmax"]),
                        ylim = c(bb["ymin"], bb["ymax"]),
                        crs = 3857, expand = FALSE)
}

l0_3857 <- sf::st_transform(l0, 3857)
tur1_3857 <- sf::st_transform(tur1, 3857)
ist_3857 <- sf::st_transform(ist, 3857)
ist_hp_3857 <- sf::st_transform(ist_hp, 3857)
removed_3857 <- sf::st_transform(removed, 3857)
circle_3857 <- sf::st_transform(circle, 3857)

# --- Panel A: 5 km circle (Col 1) -------------------------------------------
bbA <- frame_bbox(circle, pad_frac = 0.55)
pA <- ggplot2::ggplot() +
  ggplot2::geom_sf(data = l0_3857, fill = land, colour = NA) +
  ggplot2::geom_sf(data = tur1_3857, fill = NA, colour = land_edge, linewidth = 0.25) +
  ggplot2::geom_sf(data = circle_3857, fill = accent, colour = accent,
                   alpha = 0.45, linewidth = 0.55) +
  pt_layer() +
  scale_bar() +
  ggplot2::labs(title = "A   Circle around the birthplace",
                subtitle = "5 km radius, clipped to the coastline · Col. (1)") +
  base_theme()
pA <- framed(pA, bbA)

# --- Panel B: SN1 region (Col 2) --------------------------------------------
bbB <- frame_bbox(ist, pad_frac = 0.10)
pB <- ggplot2::ggplot() +
  ggplot2::geom_sf(data = l0_3857, fill = land, colour = NA) +
  ggplot2::geom_sf(data = tur1_3857, fill = land, colour = land_edge, linewidth = 0.25) +
  ggplot2::geom_sf(data = ist_3857, fill = accent, colour = ink,
                   alpha = 0.55, linewidth = 0.45) +
  pt_layer() +
  scale_bar() +
  ggplot2::labs(title = "B   SN1 region",
                subtitle = "Istanbul, the whole first-level unit · Col. (2)") +
  base_theme()
pB <- framed(pB, bbB)

# --- Panel C: SN1 minus ever-birth SN2 (Col 3) ------------------------------
# The removed districts are ~0.7% of the province, so the hole is redrawn in a
# corner inset; at province zoom it would otherwise be a few pixels wide.
bbC <- bbB
pC <- ggplot2::ggplot() +
  ggplot2::geom_sf(data = l0_3857, fill = land, colour = NA) +
  ggplot2::geom_sf(data = tur1_3857, fill = land, colour = land_edge, linewidth = 0.25) +
  ggplot2::geom_sf(data = ist_hp_3857, fill = accent, colour = ink,
                   alpha = 0.55, linewidth = 0.45) +
  ggplot2::geom_sf(data = removed_3857, fill = "white", colour = gold, linewidth = 0.5) +
  pt_layer() +
  scale_bar() +
  ggplot2::labs(title = "C   SN1 minus the birth SN2",
                subtitle = "Beyoğlu cut out of the light average · Col. (3)") +
  base_theme()
pC <- framed(pC, bbC)

bb_inset <- frame_bbox(removed, pad_frac = 0.85, aspect = 1)
p_inset <- ggplot2::ggplot() +
  ggplot2::geom_sf(data = l0_3857, fill = land, colour = NA) +
  ggplot2::geom_sf(data = ist_hp_3857, fill = accent, colour = ink,
                   alpha = 0.55, linewidth = 0.3) +
  ggplot2::geom_sf(data = removed_3857, fill = "white", colour = gold, linewidth = 0.6) +
  pt_layer(size = 1.1) +
  ggplot2::coord_sf(xlim = c(bb_inset["xmin"], bb_inset["xmax"]),
                    ylim = c(bb_inset["ymin"], bb_inset["ymax"]),
                    crs = 3857, expand = FALSE) +
  ggplot2::theme_void(base_family = FONT) +
  ggplot2::theme(
    panel.background = ggplot2::element_rect(fill = water, colour = NA),
    panel.border = ggplot2::element_rect(colour = gold, fill = NA, linewidth = 0.6),
    plot.background = ggplot2::element_rect(fill = paper_bg, colour = NA)
  )

# Box on panel C showing what the inset magnifies.
inset_box <- sf::st_as_sfc(sf::st_bbox(c(
  xmin = as.numeric(bb_inset["xmin"]), xmax = as.numeric(bb_inset["xmax"]),
  ymin = as.numeric(bb_inset["ymin"]), ymax = as.numeric(bb_inset["ymax"])), crs = 3857))
pC <- pC + ggplot2::geom_sf(data = inset_box, fill = NA, colour = gold,
                             linewidth = 0.4, linetype = "22")
pC <- framed(pC, bbC)
pC <- pC + patchwork::inset_element(p_inset, left = 0.02, bottom = 0.02,
                                     right = 0.30, top = 0.42, align_to = "panel")

# --- Panel D: grid cells (Cols 4-7) -----------------------------------------
cells_3857 <- lapply(grid_cells, function(g) sf::st_transform(g, 3857))
bbD <- frame_bbox(grid_cells[["400"]], pad_frac = 0.10)
grid_pal <- c("50" = ink, "100" = accent, "200" = gold, "400" = "#8C7A5B")

pD <- ggplot2::ggplot() +
  ggplot2::geom_sf(data = l0_3857, fill = land, colour = land_edge, linewidth = 0.2)
for (nm in c("400", "200", "100", "50")) {
  pD <- pD + ggplot2::geom_sf(data = cells_3857[[nm]], fill = NA,
                               colour = grid_pal[[nm]], linewidth = 0.6)
}

# The four grids have independent origins, so the containing cells are nested
# but not concentric and their corners bunch up. Label them in a key instead
# of on the cells themselves.
dx_D <- as.numeric(bbD["xmax"]) - as.numeric(bbD["xmin"])
dy_D <- as.numeric(bbD["ymax"]) - as.numeric(bbD["ymin"])
key_x <- as.numeric(bbD["xmin"]) + 0.035 * dx_D
key_top <- as.numeric(bbD["ymin"]) + 0.30 * dy_D
key_dy <- 0.070 * dy_D
key_len <- 0.060 * dx_D
key_df <- data.frame(
  res = c("50", "100", "200", "400"),
  y = key_top - key_dy * (0:3),
  stringsAsFactors = FALSE
)
pD <- pD +
  ggplot2::annotate("rect",
                    xmin = key_x - 0.020 * dx_D, xmax = key_x + key_len * 1.35 + 0.115 * dx_D,
                    ymin = key_top - key_dy * 3 - 0.035 * dy_D, ymax = key_top + 0.035 * dy_D,
                    fill = paper_bg, colour = NA, alpha = 0.82) +
  ggplot2::geom_segment(data = key_df,
                        ggplot2::aes(x = key_x, xend = key_x + key_len,
                                     y = y, yend = y, colour = res),
                        linewidth = 0.7, show.legend = FALSE) +
  ggplot2::geom_text(data = key_df,
                     ggplot2::aes(x = key_x + key_len * 1.35, y = y,
                                  label = paste0(res, " km"), colour = res),
                     family = FONT, size = 6.2 * PT, hjust = 0, vjust = 0.5,
                     show.legend = FALSE) +
  ggplot2::scale_colour_manual(values = grid_pal) +
  pt_layer() +
  scale_bar() +
  ggplot2::labs(title = "D   Rectangular grid cells",
                subtitle = "equal-area cells drawn uncut, ignoring borders · Cols. (4)-(7)") +
  base_theme()
pD <- framed(pD, bbD)

combined <- (pA | pB) / (pC | pD) &
  ggplot2::theme(plot.background = ggplot2::element_rect(fill = paper_bg, colour = NA))

# --- export: svglite -> embedded LM Roman -> headless Chrome (true vector) ---
svg_path <- file.path(tempdir(), "erdogan_gis_units.svg")
pdf_path <- file.path(root, "paper/img/erdogan_gis_units_paper.pdf")

svglite::svglite(svg_path, width = FIG_W, height = FIG_H, bg = paper_bg)
print(combined)
grDevices::dev.off()

# svglite writes the font's real PostScript family name, so the embedded
# @font-face must be registered under 'Latin Modern Roman', not 'LM Roman'.
font_face_css <- function() {
  faces <- list(
    list(weight = "normal", style = "normal", file = "lmroman10-regular.otf"),
    list(weight = "bold",   style = "normal", file = "lmroman10-bold.otf"),
    list(weight = "normal", style = "italic", file = "lmroman10-italic.otf"),
    list(weight = "bold",   style = "italic", file = "lmroman10-bolditalic.otf")
  )
  paste0(vapply(faces, function(f) sprintf(
    "@font-face{font-family:'Latin Modern Roman';font-weight:%s;font-style:%s;src:url(data:font/otf;base64,%s) format('opentype');}\n",
    f$weight, f$style, base64enc::base64encode(file.path(lm_dir, f$file))
  ), character(1)), collapse = "")
}

svg_txt <- paste(readLines(svg_path, warn = FALSE), collapse = "\n")
svg_txt <- sub("(<svg[^>]*>)", paste0("\\1<style>", font_face_css(), "</style>"), svg_txt)

html_path <- file.path(tempdir(), "erdogan_wrapper.html")
writeLines(sprintf(
  '<!doctype html><html><head><meta charset="utf-8"><style>@page{size:%.4fin %.4fin;margin:0;}html,body{margin:0;padding:0;}</style></head><body>%s</body></html>',
  FIG_W, FIG_H, svg_txt), html_path)

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
system(sprintf(
  "%s --headless --disable-gpu --no-pdf-header-footer --print-to-pdf=%s --print-to-pdf-no-header --no-margins %s 2>/dev/null",
  shQuote(chrome_bin), shQuote(pdf_path), shQuote(paste0("file://", html_path))))

cat("written:", pdf_path, "\n")
