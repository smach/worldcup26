#' Is the package configured for the paid "live scores" tier?
#'
#' The package defaults to football-data.org's free tier, which returns
#' delayed scores. Set the `WORLDCUP26_LIVE` environment variable (to
#' `"true"`, `"1"`, `"yes"`, or `"on"`) to opt into live-scores behaviour:
#' a short cache TTL, running scorelines for in-play matches, and live
#' wording on the site and chat. Requires a paid API key in
#' `FOOTBALL_DATA_API_KEY`.
#'
#' The `worldcup26.live` option (TRUE/FALSE) overrides the environment
#' variable when set; it's handy in tests and inside the Quarto render.
#'
#' @return A length-one logical.
#' @noRd
live_mode <- function() {
  opt <- getOption("worldcup26.live", NA)
  if (isTRUE(opt) || isFALSE(opt)) {
    return(isTRUE(opt))
  }
  tolower(Sys.getenv("WORLDCUP26_LIVE", "")) %in% c("true", "1", "yes", "on")
}
