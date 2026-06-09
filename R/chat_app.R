#' Launch the natural-language chat dashboard
#'
#' Starts a Shiny app powered by the
#' [querychat](https://github.com/posit-dev/querychat) package. You can
#' ask questions about the World Cup schedule and results in plain
#' English (e.g. *"When is Canada's next game?"*, *"Show me all matches
#' on June 15"*, *"Which teams are in Group D?"*) and the app translates
#' them to SQL over a tidy `matches` table.
#'
#' The app uses [Anthropic Claude](https://www.anthropic.com) by default.
#' You must have an `ANTHROPIC_API_KEY` environment variable set (e.g. in
#' `~/.Renviron`). Get a key at <https://console.anthropic.com>.
#'
#' @param data The data frame to chat with. Defaults to [chat_data()].
#' @param client An `ellmer::Chat` object, a function that takes a
#'   `system_prompt` and returns an `ellmer::Chat`, or a model string
#'   like `"anthropic/claude-sonnet-4-6"`. When `NULL` (the default),
#'   builds a Claude client using `model`.
#' @param model Model identifier passed to [ellmer::chat_anthropic()].
#'   Ignored if `client` is supplied. Defaults to `"claude-sonnet-4-6"`.
#' @param greeting Optional Markdown greeting. Defaults to a built-in
#'   greeting with example questions.
#' @param ... Additional arguments forwarded to
#'   [querychat::querychat_app()].
#' @return Invisibly returns the running app (called for its side effect).
#' @export
#' @examples
#' \dontrun{
#' worldcup26_chat()
#' }
worldcup26_chat <- function(data    = chat_data(),
                            client  = NULL,
                            model   = "claude-sonnet-4-6",
                            greeting = chat_default_greeting(),
                            ...) {
  if (is.null(client) && !nzchar(Sys.getenv("ANTHROPIC_API_KEY"))) {
    cli::cli_abort(c(
      "No Anthropic API key found.",
      i = "Set {.envvar ANTHROPIC_API_KEY} in your {.file ~/.Renviron}.",
      i = "Get a key at {.url https://console.anthropic.com/}."
    ))
  }

  rlang::check_installed(c("querychat", "ellmer", "shiny", "bslib"))

  if (is.null(client)) {
    force(model)
    client <- function(system_prompt = NULL) {
      ellmer::chat_anthropic(system_prompt = system_prompt, model = model)
    }
  }

  source <- querychat::querychat_data_source(data, table_name = "matches")
  config <- querychat::querychat_init(
    source,
    client             = client,
    greeting           = greeting,
    data_description   = chat_data_description(),
    extra_instructions = chat_extra_instructions(today = utc_today())
  )
  querychat::querychat_app(config, ...)
}

#' Default greeting displayed when the chat first opens.
#' @noRd
chat_default_greeting <- function() {
  paste(
    "Welcome! Ask me anything about the 2026 FIFA Men's World Cup",
    "schedule and results. Some questions you can try:",
    "",
    "- *When is Canada's next game?*",
    "- *Show me all matches on June 15.*",
    "- *Which teams are in Group D?*",
    "- *List the round of 16 matches.*",
    "- *Has Brazil played yet?*",
    "",
    "Data comes from [football-data.org](https://www.football-data.org/).",
    "During an in-progress match the score column reads *\"in progress\"*",
    "because the dashboard uses the free API tier \u2014 check back after the",
    "final whistle.",
    sep = "\n"
  )
}

#' Markdown bullet-list description of the `matches` table, fed to the LLM.
#' @noRd
chat_data_description <- function() {
  paste(
    "The single available table is named `matches`. It has one row per",
    "match in the 2026 FIFA Men's World Cup. The tournament has 48 teams",
    "in twelve groups A through L. There are 104 matches: 72 group-stage",
    "matches followed by knockout rounds (round of 32, round of 16,",
    "quarter-finals, semi-finals, a third-place playoff, and the final).",
    "",
    "Columns:",
    "",
    "- `match_id` (integer): football-data.org match identifier.",
    "- `utc_date` (timestamp): kickoff time in UTC.",
    "- `match_date` (date): the kickoff date in UTC. Use this column for",
    "  date-based queries like \"matches on June 15\".",
    "- `kickoff_utc` (text): kickoff time formatted as `HH:MM UTC`.",
    "- `matchday` (integer): the round within the group stage (1, 2, or 3);",
    "  NULL for knockout matches.",
    "- `stage` (text): one of `GROUP_STAGE`, `LAST_32`, `LAST_16`,",
    "  `QUARTER_FINALS`, `SEMI_FINALS`, `THIRD_PLACE`, `FINAL`.",
    "- `stage_label` (text): the human-readable label for `stage`",
    "  (`'Group stage'`, `'Round of 16'`, etc.).",
    "- `knockout` (boolean): TRUE for any non-group-stage match.",
    "- `group_letter` (text): the group letter (`'A'` through `'L'`)",
    "  during the group stage; NULL for knockouts.",
    "- `home_team`, `home_tla` (text): home team full name and three-letter",
    "  code (e.g. `'United States'`, `'USA'`).",
    "- `away_team`, `away_tla` (text): away team full name and code.",
    "- `status` (text): match status. One of `SCHEDULED`, `TIMED`, `IN_PLAY`,",
    "  `PAUSED`, `EXTRA_TIME`, `PENALTY_SHOOTOUT`, `FINISHED`, `AWARDED`,",
    "  `POSTPONED`, `SUSPENDED`, `CANCELLED`.",
    "- `score_display` (text): the score formatted for humans, e.g. `'2-1'`,",
    "  or `'in progress'`, or `'no score available yet'`. Empty string when",
    "  the match has not been played.",
    "- `home_score`, `away_score` (integer): full-time goals; NULL if not",
    "  yet recorded.",
    "- `home_pk`, `away_pk` (integer): penalty shoot-out goals; NULL when",
    "  the match was not decided on penalties.",
    "- `is_finished` (boolean): TRUE when `status` is `FINISHED` or `AWARDED`.",
    "- `is_upcoming` (boolean): TRUE when the match has not yet been played",
    "  or is live (and was not cancelled, postponed, or suspended).",
    "- `is_today` (boolean): TRUE when `match_date` equals today's UTC date.",
    "- `venue` (text): host stadium. Currently NULL for every match",
    "  (the free API tier does not expose venues).",
    "",
    "Knockout matches may have NULL `home_team` / `away_team` until earlier",
    "rounds have been decided. Treat those rows as bracket placeholders.",
    sep = "\n"
  )
}

#' Tournament-specific guidance and today's date, fed to the LLM.
#' @noRd
chat_extra_instructions <- function(today = utc_today()) {
  sprintf(paste(
    "Today's date is %s (UTC, ISO `%s`). When the user asks about \"today\",",
    "\"tomorrow\", \"this week\", \"next week\", or \"the next match\",",
    "compute dates relative to today.",
    "",
    "When the user names a team, match against `home_team`, `away_team`,",
    "`home_tla`, or `away_tla`. Be tolerant of common variants",
    "(\"USA\" / \"United States\" / \"U.S.\", \"Korea\" for \"South Korea\",",
    "\"Czech Republic\" for \"Czechia\", \"Mexico\" / \"M\u00e9xico\", etc.).",
    "Use a case-insensitive `LIKE` pattern when in doubt.",
    "",
    "For \"team X's next game\": filter for `is_upcoming = TRUE` and rows",
    "where X is either the home or away team, order by `utc_date` ascending,",
    "and return the first row.",
    "",
    "For \"team X's past results\": filter for `is_finished = TRUE` (or",
    "`match_date < DATE '%s'`) and return `score_display` for the readable",
    "score. Do **not** invent scores \u2014 if `home_score` and `away_score`",
    "are NULL, the score is not yet available.",
    "",
    "All times in `utc_date` are UTC. If the user asks about local times,",
    "say so explicitly and remind them the data is in UTC.",
    sep = "\n"
  ),
  format(today, "%A, %B %e, %Y"),
  format(today, "%Y-%m-%d"),
  format(today, "%Y-%m-%d")
  )
}
