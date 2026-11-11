library(shiny)
library(bslib)
library(DBI)
library(RSQLite)
library(dplyr)
library(stringr)
library(purrr)
library(lubridate)
library(htmltools)

# Require a database configuration for this deployment
if (!file.exists(".Renviron")) {
  stop("Missing instance-specific .Renviron configuration")
}

readRenviron(".Renviron")

if (!nzchar(Sys.getenv("OPPORTUNITY_DB"))) {
  stop("OPPORTUNITY_DB is not configured")
}

source("R/database.R")
source("R/ui_helpers.R")

initialize_database()

app_theme <- bs_theme(
  version = 5,
  primary = "#00677E",
  secondary = "#846838",
  bg = "#FFFFFF",
  fg = "#06263B"
)

navbar_title <- div(
  class = "navbar-brand-wrap",
  tags$img(
    src = "VIMSGlobe.png",
    alt = "VIMS logo",
    class = "navbar-brand-logo"
  ),
  tags$span("W&M’s VIMS & Batten School Opportunity Board")
)

browse_panel <- nav_panel(
  "Browse opportunities",
  div(
    class = "page-shell",
    div(
      class = "hero",
      div(
        class = "hero-copy",
        h1("VIMS & Batten School Research & Internship Opportunities"),
        p("Explore research, internships, fieldwork, laboratory, and data-science opportunities available to William & Mary students.")
      ),
      div(
        class = "hero-logo-panel",
        tags$img(
          src = "WM-VIMS-BATTEN-LOGO.png",
          alt = "William & Mary VIMS Batten School of Coastal & Marine Sciences",
          class = "hero-logo"
        )
      )
    ),
    div(
      class = "maintainer-notice",
      strong("Independently maintained resource. "),
      "This board was created and is currently maintained by Robert Isdell (risdell@vims.edu). ",
      "It is not an official William & Mary, VIMS, or Batten School posting or placement service. ",
      "Please confirm all opportunity details with the listed contact."
    ),
    layout_sidebar(
      sidebar = sidebar(
        width = 320,
        textInput(
          "search",
          "Search",
          placeholder = "Topic, lab, skill, or faculty member"
        ),
        selectizeInput(
          "opportunity_type",
          "Opportunity type",
          choices = NULL,
          multiple = TRUE
        ),
        selectizeInput(
          "compensation_type",
          "Compensation",
          choices = NULL,
          multiple = TRUE
        ),
        selectizeInput(
          "work_setting",
          "Work setting",
          choices = NULL,
          multiple = TRUE
        ),
        selectizeInput(
          "department_center",
          "Department or center",
          choices = NULL,
          multiple = TRUE
        ),
        selectInput(
          "sort_order",
          "Sort by",
          choices = c(
            "Application deadline" = "deadline",
            "Newest first" = "newest",
            "Opportunity name" = "name"
          )
        ),
        actionButton("clear_filters", "Clear filters", class = "btn-outline-secondary w-100"),
        actionButton("refresh", "Refresh opportunities", class = "btn-outline-primary w-100 mt-2")
      ),
      div(
        uiOutput("data_message"),
        uiOutput("results_summary"),
        uiOutput("opportunity_cards")
      )
    )
  )
)

submit_panel <- nav_panel(
  "Submit an opportunity",
  div(
    class = "page-shell submit-shell",
    card(
      class = "submission-card",
      card_header(
        h2("Submit a VIMS & Batten School opportunity", class = "mb-1"),
        p(
          "Robert Isdell (risdell@vims.edu) reviews submissions before they appear on the board. All dates are required; listings close when their application deadline, end date, or board expiration date passes.",
          class = "mb-0 text-muted"
        )
      ),
      layout_columns(
        col_widths = rep(6, 17),
        textInput("submit_name", "Opportunity name *"),
        selectInput(
          "submit_type",
          "Opportunity type *",
          choices = c("Research", "Internship", "Paid employment", "Independent study", "Capstone", "Volunteer")
        ),
        selectInput(
          "submit_compensation",
          "Compensation *",
          choices = c("Paid", "Stipend", "Academic credit", "Unpaid/volunteer", "Varies")
        ),
        textInput("submit_compensation_details", "Compensation details"),
        textInput("submit_department", "Department or center *"),
        textInput("submit_location", "Location"),
        selectInput(
          "submit_work_setting",
          "Work setting",
          choices = c("Field", "Laboratory", "Computational", "Office", "Remote", "Hybrid", "Multiple")
        ),
        textInput("submit_student_level", "Student eligibility", placeholder = "e.g., Undergraduates; rising juniors preferred"),
        textInput("submit_term", "Academic term", placeholder = "e.g., Fall 2026, Summer, year-round"),
        textInput("submit_time_commitment", "Time commitment", placeholder = "e.g., 8–10 hours/week"),
        suppressWarnings(dateInput("submit_start_date", "Start date *", value = as.Date(NA))),
        suppressWarnings(dateInput("submit_end_date", "End date *", value = as.Date(NA))),
        suppressWarnings(dateInput("submit_deadline", "Application deadline *", value = as.Date(NA))),
        suppressWarnings(dateInput("submit_expiration", "Board expiration date *", value = as.Date(NA))),
        textInput("submit_contact_name", "Contact name *"),
        textInput("submit_contact_email", "VIMS contact email *", placeholder = "name@vims.edu"),
        textInput("submit_application_url", "Application or information URL")
      ),
      textAreaInput("submit_description", "Description *", rows = 5),
      textAreaInput("submit_qualification", "Qualifications", rows = 4),
      div(
        class = "hp-field",
        textInput("submit_website", "Website")
      ),
      div(
        class = "d-flex gap-2 align-items-center",
        actionButton("submit_opportunity", "Submit for review", class = "btn-primary"),
        span("Fields marked * are required.", class = "text-muted small")
      )
    )
  )
)

about_panel <- nav_panel(
  "About",
  div(
    class = "page-shell about-shell",
    card(
      card_header(h2("About this board")),
      p("This board helps William & Mary students discover research and internship opportunities offered by members of the VIMS & Batten School community."),
      p(strong("Independent project: "), "Created and currently maintained by Robert Isdell (risdell@vims.edu). This is not an official W&M, VIMS, or Batten School employment or academic program listing service."),
      p("Each opportunity is maintained by its listed contact. Students should confirm dates, eligibility, compensation, and expectations directly with that contact."),
      p("The board does not collect student applications or résumés. Use the email or application link shown on each opportunity card."),
      p("Have an existing posting that needs an edit or removal? Use the Request a change tab. Requests are reviewed manually; entering an email address does not verify identity.")
    )
  )
)

request_panel <- nav_panel(
  "Request a change",
  div(
    class = "page-shell submit-shell",
    card(
      card_header(
        h2("Request an edit or removal"),
        p("This form is for people who submitted a posting. Robert Isdell reviews each request and may verify it by email before making a change. Submitting a request does not immediately modify the board.")
      ),
      selectInput("request_opportunity", "Existing published opportunity (optional)", choices = c("Other / pending or not listed" = "")),
      textInput("request_title", "Opportunity title (required if not selected above)"),
      textInput("request_email", "Your VIMS email address *", placeholder = "name@vims.edu"),
      selectInput("request_type", "Request type *", choices = c("Edit details" = "edit", "Remove / close listing" = "remove")),
      textAreaInput("request_details", "What should change? *", rows = 5, placeholder = "For an edit, provide the corrected text or dates. For removal, explain whether the position was filled or withdrawn."),
      div(class = "hp-field", textInput("request_website", "Website")),
      actionButton("send_change_request", "Send request to Robert Isdell", class = "btn-primary")
    )
  )
)

ui <- page_navbar(
  title = navbar_title,
  fillable = FALSE,
  bg = "#06263b",
  inverse = TRUE,
  theme = app_theme,
  header = tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "styles.css?v=20261110"),
    tags$link(rel = "icon", type = "image/png", href = "VIMSGlobe.png")
  ),
  browse_panel,
  submit_panel,
  request_panel,
  about_panel,
  footer = div(
    class = "app-footer",
    "Independent board maintained by Robert Isdell · risdell@vims.edu · W&M’s VIMS & Batten School"
  )
)

server <- function(input, output, session) {
  opportunities <- reactiveVal(tibble::tibble())
  load_error <- reactiveVal(NULL)

  refresh_opportunities <- function(notify = FALSE) {
    tryCatch({
      data <- fetch_opportunities()
      opportunities(normalize_opportunities(data))
      load_error(NULL)
      if (notify) showNotification("Opportunities refreshed.", type = "message")
    }, error = function(e) {
      load_error(conditionMessage(e))
      if (notify) showNotification("Could not refresh opportunities.", type = "error")
    })
  }

  refresh_opportunities()

  observe({
    invalidateLater(300000, session)
    refresh_opportunities()
  })

  observeEvent(input$refresh, refresh_opportunities(notify = TRUE))

  observe({
    data <- opportunities()
    change_choices <- c("Other / pending or not listed" = "")
    if (nrow(data)) {
      change_choices <- c(change_choices, stats::setNames(data$id, data$opportunity_name))
    }
    updateSelectInput(session, "request_opportunity", choices = change_choices)
    updateSelectizeInput(session, "opportunity_type", choices = sort(unique(na.omit(data$opportunity_type))), server = TRUE)
    updateSelectizeInput(session, "compensation_type", choices = sort(unique(na.omit(data$compensation_type))), server = TRUE)
    updateSelectizeInput(session, "work_setting", choices = sort(unique(na.omit(data$work_setting))), server = TRUE)
    updateSelectizeInput(session, "department_center", choices = sort(unique(na.omit(data$department_center))), server = TRUE)
  })

  observeEvent(input$clear_filters, {
    updateTextInput(session, "search", value = "")
    updateSelectizeInput(session, "opportunity_type", selected = character(0))
    updateSelectizeInput(session, "compensation_type", selected = character(0))
    updateSelectizeInput(session, "work_setting", selected = character(0))
    updateSelectizeInput(session, "department_center", selected = character(0))
    updateSelectInput(session, "sort_order", selected = "deadline")
  })

  filtered_opportunities <- reactive({
    data <- opportunities()
    if (nrow(data) == 0) return(data)

    query <- str_squish(input$search %||% "")
    if (nzchar(query)) {
      searchable <- paste(
        data$opportunity_name,
        data$description,
        data$qualification,
        data$contact_name,
        data$department_center,
        data$location,
        data$work_setting,
        sep = " | "
      )
      data <- data[str_detect(str_to_lower(searchable), fixed(str_to_lower(query))), , drop = FALSE]
    }

    if (length(input$opportunity_type)) {
      data <- data[data$opportunity_type %in% input$opportunity_type, , drop = FALSE]
    }
    if (length(input$compensation_type)) {
      data <- data[data$compensation_type %in% input$compensation_type, , drop = FALSE]
    }
    if (length(input$work_setting)) {
      data <- data[map_lgl(data$work_setting, ~ any(str_detect(.x %||% "", fixed(input$work_setting)))), , drop = FALSE]
    }
    if (length(input$department_center)) {
      data <- data[data$department_center %in% input$department_center, , drop = FALSE]
    }

    if (identical(input$sort_order, "newest")) {
      data <- arrange(data, desc(created_at), opportunity_name)
    } else if (identical(input$sort_order, "name")) {
      data <- arrange(data, opportunity_name)
    } else {
      data <- arrange(data, is.na(application_deadline), application_deadline, desc(created_at))
    }

    data
  })

  output$data_message <- renderUI({
    if (!is.null(load_error())) {
      div(
        class = "alert alert-danger",
        strong("The opportunity data could not be loaded. "),
        "Check the Shiny Server logs and SQLite database permissions."
      )
    }
  })

  output$results_summary <- renderUI({
    n <- nrow(filtered_opportunities())
    div(
      class = "results-summary",
      h2(if (n == 1) "1 active opportunity" else paste(n, "active opportunities")),
      p("Listings automatically close after their application deadline, end date, or board expiration date.")
    )
  })

  output$opportunity_cards <- renderUI({
    data <- filtered_opportunities()
    if (nrow(data) == 0) {
      return(div(
        class = "empty-state",
        h3("No opportunities match these filters"),
        p("Try clearing one or more filters or check back later.")
      ))
    }

    div(
      class = "opportunity-grid",
      tagList(lapply(seq_len(nrow(data)), function(i) opportunity_card(data[i, , drop = FALSE])))
    )
  })

  observeEvent(input$submit_opportunity, {
    if (nzchar(str_squish(input$submit_website %||% ""))) {
      showNotification("Submission could not be processed.", type = "error")
      return()
    }

    required_values <- c(
      input$submit_name,
      input$submit_department,
      input$submit_contact_name,
      input$submit_contact_email,
      input$submit_description
    )

    if (any(!nzchar(str_squish(required_values)))) {
      showNotification("Please complete all required fields.", type = "warning")
      return()
    }

    if (!str_detect(str_to_lower(str_squish(input$submit_contact_email)), "^[a-z0-9._%+\\-]+@vims\\.edu$")) {
      showNotification("Please enter a valid @vims.edu contact email.", type = "warning")
      return()
    }

    if (nchar(str_squish(input$submit_description)) < 20) {
      showNotification("Please provide a slightly fuller description.", type = "warning")
      return()
    }

    entered_dates <- lapply(
      list(input$submit_start_date, input$submit_end_date,
           input$submit_deadline, input$submit_expiration),
      function(x) if (is.null(x) || length(x) == 0) as.Date(NA) else suppressWarnings(as.Date(x))
    )
    if (any(vapply(entered_dates, function(x) is.na(x), logical(1)))) {
      showNotification("All four dates are required: start, end, application deadline, and board expiration.", type = "warning", duration = 8)
      return()
    }
    if (entered_dates[[2]] < entered_dates[[1]]) {
      showNotification("End date cannot be before start date.", type = "warning")
      return()
    }
    if (any(vapply(entered_dates[c(2, 3, 4)], function(x) x < Sys.Date(), logical(1)))) {
      showNotification("End date, application deadline, and board expiration must not be in the past.", type = "warning", duration = 8)
      return()
    }

    record <- list(
      opportunity_name = str_squish(input$submit_name),
      description = str_squish(input$submit_description),
      qualification = null_if_blank(input$submit_qualification),
      opportunity_type = input$submit_type,
      academic_term = null_if_blank(input$submit_term),
      student_level = null_if_blank(input$submit_student_level),
      start_date = date_or_null(input$submit_start_date),
      end_date = date_or_null(input$submit_end_date),
      application_deadline = date_or_null(input$submit_deadline),
      expiration_date = date_or_null(input$submit_expiration),
      compensation_type = input$submit_compensation,
      compensation_details = null_if_blank(input$submit_compensation_details),
      work_setting = null_if_blank(input$submit_work_setting),
      location = null_if_blank(input$submit_location),
      department_center = str_squish(input$submit_department),
      time_commitment = null_if_blank(input$submit_time_commitment),
      contact_name = str_squish(input$submit_contact_name),
      contact_email = str_to_lower(str_squish(input$submit_contact_email)),
      application_url = null_if_blank(input$submit_application_url),
      status = "pending"
    )

    withProgress(message = "Submitting opportunity...", value = 0.5, {
      tryCatch({
        submit_opportunity(record)
        incProgress(0.5)
        showModal(modalDialog(
          title = "Submission received",
          "Thank you. The opportunity has been sent for review and will appear on the board after approval.",
          easyClose = TRUE,
          footer = modalButton("Close")
        ))
        updateTextInput(session, "submit_name", value = "")
        updateTextInput(session, "submit_compensation_details", value = "")
        updateTextInput(session, "submit_department", value = "")
        updateTextInput(session, "submit_location", value = "")
        updateTextInput(session, "submit_student_level", value = "")
        updateTextInput(session, "submit_term", value = "")
        updateTextInput(session, "submit_time_commitment", value = "")
        updateTextInput(session, "submit_contact_name", value = "")
        updateTextInput(session, "submit_contact_email", value = "")
        updateTextInput(session, "submit_application_url", value = "")
        updateTextAreaInput(session, "submit_description", value = "")
        updateTextAreaInput(session, "submit_qualification", value = "")
        suppressWarnings(updateDateInput(session, "submit_start_date", value = as.Date(NA)))
        suppressWarnings(updateDateInput(session, "submit_end_date", value = as.Date(NA)))
        suppressWarnings(updateDateInput(session, "submit_deadline", value = as.Date(NA)))
        suppressWarnings(updateDateInput(session, "submit_expiration", value = as.Date(NA)))
      }, error = function(e) {
        showNotification(
          paste("Submission failed:", conditionMessage(e)),
          type = "error",
          duration = 10
        )
      })
    })
  })

  observeEvent(input$send_change_request, {
    if (nzchar(str_squish(input$request_website %||% ""))) return()
    email <- str_to_lower(str_squish(input$request_email %||% ""))
    details <- str_squish(input$request_details %||% "")
    if (!str_detect(email, "^[a-z0-9._%+\\-]+@vims\\.edu$") || nchar(details) < 10) {
      showNotification("Provide a valid @vims.edu email and at least 10 characters describing the request.", type = "warning", duration = 8)
      return()
    }
    selected <- input$request_opportunity %||% ""
    title <- str_squish(input$request_title %||% "")
    if (!nzchar(selected) && !nzchar(title)) {
      showNotification("Please select a published opportunity or enter its title.", type = "warning")
      return()
    }
    if (nzchar(selected)) {
      data <- opportunities()
      match <- data[data$id == selected, , drop = FALSE]
      if (!nrow(match)) {
        showNotification("That opportunity could not be found; refresh and try again.", type = "warning")
        return()
      }
      title <- match$opportunity_name[[1]]
    }
    tryCatch({
      create_change_request(
        opportunity_id = if (nzchar(selected)) selected else NULL,
        opportunity_title = title,
        requester_email = email,
        request_type = input$request_type,
        details = details
      )
      showModal(modalDialog(
        title = "Request received",
        "Robert Isdell will review your request and may contact you to confirm it before changing the listing.",
        easyClose = TRUE, footer = modalButton("Close")
      ))
      updateTextInput(session, "request_title", value = "")
      updateTextInput(session, "request_email", value = "")
      updateTextAreaInput(session, "request_details", value = "")
      updateSelectInput(session, "request_opportunity", selected = "")
    }, error = function(e) {
      showNotification("Unable to record the request. Please email risdell@vims.edu.", type = "error", duration = 9)
      warning("Change request insert failed: ", conditionMessage(e))
    })
  })
}

shinyApp(ui, server)
