#' Normalise a string for fuzzy team lookup.
#' Lower-cases, strips accents and any non-alphanumeric characters.
#' @noRd
normalise_name <- function(x) {
  x <- as.character(x)
  x <- stringi::stri_trans_general(x, "Any-Latin; Latin-ASCII")
  x <- tolower(x)
  x <- gsub("[^a-z0-9]", "", x)
  x
}

#' Resolve a user-supplied team name to a row of the team table.
#'
#' Matches in this priority:
#' 1. Exact normalised match against `name`, `short_name`, or `tla`.
#' 2. Alias-table mapping, then exact match again.
#' 3. Substring match against `name` / `short_name` (must be unique).
#'
#' @param team A character scalar -- team name, short name, three-letter
#'   code, or common alias (e.g. `"USA"`).
#' @param teams A teams tibble as returned by [list_teams()]. When `NULL`
#'   (the default), teams are fetched.
#' @return A single-row tibble from the teams table.
#' @noRd
resolve_team <- function(team, teams = NULL) {
  if (!is.character(team) || length(team) != 1L || is.na(team) || !nzchar(team)) {
    cli::cli_abort("{.arg team} must be a non-empty character string.")
  }
  if (is.null(teams)) teams <- list_teams()

  needle <- normalise_name(team)

  # 1. Direct exact match on name / short_name / tla.
  hit <- teams[
    normalise_name(teams$name) == needle |
      normalise_name(teams$short_name) == needle |
      normalise_name(teams$tla) == needle,
  ]
  if (nrow(hit) == 1L) return(hit)
  if (nrow(hit) > 1L) return(disambiguate(team, hit))

  # 2. Alias table.
  aliases <- team_aliases()
  alias_key <- stringi::stri_trans_general(team, "Any-Latin; Latin-ASCII")
  alias_key <- tolower(alias_key)
  alias_key <- gsub("[^a-z ]", " ", alias_key)
  alias_key <- gsub("\\s+", " ", trimws(alias_key))
  if (!is.null(aliases[[alias_key]])) {
    canonical <- normalise_name(aliases[[alias_key]])
    hit <- teams[normalise_name(teams$name) == canonical, ]
    if (nrow(hit) == 1L) return(hit)
  }

  # 3. Substring match.
  candidate <- normalise_name(teams$name)
  matches <- grepl(needle, candidate, fixed = TRUE)
  hit <- teams[matches, ]
  if (nrow(hit) == 1L) return(hit)
  if (nrow(hit) > 1L) return(disambiguate(team, hit))

  cli::cli_abort(c(
    "No team matching {.val {team}} was found.",
    i = "Use {.fn list_teams} to see all participating teams."
  ))
}

#' Throw an informative error when more than one team matches.
#' @noRd
disambiguate <- function(team, hits) {
  cli::cli_abort(c(
    "{.val {team}} matches multiple teams.",
    i = "Be more specific. Possible matches:",
    set_names(hits$name, rep("*", nrow(hits)))
  ))
}

#' Local copy of `rlang::set_names()` to avoid an extra import.
#' @noRd
set_names <- function(x, nm) {
  names(x) <- nm
  x
}
