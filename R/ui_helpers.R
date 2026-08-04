safe_text <- function(x, fallback = "Not specified") {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) return(fallback)
  value <- stringr::str_squish(as.character(x[[1]]))
  if (!nzchar(value)) fallback else value
}

is_present <- function(x) {
  !identical(safe_text(x, fallback = ""), "")
}

format_date <- function(x, fallback = "Not specified") {
  value <- suppressWarnings(as.Date(x[[1]]))
  if (length(value) == 0 || is.na(value)) {
    fallback
  } else {
    sub(" 0", " ", format(value, "%B %d, %Y"), fixed = TRUE)
  }
}

badge <- function(text, class_name = "badge-neutral") {
  if (!nzchar(safe_text(text, fallback = ""))) return(NULL)
  tags$span(class = paste("opportunity-badge", class_name), safe_text(text))
}

link_button <- function(label, href, class_name = "btn-primary") {
  href <- safe_text(href, fallback = "")
  if (!nzchar(href)) return(NULL)
  tags$a(
    label,
    class = paste("btn", class_name),
    href = href,
    target = "_blank",
    rel = "noopener noreferrer"
  )
}

opportunity_card <- function(row) {
  deadline <- suppressWarnings(as.Date(row$application_deadline[[1]]))
  days_remaining <- if (!is.na(deadline)) as.integer(deadline - Sys.Date()) else NA_integer_

  timing_badge <- NULL
  if (!is.na(days_remaining) && days_remaining >= 0 && days_remaining <= 14) {
    timing_badge <- badge("Closing soon", "badge-alert")
  } else if (!is.na(row$created_at[[1]]) && as.Date(row$created_at[[1]]) >= Sys.Date() - 7) {
    timing_badge <- badge("New", "badge-new")
  }

  application_url <- safe_text(row$application_url, fallback = "")
  email <- safe_text(row$contact_email, fallback = "")

  tags$article(
    class = "opportunity-card",
    div(
      class = "card-topline",
      div(
        class = "badge-row",
        badge(row$opportunity_type, "badge-primary"),
        badge(row$compensation_type, "badge-compensation"),
        badge(row$work_setting, "badge-neutral"),
        timing_badge
      )
    ),
    h3(safe_text(row$opportunity_name)),
    p(class = "opportunity-department", safe_text(row$department_center)),
    p(class = "opportunity-description", safe_text(row$description)),
    div(
      class = "key-details",
      div(strong("Deadline"), span(format_date(row$application_deadline))),
      div(strong("Location"), span(safe_text(row$location))),
      div(strong("Time commitment"), span(safe_text(row$time_commitment)))
    ),
    tags$details(
      class = "opportunity-details",
      tags$summary("View full details"),
      div(
        class = "details-body",
        h4("Qualifications"),
        p(safe_text(row$qualification, fallback = "No specific qualifications were listed.")),
        h4("Timing"),
        p(paste0(
          "Start: ", format_date(row$start_date),
          " · End: ", format_date(row$end_date),
          " · Term: ", safe_text(row$academic_term)
        )),
        h4("Student eligibility"),
        p(safe_text(row$student_level)),
        h4("Compensation"),
        p(safe_text(row$compensation_details, fallback = safe_text(row$compensation_type))),
        h4("Contact"),
        p(paste0(safe_text(row$contact_name), " · ", email))
      )
    ),
    div(
      class = "card-actions",
      link_button("Application / details", application_url, "btn-primary"),
      if (nzchar(email)) link_button("Email contact", paste0("mailto:", URLencode(email)), "btn-outline-primary")
    )
  )
}
