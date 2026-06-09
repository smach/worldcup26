#' List teams competing in the 2026 FIFA World Cup
#'
#' Returns every team currently registered for the tournament in the
#' football-data.org API. Results are cached for one hour by default
#' (configure with the `worldcup26.cache_ttl` option).
#'
#' @return A tibble with one row per team and columns `id`, `name`,
#'   `short_name`, `tla` (three-letter abbreviation), and `crest_url`.
#' @export
#' @examples
#' \dontrun{
#' list_teams()
#' }
list_teams <- function() {
  body <- fwc_get_cached(sprintf("competitions/%s/teams", wc_code()))
  teams <- body$teams %||% list()
  if (length(teams) == 0L) {
    return(empty_teams())
  }
  tibble::tibble(
    id         = purrr::map_int(teams, \(t) as.integer(t$id %||% NA_integer_)),
    name       = purrr::map_chr(teams, \(t) t$name %||% NA_character_),
    short_name = purrr::map_chr(teams, \(t) t$shortName %||% NA_character_),
    tla        = purrr::map_chr(teams, \(t) t$tla %||% NA_character_),
    crest_url  = purrr::map_chr(teams, \(t) t$crest %||% NA_character_)
  ) |>
    dplyr::arrange(.data$name)
}

#' @noRd
empty_teams <- function() {
  tibble::tibble(
    id         = integer(),
    name       = character(),
    short_name = character(),
    tla        = character(),
    crest_url  = character()
  )
}
