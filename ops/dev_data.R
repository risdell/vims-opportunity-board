#!/usr/bin/env Rscript
# Development-only sample opportunities and simple approval helper.
# Refuses to run against the production SQLite database.
args <- commandArgs(trailingOnly = TRUE)
usage <- paste(
  "Usage: Rscript ops/dev_data.R seed",
  "       Rscript ops/dev_data.R pending",
  "       Rscript ops/dev_data.R approve <opportunity-id>",
  "       Rscript ops/dev_data.R remove-demo",
  sep = "\n"
)
if (!length(args) || !args[[1]] %in% c("seed", "pending", "approve", "remove-demo")) {
  stop(usage, call. = FALSE)
}
expected <- "/var/lib/vims-opportunity-board-dev/opportunities.sqlite"
db <- Sys.getenv("OPPORTUNITY_DB", unset = "")
if (!identical(db, expected)) {
  stop("Refusing to run: OPPORTUNITY_DB must be exactly ", expected, call. = FALSE)
}
if (!dir.exists(dirname(db)) || normalizePath(dirname(db), mustWork = TRUE) != dirname(db)) {
  stop("Development database directory is missing or redirects elsewhere.", call. = FALSE)
}
if (file.exists(db) && nzchar(Sys.readlink(db))) {
  stop("Refusing to use a symlinked SQLite file.", call. = FALSE)
}
file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(file_arg) != 1L) stop("Run this script with Rscript.", call. = FALSE)
script_path <- sub("^--file=", "", file_arg[[1]])
repo <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo, "public", "R", "database.R"))
initialize_database()

con <- db_connect()
command <- args[[1]]

if (command == "pending") {
  rows <- DBI::dbGetQuery(
    con, "SELECT id, opportunity_name, created_at FROM opportunities
          WHERE status='pending' ORDER BY created_at DESC LIMIT 50"
  )
  if (!nrow(rows)) cat("No pending development submissions.\n") else print(rows, row.names = FALSE)
} else if (command == "approve") {
  if (length(args) != 2L || !nzchar(args[[2]])) stop(usage, call. = FALSE)
  row <- DBI::dbGetQuery(
    con, "SELECT opportunity_name, status FROM opportunities WHERE id = :id",
    params = list(id = args[[2]])
  )
  if (nrow(row) != 1L || row$status[[1]] != "pending") {
    stop("No pending development submission exists with that ID.", call. = FALSE)
  }
  cat("Approve development posting: ", row$opportunity_name[[1]], "?\n", sep = "")
  cat("Type YES to continue: ")
  answer <- readLines("stdin", n = 1L, warn = FALSE)
  if (!identical(answer, "YES")) stop("Cancelled.", call. = FALSE)
  update_admin_status(args[[2]], "approved")
  cat("Approved in DEVELOPMENT only.\n")
} else if (command == "seed") {
  today <- Sys.Date()
  demo_records <- list(
    list(
      opportunity_name = "DEMO – Coastal GIS and Data Science Internship",
      description = paste(
        "TEST OPPORTUNITY ONLY — NOT A REAL POSITION.",
        "Practice interpreting shorelines, producing maps, and examining Chesapeake Bay data.",
        "This longer description is designed to test how opportunity cards wrap and expand",
        "at mobile widths and at 200% and 400% zoom."
      ),
      qualification = "Experience with R or GIS is helpful but is not required.",
      opportunity_type = "Internship",
      compensation_type = "Paid",
      compensation_details = "Demonstration only; no stipend or position available.",
      work_setting = "Computational",
      department_center = "Demonstration Research Group",
      location = "Example location, Virginia",
      time_commitment = "8–10 hours per week",
      student_level = "Undergraduate students",
      application_url = "https://www.vims.edu/"
    ),
    list(
      opportunity_name = "DEMO – Laboratory Assistant",
      description = "TEST OPPORTUNITY ONLY. This short sample has no application URL and limited detail. It is not accepting applications.",
      qualification = NA_character_,
      opportunity_type = "Research",
      compensation_type = "Unpaid/volunteer",
      compensation_details = NA_character_,
      work_setting = "Laboratory",
      department_center = "Demonstration Research Group",
      location = NA_character_,
      time_commitment = NA_character_,
      student_level = NA_character_,
      application_url = NA_character_
    ),
    list(
      opportunity_name = "DEMO – A Very Long Opportunity Name to Test Card Layout, Keyboard Navigation, Screen Readers, and Smaller Mobile Screens",
      description = "TEST OPPORTUNITY ONLY. Check focus outlines, expandable details, link names, and repeated cards. This is not a real opening.",
      qualification = "None—accessibility testing only.",
      opportunity_type = "Capstone",
      compensation_type = "Academic credit",
      compensation_details = "Demonstration record; no actual course credit.",
      work_setting = "Remote",
      department_center = "Demonstration Research Group",
      location = "Remote (demonstration)",
      time_commitment = "Variable",
      student_level = "All levels",
      application_url = NA_character_
    )
  )
  created <- 0L
  for (i in seq_along(demo_records)) {
    record <- demo_records[[i]]
    existing <- DBI::dbGetQuery(
      con, "SELECT id FROM opportunities WHERE opportunity_name = :name",
      params = list(name = record$opportunity_name)
    )
    if (nrow(existing)) {
      # Reopen only these named demonstration fixtures when their dates age out.
      DBI::dbExecute(
        con,
        "UPDATE opportunities
         SET start_date=:start_date, end_date=:end_date,
             application_deadline=:deadline, expiration_date=:expiration,
             status='approved', updated_at=:updated_at
         WHERE id=:id",
        params = list(
          start_date = as.character(today + 14L),
          end_date = as.character(today + 120L),
          deadline = as.character(today + if (i == 1L) 7L else 35L),
          expiration = as.character(today + 90L),
          updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
          id = existing$id[[1]]
        )
      )
      cat("Refreshed existing demo: ", record$opportunity_name, "\n", sep = "")
      next
    }
    record$start_date <- as.character(today + 14L)
    record$end_date <- as.character(today + 120L)
    record$application_deadline <- as.character(today + if (i == 1L) 7L else 35L)
    record$expiration_date <- as.character(today + 90L)
    record$academic_term <- "Demo term"
    record$contact_name <- "Demonstration Contact (not real)"
    record$contact_email <- "noreply@example.invalid"
    id <- submit_opportunity(record, status = "approved")
    cat("Created: ", record$opportunity_name, " (", id, ")\n", sep = "")
    created <- created + 1L
  }
  cat("Created ", created, " demonstration records in DEVELOPMENT only.\n", sep = "")
} else if (command == "remove-demo") {
  rows <- DBI::dbGetQuery(
    con, "SELECT id, opportunity_name FROM opportunities
          WHERE opportunity_name LIKE 'DEMO – %'"
  )
  if (!nrow(rows)) {
    cat("No named demonstration records to remove.\n")
  } else {
    print(rows, row.names = FALSE)
    cat("Type DELETE DEMO to remove only these development records: ")
    answer <- readLines("stdin", n = 1L, warn = FALSE)
    if (!identical(answer, "DELETE DEMO")) stop("Cancelled.", call. = FALSE)
    DBI::dbExecute(con, "DELETE FROM opportunities WHERE opportunity_name LIKE 'DEMO – %'")
    cat("Removed named demonstration records in DEVELOPMENT only.\n")
  }
}

DBI::dbDisconnect(con)
