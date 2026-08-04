`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x
}

null_if_blank <- function(x) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) return(NULL)
  value <- stringr::str_squish(as.character(x[[1]]))
  if (!nzchar(value)) NULL else value
}

date_or_null <- function(x) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) return(NULL)
  format(as.Date(x[[1]]), "%Y-%m-%d")
}

normalize_opportunities <- function(data) {
  required_columns <- c(
    "id", "opportunity_name", "description", "qualification",
    "opportunity_type", "academic_term", "student_level",
    "start_date", "end_date", "application_deadline", "expiration_date",
    "compensation_type", "compensation_details", "work_setting",
    "location", "department_center", "time_commitment", "contact_name",
    "contact_email", "application_url", "status", "created_at", "updated_at"
  )

  if (is.null(data) || nrow(data) == 0) {
    data <- tibble::tibble()
  }

  for (column in setdiff(required_columns, names(data))) {
    data[[column]] <- rep(NA_character_, nrow(data))
  }

  data |>
    dplyr::select(dplyr::all_of(required_columns)) |>
    dplyr::mutate(
      dplyr::across(
        c(
          id, opportunity_name, description, qualification,
          opportunity_type, academic_term, student_level,
          compensation_type, compensation_details, work_setting,
          location, department_center, time_commitment, contact_name,
          contact_email, application_url, status
        ),
        as.character
      ),
      dplyr::across(
        c(start_date, end_date, application_deadline, expiration_date),
        ~ suppressWarnings(as.Date(.x))
      ),
      created_at = suppressWarnings(lubridate::ymd_hms(created_at, quiet = TRUE)),
      updated_at = suppressWarnings(lubridate::ymd_hms(updated_at, quiet = TRUE))
    )
}

fetch_opportunities <- function(supabase_url, publishable_key, configured) {
  if (!configured) {
    return(readr::read_csv("data/sample_opportunities.csv", show_col_types = FALSE))
  }

  endpoint <- paste0(sub("/+$", "", supabase_url), "/rest/v1/opportunities")

  response <- httr2::request(endpoint) |>
    httr2::req_url_query(
      select = "*",
      order = "application_deadline.asc.nullslast,created_at.desc"
    ) |>
    httr2::req_headers(apikey = publishable_key) |>
    httr2::req_timeout(20) |>
    httr2::req_perform()

  body <- httr2::resp_body_json(response, simplifyVector = TRUE)

  if (is.null(body) || length(body) == 0) {
    return(tibble::tibble())
  }

  tibble::as_tibble(body)
}

submit_opportunity <- function(supabase_url, publishable_key, record) {
  endpoint <- paste0(sub("/+$", "", supabase_url), "/rest/v1/opportunities")

  response <- httr2::request(endpoint) |>
    httr2::req_method("POST") |>
    httr2::req_headers(
      apikey = publishable_key,
      Prefer = "return=minimal"
    ) |>
    httr2::req_body_json(record, auto_unbox = TRUE, null = "null") |>
    httr2::req_timeout(20) |>
    httr2::req_perform()

  invisible(response)
}
