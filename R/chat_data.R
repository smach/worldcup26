#' Build the flat matches table used by the chat dashboard
#'
#' Returns a denormalised data frame with one row per match and a set of
#' derived columns that make natural-language SQL queries straightforward
#' (today flags, three-letter codes, group letter, finished/upcoming
#' booleans, etc.).
#'
#' This is the same data the chat in [worldcup26_chat()] sees. You can
#' call it directly if you want to inspect what the LLM is working with.
#'
#' @param matches A matches tibble. Defaults to [all_matches()].
#' @param teams A teams tibble. Defaults to [list_teams()]. Used to attach
#'   three-letter codes (`home_tla`, `away_tla`) to each row.
#' @param today The reference date for the `is_today` flag and for
#'   computing pastness/upcomingness. A UTC date (to match `match_date`,
#'   which is in UTC). Defaults to today's date in UTC.
#' @return A tibble of matches.
#' @export
#' @examples
#' \dontrun{
#' chat_data()
#' }
chat_data <- function(
  matches = all_matches(),
  teams = list_teams(),
  today = utc_today()
) {
  tla_by_id <- stats::setNames(teams$tla, as.character(teams$id))

  out <- matches |>
    dplyr::mutate(
      match_date = as.Date(.data$utc_date),
      kickoff_utc = format(.data$utc_date, "%H:%M UTC"),
      home_tla = unname(tla_by_id[as.character(.data$home_team_id)]),
      away_tla = unname(tla_by_id[as.character(.data$away_team_id)]),
      group_letter = ifelse(
        is.na(.data$group),
        NA_character_,
        sub("^GROUP_", "", .data$group)
      ),
      stage_label = stage_to_label(.data$stage),
      knockout = !is.na(.data$stage) & .data$stage != "GROUP_STAGE",
      is_finished = .data$status %in% final_statuses(),
      is_upcoming = !.data$is_finished &
        !.data$status %in% inactive_statuses() &
        (.data$match_date >= today | .data$status %in% live_statuses()),
      is_today = !is.na(.data$match_date) & .data$match_date == today
    ) |>
    dplyr::select(
      "match_id",
      "utc_date",
      "match_date",
      "kickoff_utc",
      "matchday",
      "stage",
      "stage_label",
      "knockout",
      "group_letter",
      "home_team",
      "home_tla",
      "away_team",
      "away_tla",
      "status",
      "score_display",
      "home_score",
      "away_score",
      "home_pk",
      "away_pk",
      "is_finished",
      "is_upcoming",
      "is_today",
      "venue"
    )

  out
}

#' @noRd
stage_to_label <- function(stage) {
  # Unmatched values (including NA) pass through unchanged via `default`.
  dplyr::recode_values(
    stage,
    "GROUP_STAGE" ~ "Group stage",
    "LAST_32" ~ "Round of 32",
    "LAST_16" ~ "Round of 16",
    "QUARTER_FINALS" ~ "Quarter-finals",
    "SEMI_FINALS" ~ "Semi-finals",
    "THIRD_PLACE" ~ "Third-place playoff",
    "FINAL" ~ "Final",
    default = stage
  )
}
