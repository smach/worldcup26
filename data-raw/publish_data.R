# Build the public, reusable data files served from GitHub Pages.
#
# The hourly "Render and publish" workflow runs this after rendering the site
# and before publishing, writing files into docs/data/ so they ship to
# https://smach.github.io/worldcup26/data/ alongside index.html.
#
# Output formats:
#   - JSON and CSV for portable, language-agnostic use.
#   - worldcup26.rds for R consumers (lossless: POSIXct, integer NAs, logicals).
#   - metadata.json describing what's there and when it was generated.
#
# Requires FOOTBALL_DATA_API_KEY in the environment (the workflow supplies it).
# The output directory can be overridden with WORLDCUP26_DATA_OUT (used in tests).

library(worldcup26)

out_dir <- Sys.getenv("WORLDCUP26_DATA_OUT", unset = file.path("docs", "data"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Fetch once; build the denormalised flat table the same way the chat does.
matches <- all_matches()
teams   <- list_teams()
flat    <- chat_data(matches = matches, teams = teams)

# Lossless snapshot for R: readRDS(url(".../worldcup26.rds")) restores exact
# types with no JSON round-trip loss.
saveRDS(
  list(matches = matches, teams = teams, chat_data = flat),
  file.path(out_dir, "worldcup26.rds")
)

# Portable snapshots. jsonlite writes POSIXct/Date as ISO-8601 strings and NA
# as null; the flat table is the friendliest single product (team names, TLAs,
# stage labels, scores, and convenience flags all in one row per match).
jsonlite::write_json(
  flat, file.path(out_dir, "chat_data.json"),
  pretty = TRUE, na = "null", auto_unbox = TRUE, POSIXt = "ISO8601"
)
jsonlite::write_json(
  teams, file.path(out_dir, "teams.json"),
  pretty = TRUE, na = "null", auto_unbox = TRUE
)

utils::write.csv(flat,  file.path(out_dir, "chat_data.csv"), row.names = FALSE, na = "")
utils::write.csv(teams, file.path(out_dir, "teams.csv"),     row.names = FALSE, na = "")

# Machine-readable manifest. The is_* flags are computed as of generated_utc;
# recompute from utc_date / match_date if you need them relative to another time.
tier_note <- if (worldcup26:::live_mode()) {
  "paid tier, live scores"
} else {
  "free tier, delayed scores"
}
meta <- list(
  generated_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  source        = sprintf("https://www.football-data.org/ (%s)", tier_note),
  note = paste(
    "is_today, is_upcoming and is_finished are computed as of generated_utc (UTC).",
    "Recompute from utc_date / match_date if you need them relative to another time."
  ),
  n_matches = nrow(flat),
  n_teams   = nrow(teams),
  files = list(
    "chat_data.json" = "One row per match, denormalised (JSON).",
    "chat_data.csv"  = "One row per match, denormalised (CSV).",
    "teams.json"     = "Participating teams (JSON).",
    "teams.csv"      = "Participating teams (CSV).",
    "worldcup26.rds" = "list(matches, teams, chat_data) for R, lossless types."
  )
)
jsonlite::write_json(
  meta, file.path(out_dir, "metadata.json"),
  pretty = TRUE, auto_unbox = TRUE
)

message("Wrote ", length(list.files(out_dir)), " data files to ", normalizePath(out_dir))
