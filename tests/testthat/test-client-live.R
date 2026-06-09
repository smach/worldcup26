# Integration test against the live football-data.org API.
# Skipped unless an API key is present and we have network access.

test_that("live API call returns the World Cup team list", {
  skip_on_cran()
  skip_if_offline("api.football-data.org")
  skip_if(Sys.getenv("FOOTBALL_DATA_API_KEY") == "",
          "No FOOTBALL_DATA_API_KEY available")

  withr::local_options(worldcup26.cache_ttl = 60)
  teams <- list_teams()

  expect_s3_class(teams, "tbl_df")
  expect_gt(nrow(teams), 30)
  expect_true(all(c("id", "name", "tla") %in% names(teams)))
})
