#' Cache for API responses.
#'
#' Populated lazily on first use via [memoise::memoise()] backed by
#' [cachem::cache_disk()]. TTL is configurable via the
#' `worldcup26.cache_ttl` option (seconds); the default is 1 hour on the
#' free tier and 60 seconds in live mode (see [live_mode()]).
#' @noRd
.cache_state <- new.env(parent = emptyenv())

#' Build (or return) the memoised version of `fwc_get()`.
#' @noRd
memoised_fwc_get <- function() {
  if (!is.null(.cache_state$fn)) {
    return(.cache_state$fn)
  }
  # Live mode needs near-fresh data; the explicit option still wins.
  ttl <- getOption("worldcup26.cache_ttl", if (live_mode()) 60 else 3600)
  dir <- getOption(
    "worldcup26.cache_dir",
    tools::R_user_dir("worldcup26", which = "cache")
  )
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  cache <- cachem::cache_disk(dir = dir, max_age = ttl)
  .cache_state$cache <- cache
  .cache_state$fn <- memoise::memoise(fwc_get, cache = cache)
  .cache_state$fn
}

#' Fetch via the cache; transparent wrapper used by all callers.
#' @noRd
fwc_get_cached <- function(path, query = list()) {
  memoised_fwc_get()(path, query)
}

#' Clear the on-disk response cache.
#'
#' Removes every cached API response. Useful when fresh data is needed
#' before the TTL expires (e.g., after a match has just finished).
#'
#' @return Invisibly `TRUE`.
#' @export
#' @examples
#' \dontrun{
#' clear_cache()
#' }
clear_cache <- function() {
  if (!is.null(.cache_state$cache)) {
    .cache_state$cache$reset()
  }
  if (!is.null(.cache_state$fn)) {
    memoise::forget(.cache_state$fn)
  }
  invisible(TRUE)
}
