#' Built-in alias table mapping common short names to football-data.org
#' canonical team names. Values must match the `name` field returned by
#' the API; the lookup function also falls back to fuzzy substring
#' matching, so this table only needs to cover names a substring search
#' would miss or get wrong.
#' @noRd
team_aliases <- function() {
  list(
    "usa"            = "United States",
    "us"             = "United States",
    "u s a"          = "United States",
    "u s"            = "United States",
    "south korea"    = "South Korea",
    "korea"          = "South Korea",
    "korea republic" = "South Korea",
    "korea south"    = "South Korea",
    "rok"            = "South Korea",
    "iran"           = "Iran",
    "ir iran"        = "Iran",
    "ivory coast"    = "Ivory Coast",
    "cote d ivoire"  = "Ivory Coast",
    "cote divoire"   = "Ivory Coast",
    "czech republic" = "Czechia",
    "cape verde"     = "Cape Verde Islands",
    "cabo verde"     = "Cape Verde Islands",
    "drc"            = "Congo DR",
    "dr congo"       = "Congo DR",
    "uae"            = "United Arab Emirates",
    "uk"             = "England"
  )
}
