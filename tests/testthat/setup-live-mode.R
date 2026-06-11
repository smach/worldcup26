# Default the whole suite to free-tier behaviour so tests don't depend on a
# WORLDCUP26_LIVE env var that may happen to be set on the machine running
# them. Individual tests opt into live mode with withr::local_options() or an
# explicit `live = TRUE` argument.
withr::local_options(
  worldcup26.live = FALSE,
  .local_envir = testthat::teardown_env()
)
