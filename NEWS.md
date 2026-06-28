# worldcup26 0.7.1

* The Knockout stage tab now carries a short note explaining that fixture dates
  and times are official but next-round matchups can lag the results — the
  football-data.org API doesn't place a team into a knockout slot until that
  slot is officially set, so an upcoming game may read "TBD" even after the
  feeding match is decided. The note links to the official FIFA fixtures page
  for the latest confirmed matchups. Front-end copy only — no R or
  `live-scores.js` changes.

  _[This update was written by Claude]_

# worldcup26 0.7.0

* The companion Quarto site gains a **Knockout stage** tab (before Standings)
  showing the bracket rounds with dates/times, teams, and results. The
  football-data.org API supplies each knockout fixture's stage, date, status,
  and score but no match-to-slot linkage and a null team until a slot is
  decided, so the rounds are laid out as ordered columns (Round of 32 → Round
  of 16 → Quarter-finals → Semi-finals → Final, with the third-place playoff
  beside the Final) rather than a connector tree; a slot whose teams aren't
  decided yet reads "TBD".
* Front-end only — no R package code changed. The knockout fixtures already
  flow through `all_matches()`, and the cards derive from the same live-merged
  match array as the rest of the page, so the optional "Update scores" button
  refreshes their scorelines with no extra wiring. The round-grouping logic is
  the tested pure helper `knockoutRounds()` in `live-scores.js`.

  _[This update was written by Claude]_

# worldcup26 0.6.0

* Added group standings and advancement reasoning. Four new functions compute
  this in tested R (not by asking the chat's text-to-SQL model to derive it):
  `group_standings()` builds the group tables with the FIFA 2026 in-group
  tiebreakers (points, head-to-head, then overall goal difference and goals);
  `advancement_status()` reports whether each team has won its group, clinched a
  top-two place, been eliminated from the top two, or is still alive, computed
  by enumerating every remaining-match outcome; `team_scenario()` spells out
  what a team's own remaining match(es) would mean; and `third_place_table()`
  ranks the race for the eight best third-placed teams.
* The chat dashboard now answers standings and "who has clinched / is
  eliminated / what does my team need" questions from a pre-computed snapshot,
  and the companion Quarto site gains a **Standings** tab. The published data
  set adds `standings.json`/`.csv` and `third_place.json`/`.csv`.
* Honest limits, surfaced rather than hidden: the deepest official tiebreakers
  (disciplinary/conduct records and FIFA ranking) aren't in the API, so teams
  level on everything else are flagged as ties; and the cross-group third-place
  race is shown as a provisional standing, not a guaranteed verdict, while
  groups are in progress.

  _[This update was written by Claude]_

# worldcup26 0.5.1

* Bug fix: the publish workflow's schedule didn't match its documented
  behavior. It defined only a single 12-minute cron, while the job's `if`
  condition gated on an hourly cron string (`"0 0-6,15-23 * * *"`) that was
  never registered. As a result the hourly fallback never matched, so when
  `WORLDCUP26_LIVE` was `false` the site stopped rebuilding entirely instead of
  refreshing once an hour. The workflow now registers two crons: an hourly tick
  that always runs, and a 10-minute tick (`:10`-`:50`) that runs only when
  `WORLDCUP26_LIVE` is `true`.

  _[This update was written by Claude]_

# worldcup26 0.5.0

* The "By team" tab on the companion Quarto site now shows scores from the
  selected team's perspective. Previously the score column was always rendered
  in home–away order, so a 2–0 win by the home side looked identical on both
  team pages and you couldn't tell who won. The team's goals are now listed
  first (e.g. Mexico's page shows `2–0`, South Africa's shows `0–2` for the
  same match).
* Added an optional paid-tier "live scores" mode. Set the `WORLDCUP26_LIVE`
  environment variable (to `"true"`, `"1"`, `"yes"`, or `"on"`) along with a
  paid `FOOTBALL_DATA_API_KEY` to opt in. Live mode uses a short cache TTL and
  shows running scorelines for in-play matches (e.g. `"1–0 (live)"`) on the
  site and in the chat. The default remains the free tier, which returns
  delayed scores and shows in-progress matches as `"in progress"`.

  _[This update was written by Claude]_

# worldcup26 0.4.0

* Time zones are now selectable. `team_schedule()`, `team_next_match()`,
  `team_past_results()`, and `all_matches()` gain a `tz` argument (any name
  from `OlsonNames()`, default `"America/New_York"`); `match_date` and the
  kickoff time are recomputed for that zone. The companion Quarto site adds a
  single time-zone picker that drives both tabs and defaults to the visitor's
  own browser zone.
* **Breaking:** the `kickoff_edt` column is renamed to `kickoff`, since the
  value now carries whatever zone you asked for (e.g. `"6:00 PM PDT"`). This
  affects `team_schedule()` and friends, `all_matches()`, `chat_data()`, and
  the published `chat_data.json`/`.csv` files. The chat dashboard still
  presents Eastern times.

  _[This update was written by Claude]_

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
