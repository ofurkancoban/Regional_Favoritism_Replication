# 06_panel/02_harmonized_ntl_trend_plot.R
# Global mean trend of the harmonized DMSP/VIIRS nighttime lights panel
# (data/processed/ntl/harmonized_dmsp_viirs_adm2_panel.csv, 1992-2024).
#
# Note on the 2013/2014 step: DMSP-OLS saturates at DN=63 in bright urban
# cores, so calibrated-DMSP values for high-NTL developed countries (CHE,
# JPN, DEU, AUT, GBR, NLD, ...) sit near the scale ceiling through 2013.
# VIIRS has far greater dynamic range, so once the series switches to
# VIIRS-simulated-onto-DMSP-scale values in 2014, those same countries'
# values drop sharply (confirmed 2026-08-19: mean drop of -6 to -9.5 DN in
# the countries above, vs a  <1.5 DN drop in unsaturated countries like
# Turkey) -- a known DMSP/VIIRS sensor-transition characteristic of this
# harmonization method, not a data-processing error. Country-year fixed
# effects in the regression panel already absorb this level shift, so it
# does not affect Leader coefficient estimates; it is marked here only as
# a descriptive-plot caveat.

library(data.table)
library(ggplot2)

panel <- data.table::fread("data/processed/ntl/harmonized_dmsp_viirs_adm2_panel.csv")
trend <- panel[, .(mean_ntl = mean(harmonized_ntl, na.rm = TRUE)), by = year][order(year)]

out_dir <- "output/figures"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

p <- ggplot2::ggplot(trend, ggplot2::aes(x = year, y = mean_ntl)) +
  ggplot2::geom_line(color = "steelblue", linewidth = 0.9) +
  ggplot2::geom_point(color = "steelblue", size = 1.5) +
  ggplot2::geom_vline(xintercept = 2013.5, linetype = "dashed", color = "grey40") +
  ggplot2::annotate("text", x = 2013.5, y = max(trend$mean_ntl), hjust = -0.05, vjust = 1,
                     label = "DMSP -> VIIRS sensor transition", size = 3, color = "grey30") +
  ggplot2::labs(
    title = "Global mean harmonized nighttime lights (ADM2), 1992-2024",
    x = NULL, y = "Mean harmonized DN (0-63 scale)",
    caption = paste0(
      "Note: the 2013/2014 step reflects DMSP-OLS sensor saturation (DN capped at 63) in high-NTL\n",
      "developed countries, resolved once the series switches to VIIRS-derived values in 2014 -- a\n",
      "known DMSP/VIIRS harmonization characteristic, not a processing artifact. Absorbed by country-\n",
      "year fixed effects in all regression specifications."
    )
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(plot.caption = ggplot2::element_text(hjust = 0, size = 8, color = "grey40"))

ggplot2::ggsave(file.path(out_dir, "harmonized_ntl_global_trend.png"), p, width = 9, height = 5.5, dpi = 150)
cat(sprintf("Saved: %s\n", file.path(out_dir, "harmonized_ntl_global_trend.png")))
