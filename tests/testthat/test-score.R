# Reach the internal score_display() helper via :::.
sd <- function(status, home = NA_integer_, away = NA_integer_,
               pk_home = NA_integer_, pk_away = NA_integer_,
               utc_date = as.POSIXct("2026-06-15", tz = "UTC"),
               now = as.POSIXct("2026-06-20", tz = "UTC")) {
  worldcup26:::score_display(
    status = status, home = home, away = away,
    pk_home = pk_home, pk_away = pk_away,
    utc_date = utc_date, now = now
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

test_that("Live statuses report 'in progress'", {
  expect_equal(sd("IN_PLAY"), "in progress")
  expect_equal(sd("PAUSED"), "in progress")
  expect_equal(sd("EXTRA_TIME"), "in progress")
  expect_equal(sd("PENALTY_SHOOTOUT"), "in progress")
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
