#' Fetch every World Cup match from the API.
#'
#' Returns one tidy tibble of all 2026 World Cup matches with score and
#' status information. Used by the team-filtered helpers, but exported
#' so callers can also work with the full schedule directly.
#'
#' @param tz A single time-zone name (see [OlsonNames()]) used for the
#'   `match_date` and `kickoff` display columns. Defaults to
#'   `"America/New_York"` (US Eastern), since every World Cup venue is in
#'   North America. The raw `utc_date` instant is unaffected.
#' @return A tibble of matches. `utc_date` is the raw UTC kickoff instant
#'   (POSIXct, used for ordering); `match_date` (Date) and `kickoff`
#'   (text, e.g. `"9:00 PM EDT"`) present the kickoff in `tz`. Other
#'   columns: `match_id`, `matchday`, `stage`, `group`, `home_team_id`,
#'   `home_team`, `away_team_id`, `away_team`, `status`, `score_display`,
#'   `home_score`, `away_score`, `home_pk`, `away_pk`, `venue`.
#' @export
#' @examples
#' \dontrun{
#' all_matches()
#' all_matches(tz = "America/Los_Angeles")
#' }
all_matches <- function(tz = "America/New_York") {
  validate_tz(tz)
  body <- fwc_get_cached(sprintf("competitions/%s/matches", wc_code()))
  matches <- body$matches %||% list()
  if (length(matches) == 0L) {
    return(empty_matches())
  }

  out <- tibble::tibble(
    match_id     = purrr::map_int(matches, \(m) as.integer(m$id %||% NA_integer_)),
    utc_date     = parse_utc(purrr::map_chr(matches, \(m) m$utcDate %||% NA_character_)),
    matchday     = purrr::map_int(matches, \(m) as.integer(m$matchday %||% NA_integer_)),
    stage        = purrr::map_chr(matches, \(m) m$stage %||% NA_character_),
    group        = purrr::map_chr(matches, \(m) m$group %||% NA_character_),
    home_team_id = purrr::map_int(matches, \(m) as.integer(m$homeTeam$id %||% NA_integer_)),
    home_team    = purrr::map_chr(matches, \(m) m$homeTeam$name %||% NA_character_),
    away_team_id = purrr::map_int(matches, \(m) as.integer(m$awayTeam$id %||% NA_integer_)),
    away_team    = purrr::map_chr(matches, \(m) m$awayTeam$name %||% NA_character_),
    status       = purrr::map_chr(matches, \(m) m$status %||% NA_character_),
    home_score   = purrr::map_int(matches, \(m) as.integer(m$score$fullTime$home %||% NA_integer_)),
    away_score   = purrr::map_int(matches, \(m) as.integer(m$score$fullTime$away %||% NA_integer_)),
    home_pk      = purrr::map_int(matches, \(m) as.integer(m$score$penalties$home %||% NA_integer_)),
    away_pk      = purrr::map_int(matches, \(m) as.integer(m$score$penalties$away %||% NA_integer_)),
    venue        = purrr::map_chr(matches, \(m) m$venue %||% NA_character_)
  )

  out$score_display <- score_display(
    status   = out$status,
    home     = out$home_score,
    away     = out$away_score,
    pk_home  = out$home_pk,
    pk_away  = out$away_pk,
    utc_date = out$utc_date
  )

  out <- add_local_cols(out, tz)
  dplyr::arrange(out, .data$utc_date)
}

#' Full World Cup schedule for one team
#'
#' @param team A team name, short name, three-letter code, or alias
#'   (e.g. `"USA"`, `"United States"`, `"Korea"`).
#' @param tz A single time-zone name (see [OlsonNames()]) used for the
#'   `match_date` and `kickoff` display columns. Defaults to
#'   `"America/New_York"` (US Eastern).
#' @return A tibble of matches involving that team, ordered by date. Times
#'   are presented in `tz`. Columns: `match_id`, `match_date` (Date),
#'   `kickoff` (text, e.g. `"9:00 PM EDT"`), `stage`, `group`,
#'   `home_team`, `away_team`, `status`, `score_display`, `venue`.
#' @seealso [team_next_match()], [team_past_results()]
#' @export
#' @examples
#' \dontrun{
#' team_schedule("USA")
#' team_schedule("Brazil")
#' team_schedule("USA", tz = "America/Los_Angeles")
#' }
team_schedule <- function(team, tz = "America/New_York") {
  schedule_cols(team_matches(team, tz))
}

#' All matches involving a team, with every column (including the raw
#' `utc_date` instant the team-facing functions filter on).
#' @noRd
team_matches <- function(team, tz = "America/New_York") {
  teams   <- list_teams()
  matched <- resolve_team(team, teams)
  matches <- all_matches(tz)

  matches[
    matches$home_team_id %in% matched$id |
      matches$away_team_id %in% matched$id,
  ]
}

#' Select the local-time presentation columns shown to users (no raw `utc_date`).
#' `any_of()` keeps this robust when a caller supplies a partial tibble.
#' @noRd
schedule_cols <- function(df) {
  dplyr::select(df, dplyr::any_of(c(
    "match_id", "match_date", "kickoff", "stage", "group",
    "home_team", "away_team", "status", "score_display", "venue"
  )))
}

#' A team's next upcoming match
#'
#' Returns the earliest match that has not yet started (or is still in
#' progress). If no upcoming matches remain, returns an empty tibble.
#'
#' @inheritParams team_schedule
#' @param now The reference time used to determine whether a match is
#'   upcoming. Defaults to [Sys.time()].
#' @return A one-row tibble in the same shape as [team_schedule()], or
#'   an empty tibble if no upcoming matches are scheduled.
#' @export
#' @examples
#' \dontrun{
#' team_next_match("Brazil")
#' }
team_next_match <- function(team, now = Sys.time(), tz = "America/New_York") {
  sched <- team_matches(team, tz)
  upcoming <- sched[
    !is.na(sched$utc_date) &
      (sched$utc_date >= now | sched$status %in% live_statuses()) &
      !sched$status %in% c(final_statuses(), inactive_statuses()),
  ]
  if (nrow(upcoming) == 0L) return(schedule_cols(upcoming))
  schedule_cols(upcoming[1L, ])
}

#' A team's past results
#'
#' Returns matches whose scheduled date is in the past. Matches with
#' `status = "FINISHED"` and missing scores get a `score_display` of
#' `"no score available yet"`; live matches show `"in progress"`.
#'
#' @inheritParams team_schedule
#' @param now The reference time used to determine whether a match is in
#'   the past. Defaults to [Sys.time()].
#' @return A tibble in the same shape as [team_schedule()], ordered with
#'   the most recent match last.
#' @export
#' @examples
#' \dontrun{
#' team_past_results("Argentina")
#' }
team_past_results <- function(team, now = Sys.time(), tz = "America/New_York") {
  sched <- team_matches(team, tz)
  past <- sched[
    !is.na(sched$utc_date) & sched$utc_date < now &
      !sched$status %in% live_statuses() &
      !sched$status %in% inactive_statuses(),
  ]
  schedule_cols(past)
}

#' Parse an ISO-8601 UTC string into POSIXct.
#' @noRd
parse_utc <- function(x) {
  as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

#' Validate a time-zone argument. Returns `tz` invisibly so it can be
#' used inline; aborts with a clear message if it isn't a known zone.
#' @noRd
validate_tz <- function(tz) {
  if (!is.character(tz) || length(tz) != 1L || is.na(tz) || !tz %in% OlsonNames()) {
    cli::cli_abort(c(
      "{.arg tz} must be a single valid time-zone name.",
      i = "See {.run OlsonNames()} for the full list (e.g. {.val America/New_York})."
    ))
  }
  invisible(tz)
}

#' Short zone abbreviations for the 2026 tournament window.
#'
#' The World Cup runs entirely within one DST period (June 11 - July 19,
#' 2026), so a static lookup is correct for the supported zones and avoids
#' the platform-dependent `%Z` strftime code (which prints long names like
#' "Eastern Daylight Time" on Windows).
#' @noRd
tz_abbr_2026 <- c(
  "UTC"                 = "UTC",
  "America/New_York"    = "EDT",
  "America/Chicago"     = "CDT",
  "America/Denver"      = "MDT",
  "America/Los_Angeles" = "PDT",
  "America/Mexico_City" = "CST",
  "America/Sao_Paulo"   = "-03",
  "Europe/London"       = "BST",
  "Europe/Paris"        = "CEST",
  "Europe/Athens"       = "EEST",
  "Europe/Moscow"       = "MSK",
  "Asia/Dubai"          = "+04",
  "Asia/Kolkata"        = "IST",
  "Asia/Tokyo"          = "JST",
  "Asia/Shanghai"       = "CST",
  "Australia/Sydney"    = "AEST",
  "Pacific/Auckland"    = "NZST"
)

#' Short label for a zone, falling back to the OS `%Z` value for any zone
#' not in the static table.
#' @noRd
tz_label <- function(x, tz) {
  if (tz %in% names(tz_abbr_2026)) {
    tz_abbr_2026[[tz]]
  } else {
    format(x, "%Z", tz = tz)
  }
}

#' Format a UTC POSIXct as a 12-hour local time string, e.g. "9:00 PM EDT".
#'
#' `%I` zero-pads the hour ("09:00"); strip the leading zero. The zone label
#' comes from [tz_label()].
#' @noRd
format_kickoff <- function(x, tz = "America/New_York") {
  t <- format(x, "%I:%M %p", tz = tz)
  t <- sub("^0", "", t)
  label <- tz_label(x, tz)
  ifelse(is.na(x), NA_character_, paste0(t, " ", label))
}

#' Add the local-time presentation columns (`match_date`, `kickoff`) just
#' after `utc_date`. The instant in `utc_date` is unchanged.
#' @noRd
add_local_cols <- function(df, tz = "America/New_York") {
  dplyr::mutate(
    df,
    match_date = as.Date(.data$utc_date, tz = tz),
    kickoff    = format_kickoff(.data$utc_date, tz),
    .after = "utc_date"
  )
}

#' Today's date in US Eastern time.
#'
#' The chat presents match dates in US Eastern (every World Cup venue is in
#' North America), so date-granularity comparisons must use the Eastern "today",
#' not the machine's local date or UTC.
#' @noRd
eastern_today <- function() {
  as.Date(Sys.time(), tz = "America/New_York")
}

#' @noRd
empty_matches <- function() {
  tibble::tibble(
    match_id      = integer(),
    utc_date      = as.POSIXct(character(), tz = "UTC"),
    match_date    = as.Date(character()),
    kickoff       = character(),
    matchday      = integer(),
    stage         = character(),
    group         = character(),
    home_team_id  = integer(),
    home_team     = character(),
    away_team_id  = integer(),
    away_team     = character(),
    status        = character(),
    home_score    = integer(),
    away_score    = integer(),
    home_pk       = integer(),
    away_pk       = integer(),
    venue         = character(),
    score_display = character()
  )
}
