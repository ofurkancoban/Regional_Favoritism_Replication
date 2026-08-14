# 06_panel/03_turkey_earthquake_ntl_plot.R
# Monthly VIIRS nighttime lights (2022-02 to 2024-02) for the four
# provinces most affected by the 6 Feb 2023 Kahramanmaras earthquake,
# from the luna+blackmarbler VNP46A3 panel
# (data/processed/ntl/turkey_luna_blackmarble_monthly_adm1.csv).
#
# Note on the Feb 2023 spike then Mar 2023 crash seen in Kahramanmaras and
# Malatya: plausibly a monthly-composite artifact of the disaster itself
# (fires, generators, emergency floodlighting during the ~22 post-quake
# days that month) rather than a genuine favoritism/relief signal --
# flagged in the plot caption, not smoothed away, since this is exactly
# the kind of noise a proper event-study design needs to account for.

library(data.table)
library(ggplot2)

panel <- data.table::fread("data/processed/ntl/turkey_luna_blackmarble_monthly_adm1.csv")
provinces <- c("K.Maras", "Hatay", "Adiyaman", "Malatya")
d <- panel[NAME_1 %in% provinces]
d[, date := as.Date(sprintf("%d-%02d-01", year, month))]
d[, NAME_1 := factor(NAME_1, levels = provinces,
                      labels = c("Kahramanmaras", "Hatay", "Adiyaman", "Malatya"))]

quake_date <- as.Date("2023-02-06")

out_dir <- "output/figures"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

p <- ggplot2::ggplot(d, ggplot2::aes(x = date, y = viirs_ntl)) +
  ggplot2::geom_vline(xintercept = quake_date, linetype = "dashed", color = "firebrick", linewidth = 0.6) +
  ggplot2::geom_line(color = "steelblue", linewidth = 0.8) +
  ggplot2::geom_point(color = "steelblue", size = 1.6) +
  ggplot2::facet_wrap(~NAME_1, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_date(date_labels = "%Y-%m", date_breaks = "4 months") +
  ggplot2::labs(
    title = "Monthly VIIRS nighttime lights around the Kahramanmaras earthquake",
    subtitle = "Dashed line = 6 Feb 2023 earthquake",
    x = NULL, y = "Mean VIIRS NTL (VNP46A3, NearNadir Composite)",
    caption = paste0(
      "Note: the Feb 2023 spike in Kahramanmaras/Malatya, followed by a Mar 2023 drop, is\n",
      "plausibly a monthly-composite artifact of the disaster itself (fires, generators, emergency\n",
      "floodlighting during the ~22 post-quake days in that month) rather than a favoritism signal --\n",
      "a reminder that a simple before/after comparison is not reliable here; a proper event-study\n",
      "design is needed."
    )
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
    plot.caption = ggplot2::element_text(hjust = 0, size = 8, color = "grey40"),
    strip.text = ggplot2::element_text(face = "bold")
  )

ggplot2::ggsave(file.path(out_dir, "turkey_earthquake_ntl_event_study.png"), p, width = 10, height = 7, dpi = 150)
cat(sprintf("Saved: %s\n", file.path(out_dir, "turkey_earthquake_ntl_event_study.png")))
