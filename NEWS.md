# worldcup26 0.3.0

* All dates and times are now presented in US Eastern (EDT) across the whole
  package, since every World Cup venue is in North America. `team_schedule()`,
  `team_next_match()`, `team_past_results()`, and `all_matches()` now return a
  `match_date` (Eastern `Date`) and a readable `kickoff_edt` (e.g.
  `"9:00 PM EDT"`). `all_matches()` keeps the raw `utc_date` (UTC) for
  ordering; the team-facing functions no longer surface `utc_date`. The chat
  data and the companion Quarto site present Eastern times to match.

  _[This update was written by Claude]_

# worldcup26 0.2.0

* The hourly site build now publishes the tournament data as plain files
  on the GitHub Pages site (`data/` directory), so it can be reused from
  any language without an API key: `chat_data.json`/`.csv`,
  `teams.json`/`.csv`, a lossless `worldcup26.rds`, and a `metadata.json`
  manifest. Produced by `data-raw/publish_data.R` as a step in the publish
  workflow.
* Added a soccer-ball favicon to the companion Quarto site.
* Bumped `actions/checkout` to v5 (Node 24) in the GitHub Actions
  workflows.

  _[This update was written by Claude]_

# worldcup26 0.1.0

* Initial public release.
* Wraps the football-data.org v4 API for the 2026 FIFA Men's World Cup:
  `list_teams()`, `team_schedule()`, `team_next_match()`,
  `team_past_results()`, and `all_matches()`.
* Flexible team lookup by full name, short name, three-letter code, or
  common alias, with accent- and punctuation-insensitive matching.
* On-disk response caching with a configurable TTL and `clear_cache()`.
* `chat_data()` plus a natural-language Shiny chat dashboard,
  `worldcup26_chat()`, powered by querychat and ellmer.
* Companion Quarto + Observable JS site for browsing the schedule by team
  or by date.

  _[This update was written by Claude]_
