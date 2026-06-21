# Group standings and advancement logic for the 2026 World Cup.
#
# The chat app (querychat) is text-to-SQL and cannot be trusted to derive
# standings, tiebreakers, or the "top 2 + 8 best thirds" rule on the fly. These
# functions compute that in plain, tested R so the chat (and the Quarto site and
# the published data files) can present a pre-computed, correct answer.
#
# Scope (see project README / plan): exact for group standings and the top-2
# race within a group; the cross-group third-place race is shown as a live
# ranking flagged "provisional", not a guaranteed clinch/eliminate verdict.

#' Group-stage standings
#'
#' Computes the group tables from finished group-stage matches, applying the
#' FIFA 2026 in-group tiebreakers: points, then head-to-head (points, goal
#' difference, goals) among teams level on points, then overall goal difference
#' and goals scored. The deepest official tiebreakers (disciplinary/conduct
#' score and FIFA ranking) are **not** available from the API, so any teams that
#' remain level after goals are flagged with `tie_unresolved = TRUE` rather than
#' guessed.
#'
#' Mid-tournament tables are provisional: they reflect only the matches played
#' so far. A group is final once `group_complete` is `TRUE`.
#'
#' @param matches A matches tibble. Defaults to [all_matches()].
#' @param teams A teams tibble. Defaults to [list_teams()]; used to attach the
#'   three-letter code (`tla`).
#' @return A tibble, one row per team per group, ordered by group then rank.
#'   Columns: `group_letter`, `rank`, `team`, `team_id`, `tla`, `played`,
#'   `won`, `drawn`, `lost`, `gf`, `ga`, `gd`, `points`, `tie_unresolved`,
#'   `group_complete`.
#' @export
#' @examples
#' \dontrun{
#' group_standings()
#' }
group_standings <- function(matches = all_matches(), teams = list_teams()) {
  grp <- dplyr::filter(matches, .data$stage == "GROUP_STAGE", !is.na(.data$group))
  if (nrow(grp) == 0L) return(empty_standings())

  counted <- group_counted_matches(grp)
  team_group <- group_team_map(grp)

  letters_present <- sort(unique(team_group$group))
  out <- purrr::map(letters_present, function(g) {
    ids   <- team_group$team_id[team_group$group == g]
    fin_g <- counted[counted$group == g, , drop = FALSE]

    tbl <- rank_within_group(tally_table(ids, fin_g), fin_g)

    # A group is final once every one of its matches counts toward the table.
    tbl$group_letter   <- sub("^GROUP_", "", g)
    tbl$group_complete <- sum(grp$group == g) == nrow(fin_g)
    tbl
  })
  out <- dplyr::bind_rows(out)

  # Attach names and three-letter codes for display.
  names_lookup <- stats::setNames(team_group$team, as.character(team_group$team_id))
  tla_lookup   <- stats::setNames(teams$tla, as.character(teams$id))
  out$team <- unname(names_lookup[as.character(out$team_id)])
  out$tla  <- unname(tla_lookup[as.character(out$team_id)])

  out |>
    dplyr::arrange(.data$group_letter, .data$rank) |>
    dplyr::select(
      "group_letter", "rank", "team", "team_id", "tla",
      "played", "won", "drawn", "lost", "gf", "ga", "gd", "points",
      "tie_unresolved", "group_complete"
    )
}

#' Per-team advancement status for the top-two race
#'
#' Classifies every group-stage team as `"won_group"`, `"clinched_top2"`,
#' `"eliminated_top2"`, or `"alive"` for the race to finish in the top two of
#' its group (which guarantees a Round-of-32 place). The verdict is computed by
#' enumerating every win/draw/loss combination of the group's remaining matches.
#'
#' To stay sound it never over-claims: a "clinched"/"won" verdict assumes the
#' team **loses** every points tiebreak, and an "eliminated" verdict assumes it
#' **wins** every tiebreak. Teams that are in fact decided only on goal
#' difference therefore show as `"alive"` until the maths is unambiguous. The
#' third-place ("best 8") route is handled separately by [third_place_table()].
#'
#' @inheritParams group_standings
#' @return A tibble: `group_letter`, `team`, `team_id`, `top2_status`,
#'   `group_complete`.
#' @seealso [group_standings()], [third_place_table()], [team_scenario()]
#' @export
#' @examples
#' \dontrun{
#' advancement_status()
#' }
advancement_status <- function(matches = all_matches(), teams = list_teams()) {
  grp <- dplyr::filter(matches, .data$stage == "GROUP_STAGE", !is.na(.data$group))
  if (nrow(grp) == 0L) return(empty_advancement())

  counted    <- group_counted_matches(grp)
  remaining  <- group_remaining_matches(grp)
  team_group <- group_team_map(grp)
  standings  <- group_standings(matches, teams)

  letters_present <- sort(unique(team_group$group))
  out <- purrr::map(letters_present, function(g) {
    ids        <- team_group$team_id[team_group$group == g]
    fin_g      <- counted[counted$group == g, , drop = FALSE]
    remaining_g <- remaining[remaining$group == g, , drop = FALSE]
    base_points <- group_base_points(ids, fin_g)
    complete    <- nrow(remaining_g) == 0L

    status <- vapply(ids, function(id) {
      if (complete) {
        rank <- standings$rank[standings$team_id == id]
        if (length(rank) == 0L) return(NA_character_)
        if (rank == 1L) "won_group" else if (rank == 2L) "clinched_top2" else "eliminated_top2"
      } else {
        cls <- classify_top2(id, ids, base_points, remaining_g)
        if (cls$won) "won_group"
        else if (cls$clinched) "clinched_top2"
        else if (!cls$reachable) "eliminated_top2"
        else "alive"
      }
    }, character(1))

    tibble::tibble(
      group_letter   = sub("^GROUP_", "", g),
      team_id        = ids,
      top2_status    = status,
      group_complete = complete
    )
  })

  out <- dplyr::bind_rows(out)
  names_lookup <- stats::setNames(team_group$team, as.character(team_group$team_id))
  out$team <- unname(names_lookup[as.character(out$team_id)])
  dplyr::select(out, "group_letter", "team", "team_id", "top2_status", "group_complete")
}

#' What a team needs to reach the top two of its group
#'
#' Breaks down a single team's remaining group match(es) into outcomes and says,
#' for each, whether that outcome clinches a top-two finish, eliminates the team
#' from it, or leaves it dependent on other results. Outcomes are from the team's
#' own perspective (Win / Draw / Loss); when more than one match remains they are
#' combined (e.g. `"Win, Draw"`). The same sound, never-over-claiming logic as
#' [advancement_status()] is used.
#'
#' @param team A team name, short name, three-letter code, or alias.
#' @inheritParams group_standings
#' @return A tibble: `team`, `group_letter`, `scenario` (the outcome label),
#'   `result` (one of `"clinched"`, `"eliminated"`, `"depends"`, or, when no
#'   matches remain, `"final: <status>"`). One row per outcome combination.
#' @seealso [advancement_status()]
#' @export
#' @examples
#' \dontrun{
#' team_scenario("USA")
#' }
team_scenario <- function(team, matches = all_matches(), teams = list_teams()) {
  resolved <- resolve_team(team, teams)
  id <- resolved$id
  team_name <- resolved$name

  grp <- dplyr::filter(matches, .data$stage == "GROUP_STAGE", !is.na(.data$group))
  team_group <- group_team_map(grp)
  g <- team_group$group[team_group$team_id == id]
  if (length(g) == 0L) {
    cli::cli_abort("{.val {team}} is not in the group stage of this tournament.")
  }
  g <- g[1]
  group_letter <- sub("^GROUP_", "", g)

  ids         <- team_group$team_id[team_group$group == g]
  counted     <- group_counted_matches(grp)
  remaining   <- group_remaining_matches(grp)
  fin_g       <- counted[counted$group == g, , drop = FALSE]
  remaining_g <- remaining[remaining$group == g, , drop = FALSE]
  base_points <- group_base_points(ids, fin_g)

  own   <- remaining_g[remaining_g$home_team_id == id | remaining_g$away_team_id == id, , drop = FALSE]
  other <- remaining_g[remaining_g$home_team_id != id & remaining_g$away_team_id != id, , drop = FALSE]

  if (nrow(own) == 0L) {
    # Nothing left to play: report the settled (or provisional) status.
    cls <- classify_top2(id, ids, base_points, remaining_g)
    result <- if (cls$won || cls$clinched) "clinched"
              else if (!cls$reachable) "eliminated"
              else "depends"
    label <- if (nrow(remaining_g) == 0L) paste0("final: ", result) else result
    return(tibble::tibble(
      team = team_name, group_letter = group_letter,
      scenario = "no matches left", result = label
    ))
  }

  # Enumerate this team's own remaining results; classify each against the
  # other group matches still to play.
  own_combos <- outcome_grid(nrow(own))
  rows <- purrr::map(seq_len(nrow(own_combos)), function(i) {
    oc <- as.character(unlist(own_combos[i, ]))
    pts <- apply_outcomes(base_points, own, oc)
    cls <- classify_top2(id, ids, pts, other)
    result <- if (cls$won || cls$clinched) "clinched"
              else if (!cls$reachable) "eliminated"
              else "depends"
    tibble::tibble(
      team = team_name, group_letter = group_letter,
      scenario = own_scenario_label(own, id, oc), result = result
    )
  })
  dplyr::bind_rows(rows)
}

#' Cross-group ranking of the third-placed teams
#'
#' Ranks the current third-placed team from each group to show the race for the
#' eight "best third-placed" Round-of-32 places. Ranking criteria (FIFA 2026,
#' no head-to-head since these teams come from different groups): points, goal
#' difference, goals scored. While the group stage is in progress the table is
#' **provisional**: both which team is third and its record can still change,
#' so `currently_advancing` is a snapshot, not a guarantee, and borderline rows
#' are flagged `in_contention`. It becomes final once every group is complete.
#'
#' @inheritParams group_standings
#' @return A tibble, one row per group (12 when the full schedule is loaded):
#'   `position`, `group_letter`, `team`, `team_id`, `played`, `points`, `gd`,
#'   `gf`, `currently_advancing`, `in_contention`, `provisional`.
#' @seealso [group_standings()], [advancement_status()]
#' @export
#' @examples
#' \dontrun{
#' third_place_table()
#' }
third_place_table <- function(matches = all_matches(), teams = list_teams()) {
  st <- group_standings(matches, teams)
  if (nrow(st) == 0L) return(empty_third_place())

  thirds <- dplyr::filter(st, .data$rank == 3L)
  thirds <- thirds[order(-thirds$points, -thirds$gd, -thirds$gf), , drop = FALSE]
  thirds$position <- seq_len(nrow(thirds))
  thirds$currently_advancing <- thirds$position <= 8L

  complete <- all(st$group_complete)
  thirds$provisional   <- !complete
  # Honest "borderline" flag: while provisional, rows near the 8th/9th cut could
  # plausibly move across it. We deliberately do not compute an exact bound.
  thirds$in_contention <- !complete & thirds$position >= 5L & thirds$position <= 11L

  dplyr::select(
    thirds,
    "position", "group_letter", "team", "team_id",
    "played", "points", "gd", "gf",
    "currently_advancing", "in_contention", "provisional"
  )
}


# ---- internal helpers -------------------------------------------------------

#' Group-stage matches that count toward the table: finished, with a real score.
#' @noRd
group_counted_matches <- function(grp) {
  grp[
    grp$status %in% final_statuses() &
      !is.na(grp$home_score) & !is.na(grp$away_score),
    ,
    drop = FALSE
  ]
}

#' Group-stage matches still to be decided (everything not yet counted).
#' @noRd
group_remaining_matches <- function(grp) {
  counted_ids <- group_counted_matches(grp)$match_id
  grp[!grp$match_id %in% counted_ids, , drop = FALSE]
}

#' Map each group-stage team to its group letter (the `GROUP_x` code).
#' @noRd
group_team_map <- function(grp) {
  dplyr::distinct(dplyr::bind_rows(
    tibble::tibble(team_id = grp$home_team_id, team = grp$home_team, group = grp$group),
    tibble::tibble(team_id = grp$away_team_id, team = grp$away_team, group = grp$group)
  ))
}

#' Current points for a set of teams from a set of (finished) matches, as a
#' numeric vector named by team id (every id present, 0 when none played).
#' @noRd
group_base_points <- function(ids, fin) {
  tbl <- tally_table(ids, fin)
  stats::setNames(as.numeric(tbl$points), as.character(tbl$team_id))
}

#' Build a mini standings table (points/GD/goals/record) for `team_ids` from
#' `matches`. Every id appears even with no matches. No penalties in the group
#' stage, so full-time goals decide everything.
#' @noRd
tally_table <- function(team_ids, matches) {
  rows <- dplyr::bind_rows(
    tibble::tibble(
      team_id = matches$home_team_id,
      gf = matches$home_score, ga = matches$away_score
    ),
    tibble::tibble(
      team_id = matches$away_team_id,
      gf = matches$away_score, ga = matches$home_score
    )
  )

  agg <- rows |>
    dplyr::mutate(
      won = .data$gf > .data$ga,
      drawn = .data$gf == .data$ga,
      lost = .data$gf < .data$ga,
      pts = dplyr::case_when(
        .data$gf > .data$ga ~ 3L,
        .data$gf == .data$ga ~ 1L,
        TRUE ~ 0L
      )
    ) |>
    dplyr::group_by(.data$team_id) |>
    dplyr::summarise(
      played = dplyr::n(),
      won = sum(.data$won),
      drawn = sum(.data$drawn),
      lost = sum(.data$lost),
      gf = sum(.data$gf),
      ga = sum(.data$ga),
      points = sum(.data$pts),
      .groups = "drop"
    )

  tibble::tibble(team_id = team_ids) |>
    dplyr::left_join(agg, by = "team_id") |>
    dplyr::mutate(dplyr::across(
      c("played", "won", "drawn", "lost", "gf", "ga", "points"),
      \(x) dplyr::coalesce(x, 0L)
    )) |>
    dplyr::mutate(gd = .data$gf - .data$ga)
}

#' Order a group's teams by the FIFA in-group tiebreakers and assign ranks.
#' Adds head-to-head columns used only for ordering, plus `tie_unresolved` for
#' teams that cannot be separated without the (unavailable) conduct / FIFA
#' ranking criteria.
#' @noRd
rank_within_group <- function(tbl, fin) {
  tbl$h2h_points <- 0L
  tbl$h2h_gd <- 0L
  tbl$h2h_gf <- 0L

  for (p in unique(tbl$points)) {
    idx <- which(tbl$points == p)
    if (length(idx) > 1L && nrow(fin) > 0L) {
      ids <- tbl$team_id[idx]
      sub <- fin[fin$home_team_id %in% ids & fin$away_team_id %in% ids, , drop = FALSE]
      if (nrow(sub) > 0L) {
        h2h <- tally_table(ids, sub)
        m <- match(tbl$team_id[idx], h2h$team_id)
        tbl$h2h_points[idx] <- h2h$points[m]
        tbl$h2h_gd[idx] <- h2h$gd[m]
        tbl$h2h_gf[idx] <- h2h$gf[m]
      }
    }
  }

  ord <- order(
    -tbl$points, -tbl$h2h_points, -tbl$h2h_gd, -tbl$h2h_gf, -tbl$gd, -tbl$gf
  )
  tbl <- tbl[ord, , drop = FALSE]
  tbl$rank <- seq_len(nrow(tbl))

  # Adjacent teams identical on every available key are genuinely unresolved.
  keys <- c("points", "h2h_points", "h2h_gd", "h2h_gf", "gd", "gf")
  tbl$tie_unresolved <- FALSE
  if (nrow(tbl) > 1L) {
    for (i in seq_len(nrow(tbl) - 1L)) {
      same <- all(vapply(keys, \(k) tbl[[k]][i] == tbl[[k]][i + 1L], logical(1)))
      if (same) {
        tbl$tie_unresolved[i] <- TRUE
        tbl$tie_unresolved[i + 1L] <- TRUE
      }
    }
  }

  tbl[, c(
    "team_id", "played", "won", "drawn", "lost",
    "gf", "ga", "gd", "points", "rank", "tie_unresolved"
  )]
}

#' All win/draw/loss combinations for `n` matches as a data frame of "H"/"D"/"A"
#' rows (home win / draw / away win). One empty row when `n == 0`.
#' @noRd
outcome_grid <- function(n) {
  if (n == 0L) return(tibble::tibble(.rows = 1L))
  expand.grid(rep(list(c("H", "D", "A")), n), stringsAsFactors = FALSE)
}

#' Apply a vector of "H"/"D"/"A" outcomes for `matches` onto a named points
#' vector, returning the updated vector.
#' @noRd
apply_outcomes <- function(points, matches, outcomes) {
  if (length(outcomes) == 0L) return(points)
  home <- as.character(matches$home_team_id)
  away <- as.character(matches$away_team_id)
  for (j in seq_along(outcomes)) {
    if (outcomes[j] == "H") {
      points[home[j]] <- points[home[j]] + 3
    } else if (outcomes[j] == "A") {
      points[away[j]] <- points[away[j]] + 3
    } else {
      points[home[j]] <- points[home[j]] + 1
      points[away[j]] <- points[away[j]] + 1
    }
  }
  points
}

#' Decide a team's top-two prospects by enumerating `free_matches` outcomes.
#'
#' Returns three flags computed over every win/draw/loss combination:
#' - `won`: in every combination the team has strictly more points than all
#'   others (guaranteed first; sound, ignores goal-difference paths).
#' - `clinched`: in every combination at most one other team reaches its points
#'   (guaranteed top two even losing all tiebreaks).
#' - `reachable`: in at least one combination at most one other team is strictly
#'   above it (top two is still possible, giving it every tiebreak).
#' @noRd
classify_top2 <- function(focus_id, team_ids, base_points, free_matches) {
  n <- nrow(free_matches)
  combos <- outcome_grid(n)
  focus <- as.character(focus_id)
  other_ids <- setdiff(as.character(team_ids), focus)

  won_all <- TRUE
  clinched_all <- TRUE
  reachable_any <- FALSE

  for (i in seq_len(nrow(combos))) {
    oc <- if (n == 0L) character(0) else as.character(unlist(combos[i, ]))
    pts <- apply_outcomes(base_points, free_matches, oc)
    px <- pts[focus]
    others <- pts[other_ids]
    g_cnt <- sum(others > px)        # teams strictly above
    t_cnt <- sum(others == px)       # teams level on points

    won_all <- won_all && (g_cnt == 0 && t_cnt == 0)
    clinched_all <- clinched_all && ((g_cnt + t_cnt) <= 1)
    reachable_any <- reachable_any || (g_cnt <= 1)
  }

  list(won = won_all, clinched = clinched_all, reachable = reachable_any)
}

#' Human label for a team's own outcome combination, e.g. "Win", "Draw, Loss".
#' @noRd
own_scenario_label <- function(own, focus_id, outcomes) {
  labels <- vapply(seq_len(nrow(own)), function(j) {
    is_home <- own$home_team_id[j] == focus_id
    oc <- outcomes[j]
    if (oc == "D") "Draw" else if ((oc == "H") == is_home) "Win" else "Loss"
  }, character(1))
  paste(labels, collapse = ", ")
}

#' @noRd
empty_standings <- function() {
  tibble::tibble(
    group_letter = character(), rank = integer(),
    team = character(), team_id = integer(), tla = character(),
    played = integer(), won = integer(), drawn = integer(), lost = integer(),
    gf = integer(), ga = integer(), gd = integer(), points = integer(),
    tie_unresolved = logical(), group_complete = logical()
  )
}

#' @noRd
empty_advancement <- function() {
  tibble::tibble(
    group_letter = character(), team = character(), team_id = integer(),
    top2_status = character(), group_complete = logical()
  )
}

#' @noRd
empty_third_place <- function() {
  tibble::tibble(
    position = integer(), group_letter = character(),
    team = character(), team_id = integer(),
    played = integer(), points = integer(), gd = integer(), gf = integer(),
    currently_advancing = logical(), in_contention = logical(),
    provisional = logical()
  )
}
