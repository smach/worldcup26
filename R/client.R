#' The football-data.org v4 base URL.
#' @noRd
fd_base_url <- function() {
  getOption("worldcup26.base_url", "https://api.football-data.org/v4")
}

#' Competition code for the FIFA Men's World Cup.
#' @noRd
wc_code <- function() "WC"

#' Retrieve the football-data.org API key.
#'
#' Reads `FOOTBALL_DATA_API_KEY` from the environment. Errors if missing.
#' @noRd
fd_api_key <- function() {
  key <- Sys.getenv("FOOTBALL_DATA_API_KEY", unset = "")
  if (!nzchar(key)) {
    cli::cli_abort(c(
      "No football-data.org API key found.",
      i = "Set {.envvar FOOTBALL_DATA_API_KEY} in your {.file .Renviron}.",
      i = "Free key: {.url https://www.football-data.org/client/register}"
    ))
  }
  key
}

#' Perform a GET against the football-data.org API.
#'
#' Internal HTTP client used by all higher-level functions. Returns the
#' parsed JSON body as a list. Adds the `X-Auth-Token` header, retries on
#' transient errors and rate limits, and surfaces useful errors.
#'
#' @param path API path, e.g. `"competitions/WC/teams"`.
#' @param query Named list of query parameters; `NULL` values are dropped.
#' @return Parsed JSON as a nested list.
#' @noRd
fwc_get <- function(path, query = list()) {
  req <- httr2::request(fd_base_url()) |>
    httr2::req_url_path_append(path) |>
    httr2::req_url_query(!!!purrr::compact(query)) |>
    httr2::req_headers(`X-Auth-Token` = fd_api_key()) |>
    httr2::req_user_agent("worldcup26 R package (https://github.com/smach/worldcup26)") |>
    httr2::req_retry(
      max_tries = 3,
      is_transient = \(resp) httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504)
    ) |>
    httr2::req_error(body = fd_error_body)

  resp <- httr2::req_perform(req)
  httr2::resp_body_json(resp)
}

#' Pull a useful error message out of an API failure response.
#' @noRd
fd_error_body <- function(resp) {
  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
  if (is.list(body) && !is.null(body$message)) {
    return(body$message)
  }
  NULL
}
