test_that("chat_data() returns the expected columns and row count", {
  use_fixtures()
  d <- chat_data(today = as.Date("2026-05-11"))

  expect_s3_class(d, "tbl_df")
  expect_equal(nrow(d), 104)
  expect_true(all(c(
    "match_id", "utc_date", "match_date", "kickoff_utc", "matchday",
    "stage", "stage_label", "knockout", "group_letter",
    "home_team", "home_tla", "away_team", "away_tla",
    "status", "score_display",
    "home_score", "away_score", "home_pk", "away_pk",
    "is_finished", "is_upcoming", "is_today", "venue"
  ) %in% names(d)))
})

test_that("chat_data() column types are the ones the chat expects", {
  use_fixtures()
  d <- chat_data(today = as.Date("2026-05-11"))

  expect_s3_class(d$utc_date, "POSIXct")
  expect_s3_class(d$match_date, "Date")
  expect_type(d$knockout,    "logical")
  expect_type(d$is_finished, "logical")
  expect_type(d$is_upcoming, "logical")
  expect_type(d$is_today,    "logical")
})

test_that("chat_data() attaches three-letter codes for known teams", {
  use_fixtures()
  d <- chat_data(today = as.Date("2026-05-11"))

  usa <- d[d$home_team == "United States" & !is.na(d$home_team), ][1, ]
  expect_equal(usa$home_tla, "USA")
})

test_that("chat_data() labels stages and group letters correctly", {
  use_fixtures()
  d <- chat_data(today = as.Date("2026-05-11"))

  group_row <- d[d$stage == "GROUP_STAGE", ][1, ]
  expect_equal(group_row$stage_label, "Group stage")
  expect_false(group_row$knockout)
  expect_match(group_row$group_letter, "^[A-L]$")

  final_row <- d[d$stage == "FINAL", ][1, ]
  expect_equal(final_row$stage_label, "Final")
  expect_true(final_row$knockout)
  expect_true(is.na(final_row$group_letter))
})

test_that("chat_data() flags is_today against the reference date", {
  use_fixtures()
  d <- chat_data(today = as.Date("2026-06-11"))
  expect_true(any(d$is_today))
  expect_true(all(
    d$match_date[d$is_today] == as.Date("2026-06-11")
  ))
})

test_that("chat_data() only flags genuinely upcoming matches", {
  matches <- tibble::tibble(
    match_id = 1:6,
    utc_date = as.POSIXct(c(
      "2026-06-01 12:00:00", "2026-06-06 12:00:00",
      "2026-06-07 12:00:00", "2026-06-07 13:00:00",
      "2026-06-07 14:00:00", "2026-06-07 15:00:00"
    ), tz = "UTC"),
    matchday = 1L,
    stage = "GROUP_STAGE",
    group = "GROUP_A",
    home_team_id = 1L,
    home_team = "A",
    away_team_id = 2L,
    away_team = "B",
    status = c(
      "TIMED", "IN_PLAY", "TIMED", "CANCELLED", "POSTPONED", "SUSPENDED"
    ),
    home_score = NA_integer_,
    away_score = NA_integer_,
    home_pk = NA_integer_,
    away_pk = NA_integer_,
    venue = NA_character_,
    score_display = ""
  )
  teams <- tibble::tibble(
    id = c(1L, 2L),
    name = c("A", "B"),
    short_name = c("A", "B"),
    tla = c("AAA", "BBB"),
    crest_url = NA_character_
  )

  d <- chat_data(matches, teams, today = as.Date("2026-06-06"))

  expect_identical(d$is_upcoming, c(FALSE, TRUE, TRUE, FALSE, FALSE, FALSE))
})

test_that("worldcup26_chat() errors clearly when the API key is missing", {
  use_fixtures()
  withr::with_envvar(
    list(ANTHROPIC_API_KEY = ""),
    expect_error(worldcup26_chat(), "Anthropic API key")
  )
})
