# live_mode() reads the WORLDCUP26_LIVE env var, with the
# worldcup26.live option taking precedence when set.

test_that("WORLDCUP26_LIVE truthy values enable live mode", {
  withr::local_options(worldcup26.live = NULL)
  for (v in c("true", "TRUE", "1", "yes", "on")) {
    withr::local_envvar(WORLDCUP26_LIVE = v)
    expect_true(worldcup26:::live_mode(), info = v)
  }
})

test_that("WORLDCUP26_LIVE falsey/unset values keep free mode", {
  withr::local_options(worldcup26.live = NULL)
  for (v in c("", "false", "0", "no", "off", "nope")) {
    withr::local_envvar(WORLDCUP26_LIVE = v)
    expect_false(worldcup26:::live_mode(), info = v)
  }
})

test_that("worldcup26.live option overrides the env var", {
  withr::local_envvar(WORLDCUP26_LIVE = "true")
  withr::local_options(worldcup26.live = FALSE)
  expect_false(worldcup26:::live_mode())

  withr::local_envvar(WORLDCUP26_LIVE = "")
  withr::local_options(worldcup26.live = TRUE)
  expect_true(worldcup26:::live_mode())
})
