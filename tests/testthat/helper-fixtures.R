# Load a fixture file as the parsed JSON list (matching what
# `fwc_get()` would return for the corresponding endpoint).
load_fixture <- function(name) {
  jsonlite::fromJSON(
    test_path("fixtures", name),
    simplifyVector = FALSE
  )
}

# Build a stub for `fwc_get_cached()` (and the underlying `fwc_get()`)
# that maps API paths to fixture files. Returns a function suitable
# for use with `local_mocked_bindings()`.
fixture_stub <- function(map = list(
  "competitions/WC/teams"   = "teams.json",
  "competitions/WC/matches" = "matches.json"
)) {
  function(path, query = list()) {
    file <- map[[path]]
    if (is.null(file)) stop("unmapped path in fixture stub: ", path)
    load_fixture(file)
  }
}

# Convenience wrapper: install the fixture stub for the duration of
# the calling test. Falls back gracefully if `local_mocked_bindings()`
# is unavailable.
use_fixtures <- function(env = parent.frame()) {
  testthat::local_mocked_bindings(
    fwc_get_cached = fixture_stub(),
    .package = "worldcup26",
    .env = env
  )
}
