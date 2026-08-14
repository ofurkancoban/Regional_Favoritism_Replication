suppressWarnings(library(data.table))
plad <- data.table::fread("data/raw/plad/PLAD_April_2024.tab", sep = "\t")
plad <- plad[!is.na(gid_2) & gid_2 != "." & gid_0 != "."]
cw36 <- data.table::fread("data/processed/gadm36_41_crosswalk.csv")
plad[cw36, on = .(gid_2 = gid2_36), gid_2_41 := i.gid2_41]
plad[, birth_gid2_final := data.table::fcase(!is.na(gid_2_41), gid_2_41, default = gid_2)]
ever_birth <- unique(plad[, .(gid_0, birth_gid2_final)])
cat("Ever-birth ADM2 rows:", nrow(ever_birth), "\n")

ever_birth[, gid1 := data.table::fcase(
  grepl("^[A-Z]{3}\\.[0-9]+\\.[0-9]+_[0-9]+$", birth_gid2_final),
  sub("(\\.[0-9]+)\\.[0-9]+_[0-9]+$", "\\1_1", birth_gid2_final),
  default = NA_character_
)]
cat("Affected ADM1 (unique parents):", ever_birth[!is.na(gid1), uniqueN(gid1)], "\n")
cat("Countries affected:", ever_birth[!is.na(gid1), uniqueN(gid_0)], "\n")
data.table::fwrite(ever_birth[!is.na(gid1)], "data/processed/affected_adm1_birth_adm2.csv")
