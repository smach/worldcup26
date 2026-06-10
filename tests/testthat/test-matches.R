test_that("all_matches() returns a tibble of every match", {
  use_fixtures()
  matches <- all_matches()

  expect_s3_class(matches, "tbl_df")
  expect_equal(nrow(matches), 104)
  expect_true(all(
    c("match_id", "utc_date", "home_team", "away_team", "status",
      "score_display", "stage", "group") %in% names(matches)
  ))
  expect_s3_class(matches$utc_date, "POSIXct")
})

test_that("all_matches() is sorted chronologically", {
  use_fixtures()
  matches <- all_matches()
  expect_identical(matches$utc_date, sort(matches$utc_date))
})

test_that("team_schedule() returns only matches involving the team", {
  use_fixtures()
  usa <- team_schedule("USA")

  expect_s3_class(usa, "tbl_df")
  expect_gt(nrow(usa), 0)
  expect_true(all(
    usa$home_team == "United States" | usa$away_team == "United States"
  ))
})

test_that("team_schedule() returns the expected USA group-stage opponents", {
  use_fixtures()
  usa <- team_schedule("USA")
  opponents <- ifelse(usa$home_team == "United States", usa$away_team, usa$home_team)
  expect_setequal(opponents, c("Paraguay", "Australia", "Turkey"))
})

test_that("team_schedule() works with the canonical name, an alias, and a TLA", {
  use_fixtures()
  by_name  <- team_schedule("United States")
  by_alias <- team_schedule("USA")
  by_tla   <- team_schedule("usa")
  expect_identical(by_name$match_id, by_alias$match_id)
  expect_identical(by_name$match_id, by_tla$match_id)
})

test_that("team_next_match() uses the supplied reference time", {
  use_fixtures()
  nxt <- team_next_match(
    "Brazil",
    now = as.POSIXct("2026-06-01", tz = "UTC")
  )

  expect_s3_class(nxt, "tbl_df")
  expect_equal(nrow(nxt), 1L)
  expect_true("Brazil" %in% c(nxt$home_team, nxt$away_team))
  expect_false("utc_date" %in% names(nxt))
  expect_gte(nxt$match_date, as.Date("2026-06-01"))

  none <- team_next_match(
    "Brazil",
    now = as.POSIXct("2026-08-01", tz = "UTC")
  )
  expect_equal(nrow(none), 0L)
})

test_that("team_past_results() uses the supplied reference time", {
  use_fixtures()
  now <- as.POSIXct("2026-07-01", tz = "UTC")
  past <- team_past_results("Argentina", now = now)

  expect_s3_class(past, "tbl_df")
  expect_gt(nrow(past), 0L)
  expect_false("utc_date" %in% names(past))
  # now is 2026-07-01 00:00 UTC == 2026-06-30 EDT, so every past match's
  # Eastern date is strictly before July 1.
  expect_true(all(past$match_date < as.Date("2026-07-01")))
})

test_that("live matches are upcoming rather than past results", {
  schedule <- tibble::tibble(
    match_id = 1:4,
    utc_date = as.POSIXct(c(
      "2026-06-06 12:00:00", "2026-06-07 12:00:00",
      "2026-06-07 13:00:00", "2026-06-07 14:00:00"
    ), tz = "UTC"),
    stage = "GROUP_STAGE",
    group = "GROUP_A",
    home_team = "A",
    away_team = "B",
    status = c("IN_PLAY", "CANCELLED", "POSTPONED", "SUSPENDED"),
    score_display = c("in progress", "cancelled", "postponed", "suspended"),
    venue = NA_character_
  )
  testthat::local_mocked_bindings(
    team_matches = function(team) {
      if (team == "inactive") schedule[-1, ] else schedule
    },
    .package = "worldcup26"
  )
  now <- as.POSIXct("2026-06-06 13:00:00", tz = "UTC")

  expect_equal(team_next_match("A", now = now)$status, "IN_PLAY")
  expect_equal(nrow(team_past_results("A", now = now)), 0L)
  expect_equal(nrow(team_next_match("inactive", now = now)), 0L)
})
