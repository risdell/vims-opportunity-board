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
  value <- suppressWarnings(as.Date(x[[1]]))
  if (is.na(value)) NULL else format(value, "%Y-%m-%d")
}

DB_PATH <- Sys.getenv(
  "OPPORTUNITY_DB",
  "/var/lib/vims-opportunity-board/opportunities.sqlite"
)

generate_id <- function() {
  paste0(
    format(Sys.time(), "%Y%m%d%H%M%OS6"), "-",
    Sys.getpid(), "-",
    sprintf("%09d", sample.int(999999999, 1))
  )
}

db_connect <- function() {
  con <- DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  DBI::dbExecute(con, "PRAGMA journal_mode = WAL")
  DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")
  DBI::dbExecute(con, "PRAGMA synchronous = NORMAL")
  con
}

initialize_database <- function() {
  db_dir <- dirname(DB_PATH)
  if (!dir.exists(db_dir)) {
    stop("Database directory does not exist: ", db_dir)
  }

  con <- db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS opportunities (
      id TEXT PRIMARY KEY,
      opportunity_name TEXT NOT NULL,
      description TEXT NOT NULL,
      qualification TEXT,
      opportunity_type TEXT NOT NULL DEFAULT 'Research'
        CHECK (opportunity_type IN (
          'Research', 'Internship', 'Paid employment',
          'Independent study', 'Capstone', 'Volunteer'
        )),
      academic_term TEXT,
      student_level TEXT,
      start_date TEXT,
      end_date TEXT,
      application_deadline TEXT,
      expiration_date TEXT,
      compensation_type TEXT NOT NULL DEFAULT 'Unpaid/volunteer'
        CHECK (compensation_type IN (
          'Paid', 'Stipend', 'Academic credit',
          'Unpaid/volunteer', 'Varies'
        )),
      compensation_details TEXT,
      work_setting TEXT,
      location TEXT,
      department_center TEXT NOT NULL,
      time_commitment TEXT,
      contact_name TEXT NOT NULL,
      contact_email TEXT NOT NULL,
      application_url TEXT,
      owner_id TEXT,
      owner_email TEXT,
      notification_sent_at TEXT,
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'closed', 'rejected')),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK (
        end_date IS NULL OR start_date IS NULL OR end_date >= start_date
      )
    )
  ")

  # Migration-safe additions for future SSO ownership. Existing public
  # submissions remain valid with NULL owner fields.
  existing_columns <- DBI::dbGetQuery(con, "PRAGMA table_info(opportunities)")$name

  if (!"owner_id" %in% existing_columns) {
    DBI::dbExecute(con, "ALTER TABLE opportunities ADD COLUMN owner_id TEXT")
  }

  if (!"owner_email" %in% existing_columns) {
    DBI::dbExecute(con, "ALTER TABLE opportunities ADD COLUMN owner_email TEXT")
  }

  # Existing rows should not generate a backlog of alerts on upgrade.
  if (!"notification_sent_at" %in% existing_columns) {
    DBI::dbExecute(con, "ALTER TABLE opportunities ADD COLUMN notification_sent_at TEXT")
    DBI::dbExecute(con, "UPDATE opportunities SET notification_sent_at = created_at WHERE notification_sent_at IS NULL")
  }

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS change_requests (
      id TEXT PRIMARY KEY,
      opportunity_id TEXT,
      opportunity_title TEXT NOT NULL,
      requester_email TEXT NOT NULL,
      request_type TEXT NOT NULL CHECK (request_type IN ('edit', 'remove')),
      details TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved','dismissed')),
      created_at TEXT NOT NULL,
      resolved_at TEXT,
      notification_sent_at TEXT,
      FOREIGN KEY (opportunity_id) REFERENCES opportunities(id) ON DELETE SET NULL
    )
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_requests_status ON change_requests(status)")

  DBI::dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_opportunities_status
    ON opportunities(status)
  ")

  DBI::dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_opportunities_expiration
    ON opportunities(expiration_date)
  ")

  DBI::dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_opportunities_owner
    ON opportunities(owner_id)
  ")

  invisible(DB_PATH)
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

  if (is.null(data) || nrow(data) == 0) data <- tibble::tibble()

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

fetch_opportunities <- function() {
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbGetQuery(con, "
    SELECT *
    FROM opportunities
    WHERE status = 'approved'
      AND start_date IS NOT NULL AND date(start_date) IS NOT NULL
      AND date(end_date) >= :today
      AND date(application_deadline) >= :today
      AND date(expiration_date) >= :today
    ORDER BY
      CASE WHEN application_deadline IS NULL OR application_deadline = '' THEN 1 ELSE 0 END,
      application_deadline ASC,
      created_at DESC
  ", params = list(today = as.character(Sys.Date())))
}

submit_opportunity <- function(record, owner_id = NULL, owner_email = NULL, status = "pending") {
  allowed_status <- c("pending", "approved", "closed", "rejected")
  if (!status %in% allowed_status) {
    stop("Invalid opportunity status: ", status)
  }

  required_dates <- c("start_date", "end_date", "application_deadline", "expiration_date")
  dates <- lapply(required_dates, function(name) suppressWarnings(as.Date(record[[name]])))
  if (any(vapply(dates, function(x) length(x) != 1 || is.na(x), logical(1)))) {
    stop("All four dates are required.")
  }
  names(dates) <- required_dates
  if (dates$end_date < dates$start_date) stop("End date cannot precede start date.")
  if (!is.null(record$application_url) && length(record$application_url) &&
      !is.na(record$application_url[[1]]) && nzchar(record$application_url[[1]]) &&
      !grepl("^https?://", record$application_url[[1]], ignore.case = TRUE)) {
    stop("Application URL must begin with https:// or http://")
  }
  if (any(vapply(dates[c("end_date", "application_deadline", "expiration_date")],
                 function(x) x < Sys.Date(), logical(1)))) {
    stop("Deadline, end date, and board expiration must be today or later.")
  }

  con <- db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  value <- function(name) {
    x <- record[[name]]
    if (is.null(x) || length(x) == 0 || is.na(x[[1]]) || !nzchar(as.character(x[[1]]))) {
      NA_character_
    } else {
      as.character(x[[1]])
    }
  }

  params <- list(
    id = generate_id(),
    opportunity_name = value("opportunity_name"),
    description = value("description"),
    qualification = value("qualification"),
    opportunity_type = value("opportunity_type"),
    academic_term = value("academic_term"),
    student_level = value("student_level"),
    start_date = value("start_date"),
    end_date = value("end_date"),
    application_deadline = value("application_deadline"),
    expiration_date = value("expiration_date"),
    compensation_type = value("compensation_type"),
    compensation_details = value("compensation_details"),
    work_setting = value("work_setting"),
    location = value("location"),
    department_center = value("department_center"),
    time_commitment = value("time_commitment"),
    contact_name = value("contact_name"),
    contact_email = value("contact_email"),
    application_url = value("application_url"),
    owner_id = if (is.null(owner_id) || !nzchar(owner_id)) NA_character_ else as.character(owner_id),
    owner_email = if (is.null(owner_email) || !nzchar(owner_email)) NA_character_ else tolower(as.character(owner_email)),
    status = status,
    created_at = now,
    updated_at = now
  )

  DBI::dbExecute(
    con,
    "
      INSERT INTO opportunities (
        id, opportunity_name, description, qualification,
        opportunity_type, academic_term, student_level,
        start_date, end_date, application_deadline, expiration_date,
        compensation_type, compensation_details, work_setting,
        location, department_center, time_commitment,
        contact_name, contact_email, application_url,
        owner_id, owner_email, status, created_at, updated_at
      ) VALUES (
        :id, :opportunity_name, :description, :qualification,
        :opportunity_type, :academic_term, :student_level,
        :start_date, :end_date, :application_deadline, :expiration_date,
        :compensation_type, :compensation_details, :work_setting,
        :location, :department_center, :time_commitment,
        :contact_name, :contact_email, :application_url,
        :owner_id, :owner_email, :status, :created_at, :updated_at
      )
    ",
    params = params
  )

  invisible(params$id)
}


# Future SSO management helper. Once the reverse proxy supplies a stable
# authenticated user identifier, the management app can use this function
# to show only records owned by that user.
fetch_owned_opportunities <- function(owner_id) {
  if (is.null(owner_id) || !nzchar(owner_id)) {
    stop("owner_id must be a non-empty authenticated user identifier")
  }

  con <- db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbGetQuery(
    con,
    "
      SELECT *
      FROM opportunities
      WHERE owner_id = :owner_id
      ORDER BY updated_at DESC
    ",
    params = list(owner_id = owner_id)
  )
}

# Public change requests are never applied automatically. The claimed email
# address is not verified; the administrator confirms before editing a record.
create_change_request <- function(opportunity_id = NULL, opportunity_title,
                                  requester_email, request_type, details) {
  stopifnot(request_type %in% c("edit", "remove"))
  if (is.null(opportunity_title) || nchar(trimws(opportunity_title)) < 3) stop("Opportunity title is required")
  if (!grepl("^[a-z0-9._%+\\-]+@vims\\.edu$", tolower(requester_email))) stop("A VIMS email address is required")
  if (nchar(trimws(details)) < 10) stop("More detail is required")
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con,
    "INSERT INTO change_requests
      (id, opportunity_id, opportunity_title, requester_email, request_type, details, status, created_at)
     VALUES (:id, :opportunity_id, :opportunity_title, :requester_email, :request_type, :details, 'open', :created_at)",
    params = list(
      id = generate_id(),
      opportunity_id = if (is.null(opportunity_id) || !nzchar(opportunity_id)) NA_character_ else opportunity_id,
      opportunity_title = trimws(opportunity_title),
      requester_email = tolower(trimws(requester_email)),
      request_type = request_type,
      details = trimws(details),
      created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    )
  )
  invisible(TRUE)
}

fetch_admin_opportunities <- function() {
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbGetQuery(con, "SELECT * FROM opportunities
    ORDER BY CASE WHEN status = 'pending' THEN 0 ELSE 1 END, created_at DESC")
}

fetch_change_requests <- function() {
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbGetQuery(con, "SELECT * FROM change_requests
    ORDER BY CASE WHEN status = 'open' THEN 0 ELSE 1 END, created_at DESC")
}

# Admin-only helper, called exclusively from a separately protected app.
# All SQL values are parameters; do not use user input as SQL syntax.
update_admin_opportunity <- function(id, record, status) {
  if (!status %in% c("pending", "approved", "closed", "rejected")) stop("Invalid status")
  date_cols <- c("start_date", "end_date", "application_deadline", "expiration_date")
  date_values <- lapply(date_cols, function(name) suppressWarnings(as.Date(record[[name]])))
  names(date_values) <- date_cols
  if (identical(status, "approved")) {
    if (any(vapply(date_values, function(x) length(x) != 1 || is.na(x), logical(1)))) {
      stop("To approve, supply all four dates.")
    }
    if (date_values$end_date < date_values$start_date) stop("End date precedes start date")
    if (any(vapply(date_values[c("end_date","application_deadline","expiration_date")],
                   function(x) x < Sys.Date(), logical(1)))) {
      stop("End date, application deadline, and expiration must not have passed")
    }
  }
  if (!nzchar(trimws(record$opportunity_name)) || !nzchar(trimws(record$description)) ||
      !nzchar(trimws(record$contact_name)) || !nzchar(trimws(record$contact_email))) {
    stop("Title, description, contact name and contact email are required")
  }
  if (!grepl("^[a-z0-9._%+\\-]+@vims\\.edu$", tolower(record$contact_email))) {
    stop("Contact email must be @vims.edu")
  }
  if (!is.null(record$application_url) && length(record$application_url) &&
      !is.na(record$application_url[[1]]) && nzchar(record$application_url[[1]]) &&
      !grepl("^https?://", record$application_url[[1]], ignore.case=TRUE)) {
    stop("Application URL must begin with https:// or http://")
  }
  names_to_update <- c("opportunity_name", "description", "qualification", "opportunity_type",
     "academic_term", "student_level", date_cols, "compensation_type", "compensation_details",
     "work_setting", "location", "department_center", "time_commitment", "contact_name",
     "contact_email", "application_url")
  params <- lapply(names_to_update, function(name) {
    x <- record[[name]]
    if (is.null(x) || length(x) == 0 || is.na(x[[1]]) || !nzchar(trimws(as.character(x[[1]])))) {
      NA_character_
    } else {
      as.character(x[[1]])
    }
  })
  names(params) <- names_to_update
  params$status <- status
  params$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  params$id <- id
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  setters <- paste(paste0(names_to_update, " = :", names_to_update), collapse = ", ")
  sql <- paste0("UPDATE opportunities SET ", setters,
                ", status = :status, updated_at = :updated_at WHERE id = :id")
  affected <- DBI::dbExecute(con, sql, params = params)
  if (affected != 1) stop("Opportunity ID was not found")
  invisible(TRUE)
}

update_admin_status <- function(id, status) {
  if (!status %in% c("pending", "approved", "closed", "rejected")) stop("Invalid status")
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (identical(status, "approved")) {
    row <- DBI::dbGetQuery(con, "SELECT start_date,end_date,application_deadline,expiration_date
      FROM opportunities WHERE id=:id", params = list(id=id))
    if (!nrow(row) || any(is.na(row[1, ])) || any(!nzchar(unlist(row[1, ], use.names=FALSE)))) {
      stop("All dates must be populated before approval")
    }
    all_dates <- lapply(row[1, ], as.Date)
    if (any(vapply(all_dates, function(x) is.na(x), logical(1))) ||
        all_dates$end_date < all_dates$start_date ||
        any(vapply(all_dates[c("end_date", "application_deadline", "expiration_date")],
                   function(x) x < Sys.Date(), logical(1)))) {
      stop("Dates are invalid or the opportunity is already past its deadline")
    }
  }
  result <- DBI::dbExecute(con,
     "UPDATE opportunities SET status=:status, updated_at=:updated_at WHERE id=:id",
     params=list(status=status,updated_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),id=id))
  if (result != 1) stop("Opportunity not found")
  invisible(TRUE)
}

resolve_change_request <- function(id, status) {
  if (!status %in% c("resolved", "dismissed")) stop("Invalid request status")
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  result <- DBI::dbExecute(con,
    "UPDATE change_requests SET status=:status, resolved_at=:resolved_at WHERE id=:id",
    params=list(status=status,resolved_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),id=id))
  if (result != 1) stop("Change request not found")
  invisible(TRUE)
}
