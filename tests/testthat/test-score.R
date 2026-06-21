# Reach the internal score_display() helper via :::. `live` defaults to
# FALSE so the existing free-tier expectations don't depend on the
# WORLDCUP26_LIVE env var of whatever machine runs the tests.
sd <- function(status, home = NA_integer_, away = NA_integer_,
               pk_home = NA_integer_, pk_away = NA_integer_,
               utc_date = as.POSIXct("2026-06-15", tz = "UTC"),
               now = as.POSIXct("2026-06-20", tz = "UTC"),
               minute = NA_integer_, injury = NA_integer_,
               live = FALSE) {
  worldcup26:::score_display(
    status = status, home = home, away = away,
    pk_home = pk_home, pk_away = pk_away,
    utc_date = utc_date, now = now,
    minute = minute, injury = injury, live = live
  )
}

test_that("FINISHED with a score is formatted as a dash-separated line", {
  expect_equal(sd("FINISHED", 2L, 1L), "2–1")
})

test_that("FINISHED with no score reports 'no score available yet'", {
  expect_equal(sd("FINISHED"), "no score available yet")
})

test_that("Penalty shoot-out result is appended", {
  expect_equal(
    sd("FINISHED", 1L, 1L, pk_home = 4L, pk_away = 3L),
    "1–1 (4–3 PK)"
  )
})

test_that("Live statuses report 'in progress' on the free tier", {
  expect_equal(sd("IN_PLAY"), "in progress")
  expect_equal(sd("PAUSED"), "in progress")
  expect_equal(sd("EXTRA_TIME"), "in progress")
  expect_equal(sd("PENALTY_SHOOTOUT"), "in progress")
})

test_that("Live mode shows a running scoreline when a score is present", {
  expect_equal(sd("IN_PLAY", 1L, 0L, live = TRUE), "1–0 (live)")
  expect_equal(sd("PAUSED", 2L, 2L, live = TRUE), "2–2 (live)")
})

test_that("Live mode falls back to 'in progress' before the first goal", {
  expect_equal(sd("IN_PLAY", live = TRUE), "in progress")
})

test_that("Live mode appends the match clock when a minute is available", {
  expect_equal(sd("IN_PLAY", 1L, 0L, minute = 67L, live = TRUE), "1–0 (live 67')")
  expect_equal(sd("IN_PLAY", 0L, 0L, minute = 80L, live = TRUE), "0–0 (live 80')")
})

test_that("Injury time is shown as minute+added", {
  expect_equal(sd("IN_PLAY", 1L, 1L, minute = 45L, injury = 2L, live = TRUE), "1–1 (live 45+2')")
  # injuryTime of 0 (or NA) means no stoppage time to show.
  expect_equal(sd("IN_PLAY", 1L, 1L, minute = 45L, injury = 0L, live = TRUE), "1–1 (live 45')")
})

test_that("The clock rides along even before the first goal", {
  expect_equal(sd("IN_PLAY", minute = 12L, live = TRUE), "in progress (12')")
})

test_that("A missing minute leaves the scoreline unchanged", {
  expect_equal(sd("IN_PLAY", 2L, 1L, live = TRUE), "2–1 (live)")
})

test_that("score_display() defaults the live flag from live_mode()", {
  withr::local_options(worldcup26.live = TRUE)
  expect_equal(
    worldcup26:::score_display(
      "IN_PLAY", 3L, 1L, NA_integer_, NA_integer_,
      utc_date = as.POSIXct("2026-06-15", tz = "UTC"),
      now = as.POSIXct("2026-06-15 01:00", tz = "UTC")
    ),
    "3–1 (live)"
  )
})

test_that("SCHEDULED in the future is blank, in the past is 'no score available yet'", {
  future <- as.POSIXct("2026-07-01", tz = "UTC")
  past   <- as.POSIXct("2026-06-12", tz = "UTC")
  now    <- as.POSIXct("2026-06-15", tz = "UTC")
  expect_equal(sd("SCHEDULED", utc_date = future, now = now), "")
  expect_equal(sd("TIMED",     utc_date = future, now = now), "")
  expect_equal(sd("SCHEDULED", utc_date = past,   now = now), "no score available yet")
})

test_that("Off-pitch statuses are lower-cased", {
  expect_equal(sd("POSTPONED"), "postponed")
  expect_equal(sd("CANCELLED"), "cancelled")
  expect_equal(sd("SUSPENDED"), "suspended")
})

test_that("score_display() is vectorised", {
  out <- worldcup26:::score_display(
    status   = c("FINISHED", "IN_PLAY", "TIMED"),
    home     = c(3L, NA, NA),
    away     = c(2L, NA, NA),
    pk_home  = c(NA, NA, NA),
    pk_away  = c(NA, NA, NA),
    utc_date = as.POSIXct(c("2026-06-12", "2026-06-15", "2026-07-01"), tz = "UTC"),
    now      = as.POSIXct("2026-06-15", tz = "UTC")
  )
  expect_equal(out, c("3–2", "in progress", ""))
})
