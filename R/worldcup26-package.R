#' worldcup26: FIFA 2026 World Cup Schedule and Results
#'
#' An R wrapper for the football-data.org v4 API focused on the
#' 2026 FIFA Men's World Cup. The package provides eight user-facing
#' functions:
#'
#' * [list_teams()] -- every team competing in the tournament
#' * [team_schedule()] -- a team's full schedule
#' * [team_next_match()] -- a team's next upcoming match
#' * [team_past_results()] -- a team's matches that have already occurred
#' * [all_matches()] -- every World Cup match in one tibble
#' * [chat_data()] -- flat matches table used by the chat dashboard
#' * [worldcup26_chat()] -- natural-language chat dashboard
#' * [clear_cache()] -- drop cached API responses
#'
#' Set your API key in the `FOOTBALL_DATA_API_KEY` environment variable
#' (e.g. in `~/.Renviron`). Get a free key at
#' <https://www.football-data.org/client/register>.
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom rlang .data %||%
## usethis namespace: end
NULL

# Quiet R CMD check about pipe and tidy-eval pronouns.
utils::globalVariables(c("."))
