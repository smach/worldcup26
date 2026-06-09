#' Fetch every World Cup match from the API.
#'
#' Returns one tidy tibble of all 2026 World Cup matches with score and
#' status information. Used by the team-filtered helpers, but exported
#' so callers can also work with the full schedule directly.
#'
#' @return A tibble of matches with columns `match_id`, `utc_date`,
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

  dplyr::arrange(out, .data$utc_date)
}

#' Full World Cup schedule for one team
#'
#' @param team A team name, short name, three-letter code, or alias
#'   (e.g. `"USA"`, `"United States"`, `"Korea"`).
#' @return A tibble of matches involving that team, ordered by date.
#'   Columns: `match_id`, `utc_date`, `stage`, `group`, `home_team`,
#'   `away_team`, `status`, `score_display`, `venue`.
#' @seealso [team_next_match()], [team_past_results()]
#' @export
#' @examples
#' \dontrun{
#' team_schedule("USA")
#' team_schedule("Brazil")
#' }
team_schedule <- function(team) {
  teams   <- list_teams()
  matched <- resolve_team(team, teams)
  matches <- all_matches()

  filtered <- matches[
    matches$home_team_id %in% matched$id |
      matches$away_team_id %in% matched$id,
  ]
  dplyr::select(
    filtered,
    "match_id", "utc_date", "stage", "group",
    "home_team", "away_team", "status", "score_display", "venue"
  )
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
  sched <- team_schedule(team)
  upcoming <- sched[
    !is.na(sched$utc_date) &
      (sched$utc_date >= now | sched$status %in% live_statuses()) &
      !sched$status %in% c(final_statuses(), inactive_statuses()),
  ]
  if (nrow(upcoming) == 0L) return(upcoming)
  upcoming[1L, ]
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
  sched <- team_schedule(team)
  sched[
    !is.na(sched$utc_date) & sched$utc_date < now &
      !sched$status %in% live_statuses() &
      !sched$status %in% inactive_statuses(),
  ]
}

#' Parse an ISO-8601 UTC string into POSIXct.
#' @noRd
parse_utc <- function(x) {
  as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

#' Today's date in UTC.
#'
#' Match dates (`match_date`) are UTC dates, so date-granularity comparisons
#' must use the UTC "today", not the machine's local date. `Sys.Date()` returns
#' the local date, which can be a day off from UTC in the evening in the
#' Americas.
#' @noRd
utc_today <- function() {
  as.Date(Sys.time(), tz = "UTC")
}

#' @noRd
empty_matches <- function() {
  tibble::tibble(
    match_id      = integer(),
    utc_date      = as.POSIXct(character(), tz = "UTC"),
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
