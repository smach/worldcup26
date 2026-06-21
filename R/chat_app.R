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
    # The standings/advancement tables aren't in the `matches` table; they are
    # pre-computed in R and handed to the model as a snapshot it narrates.
    extra_instructions = paste(
      chat_extra_instructions(today = eastern_today()),
      chat_advancement_digest(),
      sep = "\n\n"
    )
  )
  querychat::querychat_app(config, ...)
}

#' Default greeting displayed when the chat first opens.
#' @noRd
chat_default_greeting <- function() {
  tier_note <- if (live_mode()) {
    c(
      "During an in-progress match the score column shows the running",
      "scoreline (e.g. *\"1\u20130 (live)\"*) from the paid live-scores tier."
    )
  } else {
    c(
      "During an in-progress match the score column may read *\"in progress\"*",
      "because the dashboard uses the free API tier \u2014 check back after the",
      "final whistle."
    )
  }
  paste(
    c(
      "Welcome! Ask me anything about the 2026 FIFA Men's World Cup",
      "schedule and results. Some questions you can try:",
      "",
      "- *When is Canada's next game?*",
      "- *Show me all matches on June 15.*",
      "- *Which teams are in Group D?*",
      "- *Show the current Group D standings.*",
      "- *Which teams have clinched a spot in the next round?*",
      "- *What does Mexico need to advance?*",
      "- *Show the third-place standings.*",
      "- *Has Brazil played yet?*",
      "",
      "Data comes from [football-data.org](https://www.football-data.org/).",
      tier_note
    ),
    collapse = "\n"
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
    "- `utc_date` (timestamp): the raw kickoff instant in UTC. Use it only for",
    "  ordering matches chronologically, not for display.",
    "- `match_date` (date): the kickoff date in US Eastern (EDT). Use this",
    "  column for date-based queries like \"matches on June 15\".",
    "- `kickoff` (text): kickoff time formatted as `9:00 PM EDT`",
    "  (12-hour, US Eastern).",
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
    "  or `'in progress'` (or `'1-0 (live)'` on the paid live-scores tier),",
    "  or `'no score available yet'`. Empty string when the match has not",
    "  been played.",
    "- `home_score`, `away_score` (integer): full-time goals; NULL if not",
    "  yet recorded.",
    "- `home_pk`, `away_pk` (integer): penalty shoot-out goals; NULL when",
    "  the match was not decided on penalties.",
    "- `is_finished` (boolean): TRUE when `status` is `FINISHED` or `AWARDED`.",
    "- `is_upcoming` (boolean): TRUE when the match has not yet been played",
    "  or is live (and was not cancelled, postponed, or suspended).",
    "- `is_today` (boolean): TRUE when `match_date` equals today's Eastern date.",
    "- `venue` (text): host stadium. Currently NULL for every match",
    "  (the free API tier does not expose venues).",
    "",
    "Knockout matches may have NULL `home_team` / `away_team` until earlier",
    "rounds have been decided. Treat those rows as bracket placeholders.",
    "",
    "Group standings, each team's top-two advancement status, and the",
    "third-place race are **not** columns in this table. They are provided as",
    "pre-computed tables in the instructions below. Use those tables for any",
    "standings or \"who has clinched / is eliminated / what needs to happen\"",
    "question. Do not try to derive them from `matches` yourself.",
    sep = "\n"
  )
}

#' Tournament-specific guidance and today's date, fed to the LLM.
#' @noRd
chat_extra_instructions <- function(today = eastern_today()) {
  sprintf(paste(
    "Today's date is %s (US Eastern, ISO `%s`). When the user asks about \"today\",",
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
    "All match times are presented in US Eastern (EDT) \u2014 see `kickoff`",
    "and `match_date` \u2014 because every World Cup venue is in North America.",
    "When you mention a kickoff time, give it in EDT and label it as such.",
    sep = "\n"
  ),
  format(today, "%A, %B %e, %Y"),
  format(today, "%Y-%m-%d"),
  format(today, "%Y-%m-%d")
  )
}

#' Render the pre-computed standings/advancement snapshot for the LLM.
#'
#' Builds a compact Markdown digest from [group_standings()],
#' [advancement_status()], [third_place_table()], and (for still-alive teams)
#' [team_scenario()]. This is the authoritative source the chat narrates from,
#' so it doesn't have to derive standings or advancement itself in SQL.
#' @noRd
chat_advancement_digest <- function(matches = all_matches(),
                                    teams   = list_teams(),
                                    today   = eastern_today()) {
  st <- group_standings(matches, teams)
  if (nrow(st) == 0L) {
    return(paste(
      "## Group standings & advancement",
      "",
      "No group-stage standings are available yet.",
      sep = "\n"
    ))
  }
  adv <- advancement_status(matches, teams)
  tp  <- third_place_table(matches, teams)
  st  <- dplyr::left_join(st, adv[, c("team_id", "top2_status")], by = "team_id")

  header <- c(
    sprintf("## Group standings & advancement (snapshot %s)",
            format(today, "%Y-%m-%d")),
    "",
    "Tournament format: 12 groups of four. The top two of each group plus the",
    "eight best third-placed teams reach the Round of 32.",
    "",
    "Answer standings and advancement questions from the tables below. Do",
    "not recompute them yourself. The `Status` column is authoritative for the",
    "top-two race. The third-place race is provisional while the group stage is",
    "in progress: report it as a current standing / \"in contention\", never as a",
    "guaranteed verdict. A team marked \"(tie)\" is level on every tiebreaker the",
    "data supports; the order then depends on disciplinary (card) records and",
    "FIFA ranking, which are unavailable; say so rather than guess.",
    ""
  )

  group_blocks <- purrr::map_chr(
    sort(unique(st$group_letter)),
    \(g) render_group_block(st[st$group_letter == g, , drop = FALSE], g)
  )

  paste(
    c(header, group_blocks, render_third_place(tp), render_scenarios(adv, matches, teams)),
    collapse = "\n"
  )
}

#' Human-readable label for a `top2_status` value.
#' @noRd
top2_label <- function(x) {
  labels <- c(
    won_group       = "Won group",
    clinched_top2   = "Through (top 2)",
    eliminated_top2 = "Out of top 2",
    alive           = "Still alive"
  )
  out <- unname(labels[x])
  dplyr::coalesce(out, "")
}

#' Render one group's standings table (Markdown), with status and tie flags.
#' @noRd
render_group_block <- function(df, g) {
  title <- sprintf(
    "### Group %s %s",
    g, if (isTRUE(df$group_complete[1])) "(final)" else "(in progress)"
  )
  status <- paste0(top2_label(df$top2_status), ifelse(df$tie_unresolved, " (tie)", ""))
  rows <- sprintf(
    "| %d | %s | %d | %d | %d | %d | %d | %d | %d | %d | %s |",
    df$rank, df$team, df$played, df$won, df$drawn, df$lost,
    df$gf, df$ga, df$gd, df$points, status
  )
  paste(c(
    title,
    "| Rank | Team | P | W | D | L | GF | GA | GD | Pts | Status |",
    "|---|---|---|---|---|---|---|---|---|---|---|",
    rows, ""
  ), collapse = "\n")
}

#' Render the cross-group third-place race table (Markdown).
#' @noRd
render_third_place <- function(tp) {
  if (nrow(tp) == 0L) return("")
  final <- !any(tp$provisional)
  rows <- sprintf(
    "| %d | %s | %s | %d | %d | %d | %d | %s | %s |",
    tp$position, tp$group_letter, tp$team, tp$played, tp$points, tp$gd, tp$gf,
    ifelse(tp$currently_advancing, "yes", "no"),
    ifelse(tp$in_contention, "yes", "")
  )
  note <- if (final) {
    "The top eight advance to the Round of 32."
  } else {
    paste(
      "Top eight are currently advancing, but positions can still change while",
      "groups are in progress; treat this as provisional, not settled."
    )
  }
  paste(c(
    sprintf("### Third-place race %s", if (final) "(final)" else "(provisional)"),
    "| Pos | Group | Team | P | Pts | GD | GF | Advancing? | In contention |",
    "|---|---|---|---|---|---|---|---|---|",
    rows, "", note, ""
  ), collapse = "\n")
}

#' Render one line per still-alive team describing what its own remaining
#' match(es) would mean for a top-two finish.
#' @noRd
render_scenarios <- function(adv, matches, teams) {
  if (all(adv$group_complete)) return("")
  alive <- adv[adv$top2_status == "alive", , drop = FALSE]
  if (nrow(alive) == 0L) return("")

  lines <- purrr::map_chr(seq_len(nrow(alive)), function(i) {
    sc <- tryCatch(
      team_scenario(alive$team[i], matches, teams),
      error = function(e) NULL
    )
    if (is.null(sc) || nrow(sc) == 0L) return(NA_character_)
    detail <- paste(sprintf("%s -> %s", sc$scenario, sc$result), collapse = "; ")
    sprintf("- %s (Group %s): %s", alive$team[i], alive$group_letter[i], detail)
  })
  lines <- lines[!is.na(lines)]
  if (length(lines) == 0L) return("")

  paste(c(
    "### What still-alive teams need (top-two race)",
    "",
    "Each line covers only that team's own remaining group match(es); outcomes",
    "are from the named team's perspective.",
    "",
    lines, ""
  ), collapse = "\n")
}
