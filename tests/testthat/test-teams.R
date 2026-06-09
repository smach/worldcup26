test_that("list_teams() returns a tibble with the expected columns", {
  use_fixtures()
  teams <- list_teams()

  expect_s3_class(teams, "tbl_df")
  expect_named(
    teams,
    c("id", "name", "short_name", "tla", "crest_url")
  )
  expect_gt(nrow(teams), 30)
})

test_that("list_teams() includes the 48 World Cup teams", {
  use_fixtures()
  teams <- list_teams()

  expect_equal(nrow(teams), 48)
  expect_true(all(c("Brazil", "United States", "Mexico", "England") %in% teams$name))
})

test_that("list_teams() is sorted alphabetically by name", {
  use_fixtures()
  teams <- list_teams()
  expect_identical(teams$name, sort(teams$name))
})
