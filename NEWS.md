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
