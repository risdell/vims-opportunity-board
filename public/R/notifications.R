# Optional institutional SMTP notification sender.
# Configure credentials only in /etc/vims-opportunity-board/mail.env (never in Git).
load_notification_config <- function(path = "/etc/vims-opportunity-board/mail.env") {
  if (file.exists(path)) readRenviron(path)
}

notification_ready <- function() {
  nzchar(Sys.getenv("OPPORTUNITY_SMTP_SERVER")) &&
    nzchar(Sys.getenv("OPPORTUNITY_MAIL_FROM")) &&
    nzchar(Sys.getenv("OPPORTUNITY_NOTIFY_TO"))
}

mail_safe_header <- function(x) gsub("[\\r\\n]+", " ", as.character(x))

send_board_message <- function(subject, body) {
  if (!notification_ready()) stop("SMTP is not configured; no message sent")
  sender <- Sys.getenv("OPPORTUNITY_MAIL_FROM")
  recipient <- Sys.getenv("OPPORTUNITY_NOTIFY_TO")
  if (!grepl("^[^@[:space:]]+@[^@[:space:]]+$", sender) ||
      !grepl("^[^@[:space:]]+@[^@[:space:]]+$", recipient)) {
    stop("Notification sender/recipient must be plain valid email addresses")
  }
  message <- paste0(
    "From: ", mail_safe_header(sender), "\r\n",
    "To: ", mail_safe_header(recipient), "\r\n",
    "Subject: ", mail_safe_header(subject), "\r\n",
    "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n",
    gsub("\\r?\\n", "\r\n", body)
  )
  args <- list(
    mail_from = sender, mail_rcpt = recipient, message = message,
    smtp_server = Sys.getenv("OPPORTUNITY_SMTP_SERVER"),
    use_ssl = Sys.getenv("OPPORTUNITY_SMTP_TLS", "force"),
    verbose = FALSE, connecttimeout = 10, timeout = 20
  )
  user <- Sys.getenv("OPPORTUNITY_SMTP_USER")
  password <- Sys.getenv("OPPORTUNITY_SMTP_PASSWORD")
  if (nzchar(user)) args$username <- user
  if (nzchar(password)) args$password <- password
  do.call(curl::send_mail, args)
  invisible(TRUE)
}

# Cron calls this every minute. Records are marked only after SMTP accepts
# the message. Failed sends remain queued for the next attempt.
send_pending_notifications <- function() {
  load_notification_config()
  if (!notification_ready()) {
    message("SMTP not configured; leaving notifications queued.")
    return(invisible(FALSE))
  }
  con <- db_connect()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  opps <- DBI::dbGetQuery(con, "SELECT id,opportunity_name,contact_name,contact_email,created_at
      FROM opportunities WHERE notification_sent_at IS NULL ORDER BY created_at ASC LIMIT 100")
  requests <- DBI::dbGetQuery(con, "SELECT id,opportunity_title,requester_email,request_type,created_at,details
      FROM change_requests WHERE notification_sent_at IS NULL ORDER BY created_at ASC LIMIT 100")
  sent <- 0L
  for (i in seq_len(nrow(opps))) {
    row <- opps[i, , drop = FALSE]
    subject <- "[Opportunity Board] New opportunity awaiting review"
    body <- paste0("A new VIMS & Batten School opportunity is awaiting your review.\n\n",
      "Title: ", row$opportunity_name[[1]], "\n",
      "Contact: ", row$contact_name[[1]], " <", row$contact_email[[1]], ">\n",
      "Submitted: ", row$created_at[[1]], "\n\n",
      "Open the protected Opportunity Board admin dashboard to review it.")
    tryCatch({
      send_board_message(subject, body)
      DBI::dbExecute(con, "UPDATE opportunities SET notification_sent_at=:now WHERE id=:id AND notification_sent_at IS NULL",
        params=list(now=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),id=row$id[[1]]))
      sent <- sent + 1L
    }, error = function(e) warning("Opportunity notification failed: ", conditionMessage(e)))
  }
  for (i in seq_len(nrow(requests))) {
    row <- requests[i, , drop = FALSE]
    subject <- "[Opportunity Board] New change/removal request"
    body <- paste0("A new request needs review. No change has been applied.\n\n",
      "Title: ", row$opportunity_title[[1]], "\n",
      "Request: ", row$request_type[[1]], "\n",
      "Claimed email: ", row$requester_email[[1]], " (NOT VERIFIED)\n",
      "Details: ", row$details[[1]], "\n\n",
      "Confirm the submitter's identity before editing/removing a listing.")
    tryCatch({
      send_board_message(subject, body)
      DBI::dbExecute(con, "UPDATE change_requests SET notification_sent_at=:now WHERE id=:id AND notification_sent_at IS NULL",
        params=list(now=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),id=row$id[[1]]))
      sent <- sent + 1L
    }, error = function(e) warning("Change request notification failed: ", conditionMessage(e)))
  }
  message("Notification emails accepted by SMTP: ", sent)
  invisible(sent)
}
