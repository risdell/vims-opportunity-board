suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(stringr)
  library(lubridate)
})
source("../public/R/database.R")
initialize_database()

# This app must NOT be linked under /srv/shiny-server while unauthenticated.
# Run only bound to 127.0.0.1 through an SSH tunnel until SSO is provisioned.
admin_env <- "/etc/vims-opportunity-board/admin.env"
if (file.exists(admin_env)) readRenviron(admin_env)
ADMIN_PASSWORD <- Sys.getenv("OPPORTUNITY_ADMIN_PASSWORD")
if (!nzchar(ADMIN_PASSWORD)) {
  stop("Admin password not configured: have IT create /etc/vims-opportunity-board/admin.env")
}

choice_types <- c("Research", "Internship", "Paid employment", "Independent study", "Capstone", "Volunteer")
choice_comp <- c("Paid", "Stipend", "Academic credit", "Unpaid/volunteer", "Varies")
choice_setting <- c("Field", "Laboratory", "Computational", "Office", "Remote", "Hybrid", "Multiple")

empty_if_na <- function(x) if (is.null(x) || length(x) == 0 || is.na(x[[1]])) "" else as.character(x[[1]])
date_if_set <- function(x) {
  if (!length(x) || is.na(x[[1]]) || !nzchar(as.character(x[[1]]))) return(as.Date(NA))
  suppressWarnings(as.Date(x[[1]]))
}

ui <- fluidPage(
  theme = bs_theme(version = 5, primary = "#00677e", bg = "#f4f2ed", fg = "#06263b"),
  tags$head(tags$style(HTML(".admin-wrap{max-width:1150px;margin:1.5rem auto;} .admin-card{padding:1.2rem;border:1px solid #85b8c7;border-radius:.8rem;background:#fff;} .muted{color:#526873;}"))),
  div(class = "admin-wrap",
      h1("VIMS & Batten School Opportunity Board — Administration"),
      p(class = "muted", "For Robert Isdell. This dashboard is private, and should only run behind an authenticated connection."),
      uiOutput("admin_ui")
  )
)

server <- function(input, output, session) {
  authenticated <- reactiveVal(FALSE)
  rows <- reactiveVal(data.frame())
  requests <- reactiveVal(data.frame())
  refresh <- function() {
    rows(fetch_admin_opportunities())
    requests(fetch_change_requests())
  }
  observeEvent(input$login, {
    if (identical(input$password, ADMIN_PASSWORD)) {
      authenticated(TRUE)
      updateTextInput(session, "password", value = "")
      refresh()
    } else {
      showNotification("Incorrect password", type = "error")
    }
  })
  output$admin_ui <- renderUI({
    if (!authenticated()) {
      return(div(class = "admin-card", h3("Administrator sign-in"),
                 passwordInput("password", "Admin password"),
                 actionButton("login", "Sign in", class="btn-primary")))
    }
    tabsetPanel(
      tabPanel("Review and edit postings",
        br(), actionButton("reload", "Refresh records", class = "btn-outline-primary"),
        uiOutput("opportunity_picker"), uiOutput("opportunity_editor")
      ),
      tabPanel("Change/removal requests",
        br(), uiOutput("request_picker"), uiOutput("request_detail")
      )
    )
  })
  observeEvent(input$reload, { req(authenticated()); refresh(); showNotification("Records refreshed") })
  output$opportunity_picker <- renderUI({
    req(authenticated())
    data <- rows()
    if (!nrow(data)) return(p("No opportunities yet."))
    labels <- paste0("[", toupper(data$status), "] ", data$opportunity_name,
                     " — ", substr(data$created_at, 1, 10))
    selectInput("admin_opp_id", "Select a posting (pending first)",
                choices = stats::setNames(data$id, labels), width = "100%")
  })
  output$opportunity_editor <- renderUI({
    req(authenticated(), input$admin_opp_id)
    data <- rows()
    row <- data[data$id == input$admin_opp_id, , drop = FALSE]
    if (!nrow(row)) return(NULL)
    get <- function(name) empty_if_na(row[[name]])
    date_ui <- function(id, title, column) suppressWarnings(dateInput(id, title, value=date_if_set(row[[column]])))
    div(class="admin-card",
      p(strong("Status: "), get("status"), " · ", strong("ID: "), get("id")),
      textInput("edit_name", "Opportunity title", value=get("opportunity_name")),
      textAreaInput("edit_description", "Description", value=get("description"), rows=5),
      textAreaInput("edit_qualification", "Qualifications", value=get("qualification"), rows=3),
      fluidRow(
        column(6, selectInput("edit_type", "Type", choices=choice_types, selected=get("opportunity_type"))),
        column(6, selectInput("edit_comp", "Compensation", choices=choice_comp, selected=get("compensation_type"))),
        column(6, textInput("edit_comp_details", "Compensation details", value=get("compensation_details"))),
        column(6, selectInput("edit_setting", "Work setting", choices=choice_setting, selected=get("work_setting"))),
        column(6, textInput("edit_department", "Department / center", value=get("department_center"))),
        column(6, textInput("edit_location", "Location", value=get("location"))),
        column(6, textInput("edit_term", "Academic term", value=get("academic_term"))),
        column(6, textInput("edit_level", "Student eligibility", value=get("student_level"))),
        column(6, textInput("edit_hours", "Time commitment", value=get("time_commitment"))),
        column(6, textInput("edit_contact", "Public contact name", value=get("contact_name"))),
        column(6, textInput("edit_email", "Public VIMS contact email", value=get("contact_email"))),
        column(6, textInput("edit_url", "Application URL", value=get("application_url"))),
        column(6, date_ui("edit_start", "Start date", "start_date")),
        column(6, date_ui("edit_end", "End date", "end_date")),
        column(6, date_ui("edit_deadline", "Application deadline", "application_deadline")),
        column(6, date_ui("edit_expiration", "Board expiration", "expiration_date"))
      ),
      selectInput("edit_status", "Status when saving", choices=c("pending","approved","closed","rejected"),
                  selected=get("status")),
      div(class="d-flex gap-2 flex-wrap",
          actionButton("save_edit", "Save edits and status", class="btn-primary"),
          actionButton("approve_edit", "Approve with current edits", class="btn-success"),
          actionButton("close_edit", "Close posting", class="btn-outline-danger")
      )
    )
  })
  current_edit_values <- function() {
    list(
      opportunity_name=input$edit_name, description=input$edit_description,
      qualification=input$edit_qualification, opportunity_type=input$edit_type,
      academic_term=input$edit_term, student_level=input$edit_level,
      start_date=date_or_null(input$edit_start), end_date=date_or_null(input$edit_end),
      application_deadline=date_or_null(input$edit_deadline),
      expiration_date=date_or_null(input$edit_expiration),
      compensation_type=input$edit_comp, compensation_details=input$edit_comp_details,
      work_setting=input$edit_setting, location=input$edit_location,
      department_center=input$edit_department, time_commitment=input$edit_hours,
      contact_name=input$edit_contact, contact_email=tolower(input$edit_email),
      application_url=input$edit_url
    )
  }
  do_edit <- function(status) {
    req(authenticated(), input$admin_opp_id)
    tryCatch({
      update_admin_opportunity(input$admin_opp_id, current_edit_values(), status)
      refresh()
      showNotification(paste("Saved:", status), type="message")
    }, error=function(e) showNotification(conditionMessage(e), type="error", duration=10))
  }
  observeEvent(input$save_edit, do_edit(input$edit_status))
  observeEvent(input$approve_edit, do_edit("approved"))
  observeEvent(input$close_edit, {
    req(authenticated(), input$admin_opp_id)
    tryCatch({
      update_admin_status(input$admin_opp_id,"closed")
      refresh()
      showNotification("Posting closed.")
    },error=function(e) showNotification(conditionMessage(e), type="error", duration=10))
  })
  output$request_picker <- renderUI({
    req(authenticated())
    data <- requests()
    if (!nrow(data)) return(p("No change requests yet."))
    labels <- paste0("[", toupper(data$status), "] ", data$opportunity_title,
                     " — ", data$request_type)
    selectInput("admin_request_id", "Select a request (open first)",
                choices=stats::setNames(data$id, labels), width="100%")
  })
  output$request_detail <- renderUI({
    req(authenticated(), input$admin_request_id)
    data <- requests()
    row <- data[data$id == input$admin_request_id, , drop=FALSE]
    if (!nrow(row)) return(NULL)
    div(class="admin-card",
      p(strong("Posting: "), row$opportunity_title[[1]]),
      p(strong("Request type: "), row$request_type[[1]]),
      p(strong("Claimed email (not verified): "), row$requester_email[[1]]),
      p(strong("Linked opportunity ID: "), empty_if_na(row$opportunity_id)),
      p(strong("Details: "), row$details[[1]]),
      p("Verify the submitter by email before changing or removing a record. Use Review and edit postings to make the change, then resolve this request."),
      div(class="d-flex gap-2",
        actionButton("resolve_request", "Mark handled", class="btn-success"),
        actionButton("dismiss_request", "Dismiss request", class="btn-outline-secondary")
      )
    )
  })
  handle_request <- function(status) {
    req(authenticated(), input$admin_request_id)
    tryCatch({
      resolve_change_request(input$admin_request_id, status)
      refresh()
      showNotification(paste("Request", status))
    }, error=function(e) showNotification(conditionMessage(e), type="error", duration=10))
  }
  observeEvent(input$resolve_request, handle_request("resolved"))
  observeEvent(input$dismiss_request, handle_request("dismissed"))
}
shinyApp(ui, server)
