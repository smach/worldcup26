#' Statuses where the match is in flight.
#' @noRd
live_statuses <- function() {
  c("IN_PLAY", "PAUSED", "EXTRA_TIME", "PENALTY_SHOOTOUT")
}

#' Statuses where the match has concluded.
#' @noRd
final_statuses <- function() c("FINISHED", "AWARDED")

#' Statuses where the match is not currently part of the active schedule.
#' @noRd
inactive_statuses <- function() c("CANCELLED", "POSTPONED", "SUSPENDED")

#' Build the human-readable score column.
#'
#' Vectorised. Inputs are aligned vectors of equal length.
#' @param status One of the API status values.
#' @param home,away Full-time goals (integer; NA if not yet available).
#' @param pk_home,pk_away Penalty shoot-out goals (integer; NA if N/A).
#' @param utc_date Match start time (POSIXct).
#' @param now The reference "now" for past/future judgement.
#' @param live Whether to show running scorelines for in-play matches
#'   (e.g. `"1\u20130 (live)"`). Defaults to [live_mode()]; on the free tier
#'   the running score isn't available, so in-play matches read
#'   `"in progress"` instead.
#' @noRd
score_display <- function(status, home, away, pk_home, pk_away,
                          utc_date, now = Sys.time(), live = live_mode()) {
  dash <- "\u2013"
  n <- length(status)
  out <- character(n)
  has_score <- !is.na(home) & !is.na(away)
  has_pk    <- !is.na(pk_home) & !is.na(pk_away)
  in_past   <- !is.na(utc_date) & utc_date < now

  for (i in seq_len(n)) {
    s <- status[i]
    if (is.na(s)) {
      out[i] <- ""
      next
    }
    if (s %in% live_statuses()) {
      # In live mode the paid tier carries a running score; show it once
      # the match has a scoreline, otherwise fall back to "in progress".
      if (live && has_score[i]) {
        out[i] <- sprintf("%d%s%d (live)", home[i], dash, away[i])
      } else {
        out[i] <- "in progress"
      }
    } else if (s %in% final_statuses()) {
      if (has_score[i]) {
        out[i] <- sprintf("%d%s%d", home[i], dash, away[i])
        if (has_pk[i]) {
          out[i] <- sprintf("%s (%d%s%d PK)", out[i], pk_home[i], dash, pk_away[i])
        }
      } else {
        out[i] <- "no score available yet"
      }
    } else if (s %in% inactive_statuses()) {
      out[i] <- tolower(s)
    } else if (s %in% c("SCHEDULED", "TIMED")) {
      out[i] <- if (in_past[i]) "no score available yet" else ""
    } else {
      out[i] <- ""
    }
  }
  out
}
