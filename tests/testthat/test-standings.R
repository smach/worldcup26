# Synthetic group fixtures. The shipped matches.json fixture is pre-tournament
# (no scores), so standings/advancement are tested with hand-built groups whose
# outcomes we can reason about exactly. See test-chat-data.R for the same
# inline-tibble pattern.

# Build a matches tibble (all_matches() shape, only the columns these functions
# use) from rows of: group letter, home id, away id, home score, away score,
# status. Team names/codes are derived from ids.
build_matches <- function(rows) {
  df <- do.call(rbind, lapply(rows, function(r) {
    data.frame(
      group = r$group, home_id = r$home, away_id = r$away,
      hs = r$hs, as = r$as,
      status = r$status %||% "FINISHED",
      stringsAsFactors = FALSE
    )
  }))
  tibble::tibble(
    match_id     = seq_len(nrow(df)),
    stage        = "GROUP_STAGE",
    group        = paste0("GROUP_", df$group),
    home_team_id = df$home_id,
    home_team    = paste0("Team", df$home_id),
    away_team_id = df$away_id,
    away_team    = paste0("Team", df$away_id),
    status       = df$status,
    home_score   = ifelse(df$status == "FINISHED", df$hs, NA_integer_),
    away_score   = ifelse(df$status == "FINISHED", df$as, NA_integer_),
    home_pk      = NA_integer_,
    away_pk      = NA_integer_
  )
}

m <- function(group, home, away, hs = NA, as = NA, status = "FINISHED") {
  list(group = group, home = home, away = away, hs = hs, as = as, status = status)
}

# Teams covering every id used below.
build_teams <- function(ids) {
  tibble::tibble(
    id         = ids,
    name       = paste0("Team", ids),
    short_name = paste0("Team", ids),
    tla        = sprintf("T%02d", ids),
    crest_url  = NA_character_
  )
}

# A completed, fully transitive group a > b > c > d (a beats all, b beats c & d,
# c beats d). The third-placed team is `c`, whose goal difference is tuned by the
# margin of its win over `d`. Used to spread out third-place records across
# groups for the best-eight test.
transitive_group <- function(letter, ids, third_margin) {
  a <- ids[1]; b <- ids[2]; c <- ids[3]; d <- ids[4]
  list(
    m(letter, a, b, 1, 0), m(letter, a, c, 1, 0), m(letter, a, d, 1, 0),
    m(letter, b, c, 1, 0), m(letter, b, d, 1, 0),
    m(letter, c, d, third_margin, 0)
  )
}


test_that("group_standings ranks a completed group with the head-to-head rule", {
  # Teams 2 and 3 both finish on 6 points. Team 3 has the better overall goal
  # difference (+6 vs +5) but Team 2 won the head-to-head, so Team 2 ranks above
  # Team 3 wins: head-to-head precedes overall goal difference.
  rows <- list(
    m("A", 2, 3, 1, 0),  # T2 beats T3 (head-to-head)
    m("A", 2, 4, 5, 0),  # T2 big win
    m("A", 1, 2, 1, 0),  # T2 loses to T1
    m("A", 3, 1, 1, 0),  # T3 beats T1
    m("A", 3, 4, 6, 0),  # T3 big win
    m("A", 1, 4, 0, 1)   # T4 beats T1
  )
  st <- group_standings(build_matches(rows), build_teams(1:4))

  expect_equal(st$team_id, c(2L, 3L, 4L, 1L))          # final order
  expect_equal(st$rank, 1:4)
  expect_true(all(st$group_complete))
  # Team 3 really does have the better overall GD, confirming H2H won out.
  expect_gt(st$gd[st$team_id == 3], st$gd[st$team_id == 2])
  expect_false(any(st$tie_unresolved))
})

test_that("advancement_status reads final ranks for a completed group", {
  rows <- list(
    m("A", 2, 3, 1, 0), m("A", 2, 4, 5, 0), m("A", 1, 2, 1, 0),
    m("A", 3, 1, 1, 0), m("A", 3, 4, 6, 0), m("A", 1, 4, 0, 1)
  )
  adv <- advancement_status(build_matches(rows), build_teams(1:4))
  status <- stats::setNames(adv$top2_status, adv$team_id)

  expect_equal(unname(status["2"]), "won_group")
  expect_equal(unname(status["3"]), "clinched_top2")
  expect_equal(unname(status["4"]), "eliminated_top2")
  expect_equal(unname(status["1"]), "eliminated_top2")
  expect_true(all(adv$group_complete))
})

test_that("advancement_status clinches, eliminates and leaves teams alive mid-group", {
  # Group B, two rounds played, matchday 3 (5v8, 6v7) still to come.
  rows <- list(
    m("B", 5, 6, 3, 0), m("B", 7, 8, 1, 0),   # MD1
    m("B", 5, 7, 2, 0), m("B", 6, 8, 1, 0),   # MD2
    m("B", 5, 8, status = "TIMED"),           # MD3 (unplayed)
    m("B", 6, 7, status = "TIMED")
  )
  adv <- advancement_status(build_matches(rows), build_teams(5:8))
  status <- stats::setNames(adv$top2_status, adv$team_id)

  expect_equal(unname(status["5"]), "clinched_top2")   # 6 pts, can't drop below 2nd
  expect_equal(unname(status["8"]), "eliminated_top2") # 0 pts, can't reach top 2
  expect_equal(unname(status["6"]), "alive")
  expect_equal(unname(status["7"]), "alive")
  expect_false(any(adv$group_complete))
})

test_that("team_scenario spells out win/draw/loss on the final matchday", {
  rows <- list(
    m("B", 5, 6, 3, 0), m("B", 7, 8, 1, 0),
    m("B", 5, 7, 2, 0), m("B", 6, 8, 1, 0),
    m("B", 5, 8, status = "TIMED"),
    m("B", 6, 7, status = "TIMED")
  )
  # Team 6 plays Team 7 in its only remaining match.
  sc <- team_scenario("T06", build_matches(rows), build_teams(5:8))
  res <- stats::setNames(sc$result, sc$scenario)

  expect_equal(unname(res["Win"]), "clinched")
  expect_equal(unname(res["Draw"]), "depends")
  expect_equal(unname(res["Loss"]), "eliminated")
})

test_that("team_scenario reports a settled team as final", {
  rows <- list(
    m("A", 2, 3, 1, 0), m("A", 2, 4, 5, 0), m("A", 1, 2, 1, 0),
    m("A", 3, 1, 1, 0), m("A", 3, 4, 6, 0), m("A", 1, 4, 0, 1)
  )
  sc <- team_scenario("T01", build_matches(rows), build_teams(1:4))
  expect_equal(sc$scenario, "no matches left")
  expect_equal(sc$result, "final: eliminated")
})

test_that("third_place_table ranks thirds across groups and cuts at eight", {
  # Nine completed groups; each group's third-placed team has 3 points and a
  # goal difference set by its winning margin. Margins are deliberately not in
  # group order, so correct sorting must reorder them.
  letters9 <- LETTERS[1:9]
  margins  <- c(1, 9, 4, 7, 2, 8, 3, 6, 5)  # group A has the worst third (gd -1)
  rows <- list()
  ids_all <- integer()
  for (i in seq_along(letters9)) {
    ids <- (i * 10L) + 1:4
    ids_all <- c(ids_all, ids)
    rows <- c(rows, transitive_group(letters9[i], ids, margins[i]))
  }

  tp <- third_place_table(build_matches(rows), build_teams(ids_all))

  expect_equal(nrow(tp), 9L)
  # Best third place = group B (margin 9); worst = group A (margin 1).
  expect_equal(tp$group_letter[1], "B")
  expect_equal(tp$group_letter[9], "A")
  # Sorted by goal difference descending.
  expect_false(is.unsorted(rev(tp$gd)))
  # Eight advance; the ninth (group A) does not.
  expect_equal(sum(tp$currently_advancing), 8L)
  expect_false(tp$currently_advancing[tp$group_letter == "A"])
  # All groups complete -> final, not provisional.
  expect_false(any(tp$provisional))
  expect_false(any(tp$in_contention))
})

test_that("standings handle an unplayed group: zeros, unresolved ties, provisional", {
  rows <- list(
    m("C", 9, 10, status = "TIMED"),
    m("C", 11, 12, status = "TIMED"),
    m("C", 9, 11, status = "TIMED"),
    m("C", 10, 12, status = "TIMED"),
    m("C", 9, 12, status = "TIMED"),
    m("C", 10, 11, status = "TIMED")
  )
  st <- group_standings(build_matches(rows), build_teams(9:12))
  expect_equal(sum(st$points), 0L)
  expect_equal(sum(st$played), 0L)
  expect_true(all(st$tie_unresolved))   # nothing separates them yet
  expect_false(any(st$group_complete))

  tp <- third_place_table(build_matches(rows), build_teams(9:12))
  expect_true(all(tp$provisional))
})

test_that("chat_advancement_digest renders the tables and scenarios", {
  rows <- c(
    list(  # Group A complete (head-to-head)
      m("A", 2, 3, 1, 0), m("A", 2, 4, 5, 0), m("A", 1, 2, 1, 0),
      m("A", 3, 1, 1, 0), m("A", 3, 4, 6, 0), m("A", 1, 4, 0, 1)
    ),
    list(  # Group B mid-tournament
      m("B", 5, 6, 3, 0), m("B", 7, 8, 1, 0),
      m("B", 5, 7, 2, 0), m("B", 6, 8, 1, 0),
      m("B", 5, 8, status = "TIMED"), m("B", 6, 7, status = "TIMED")
    )
  )
  digest <- chat_advancement_digest(
    build_matches(rows), build_teams(1:8), today = as.Date("2026-06-21")
  )

  expect_type(digest, "character")
  expect_match(digest, "Group standings & advancement", fixed = TRUE)
  expect_match(digest, "### Group A (final)", fixed = TRUE)
  expect_match(digest, "### Group B (in progress)", fixed = TRUE)
  expect_match(digest, "Third-place race (provisional)", fixed = TRUE)
  expect_match(digest, "What still-alive teams need", fixed = TRUE)
})

test_that("chat_advancement_digest copes with no standings", {
  expect_match(
    chat_advancement_digest(empty_matches(), build_teams(1:4)),
    "No group-stage standings are available yet",
    fixed = TRUE
  )
})
