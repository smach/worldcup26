#' Fetch every World Cup match from the API.
#'
#' Returns one tidy tibble of all 2026 World Cup matches with score and
#' status information. Used by the team-filtered helpers, but exported
#' so callers can also work with the full schedule directly.
#'
#' @return A tibble of matches. `utc_date` is the raw UTC kickoff instant
#'   (POSIXct, used for ordering); `match_date` (Date) and `kickoff_edt`
#'   (text, e.g. `"9:00 PM EDT"`) present the kickoff in US Eastern, since
#'   every World Cup venue is in North America. Other columns: `match_id`,
#'   `matchday`, `stage`, `group`, `home_team_id`, `home_team`,
#'   `away_team_id`, `away_team`, `status`, `score_display`,
#'   `home_score`, `away_score`, `home_pk`, `away_pk`, `venue`.
#' @export
#' @examples
#' \dontrun{
#' all_matches()
#' }
all_matches <- function() {
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

  out <- add_eastern_cols(out)
  dplyr::arrange(out, .data$utc_date)
}

#' Full World Cup schedule for one team
#'
#' @param team A team name, short name, three-letter code, or alias
#'   (e.g. `"USA"`, `"United States"`, `"Korea"`).
#' @return A tibble of matches involving that team, ordered by date. Times
#'   are presented in US Eastern. Columns: `match_id`, `match_date` (Date,
#'   ET), `kickoff_edt` (text, e.g. `"9:00 PM EDT"`), `stage`, `group`,
#'   `home_team`, `away_team`, `status`, `score_display`, `venue`.
#' @seealso [team_next_match()], [team_past_results()]
#' @export
#' @examples
#' \dontrun{
#' team_schedule("USA")
#' team_schedule("Brazil")
#' }
team_schedule <- function(team) {
  schedule_cols(team_matches(team))
}

#' All matches involving a team, with every column (including the raw
#' `utc_date` instant the team-facing functions filter on).
#' @noRd
team_matches <- function(team) {
  teams   <- list_teams()
  matched <- resolve_team(team, teams)
  matches <- all_matches()

  matches[
    matches$home_team_id %in% matched$id |
      matches$away_team_id %in% matched$id,
  ]
}

#' Select the Eastern-presentation columns shown to users (no raw `utc_date`).
#' `any_of()` keeps this robust when a caller supplies a partial tibble.
#' @noRd
schedule_cols <- function(df) {
  dplyr::select(df, dplyr::any_of(c(
    "match_id", "match_date", "kickoff_edt", "stage", "group",
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
team_next_match <- function(team, now = Sys.time()) {
  sched <- team_matches(team)
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
team_past_results <- function(team, now = Sys.time()) {
  sched <- team_matches(team)
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

#' Format a UTC POSIXct as a 12-hour US Eastern time string, e.g. "9:00 PM EDT".
#'
#' The World Cup runs entirely within Eastern Daylight Time, so the label is
#' always EDT. `%I` zero-pads the hour ("09:00"); strip the leading zero.
#' @noRd
format_kickoff_edt <- function(x) {
  t <- format(x, "%I:%M %p", tz = "America/New_York")
  t <- sub("^0", "", t)
  ifelse(is.na(x), NA_character_, paste0(t, " EDT"))
}

#' Add the Eastern presentation columns (`match_date`, `kickoff_edt`) just
#' after `utc_date`. The instant in `utc_date` is unchanged.
#' @noRd
add_eastern_cols <- function(df) {
  dplyr::mutate(
    df,
    match_date  = as.Date(.data$utc_date, tz = "America/New_York"),
    kickoff_edt = format_kickoff_edt(.data$utc_date),
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
    kickoff_edt   = character(),
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
