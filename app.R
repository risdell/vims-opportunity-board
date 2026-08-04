library(shiny)
library(bslib)
library(httr2)
library(jsonlite)
library(dplyr)
library(stringr)
library(purrr)
library(lubridate)
library(readr)
library(htmltools)

source("R/supabase.R")
source("R/ui_helpers.R")

SUPABASE_URL <- Sys.getenv("SUPABASE_URL")
SUPABASE_PUBLISHABLE_KEY <- Sys.getenv("SUPABASE_PUBLISHABLE_KEY")
SUPABASE_CONFIGURED <- nzchar(SUPABASE_URL) && nzchar(SUPABASE_PUBLISHABLE_KEY)

app_theme <- bs_theme(
  version = 5,
  bootswatch = "flatly",
  primary = "#005F73",
  secondary = "#0A9396",
  base_font = font_google("Source Sans 3"),
  heading_font = font_google("Source Sans 3")
)

browse_panel <- nav_panel(
  "Browse opportunities",
  div(
    class = "page-shell",
    div(
      class = "hero",
      div(
        class = "hero-copy",
        h1("VIMS Research & Internship Opportunities"),
        p("Explore research, internships, fieldwork, laboratory, and data-science opportunities available to William & Mary students.")
      ),
      div(class = "hero-mark", "VIMS")
    ),
    if (!SUPABASE_CONFIGURED) {
      div(
        class = "demo-banner",
        strong("Demo mode: "),
        "the app is using the included sample data because Supabase environment variables are not configured."
      )
    },
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
        h2("Submit a VIMS opportunity", class = "mb-1"),
        p(
          "Submissions are reviewed before appearing on the public board. Please provide a VIMS contact email.",
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
        suppressWarnings(dateInput("submit_start_date", "Start date", value = as.Date(NA))),
        suppressWarnings(dateInput("submit_end_date", "End date", value = as.Date(NA))),
        suppressWarnings(dateInput("submit_deadline", "Application deadline", value = as.Date(NA))),
        suppressWarnings(dateInput("submit_expiration", "Board expiration date", value = as.Date(NA))),
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
        if (SUPABASE_CONFIGURED) {
          actionButton("submit_opportunity", "Submit for review", class = "btn-primary")
        } else {
          tags$button("Configure Supabase to enable submissions", class = "btn btn-secondary", disabled = "disabled")
        },
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
      p("This board helps William & Mary students discover research and internship opportunities offered through VIMS."),
      p("Each opportunity is maintained by its listed contact. Students should confirm dates, eligibility, compensation, and expectations directly with that contact."),
      p("The board does not collect student applications or résumés. Use the email or application link shown on each opportunity card.")
    )
  )
)

ui <- page_navbar(
  title = "VIMS Opportunity Board",
  theme = app_theme,
  header = tags$head(tags$link(rel = "stylesheet", type = "text/css", href = "styles.css")),
  browse_panel,
  submit_panel,
  about_panel,
  footer = div(
    class = "app-footer",
    "VIMS Research & Internship Opportunity Board"
  )
)

server <- function(input, output, session) {
  opportunities <- reactiveVal(tibble::tibble())
  load_error <- reactiveVal(NULL)

  refresh_opportunities <- function(notify = FALSE) {
    tryCatch({
      data <- fetch_opportunities(
        supabase_url = SUPABASE_URL,
        publishable_key = SUPABASE_PUBLISHABLE_KEY,
        configured = SUPABASE_CONFIGURED
      )
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
        "Check the app logs and Supabase settings."
      )
    }
  })

  output$results_summary <- renderUI({
    n <- nrow(filtered_opportunities())
    div(
      class = "results-summary",
      h2(if (n == 1) "1 active opportunity" else paste(n, "active opportunities")),
      p("Approved opportunities are removed automatically after their board expiration date.")
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
    if (!SUPABASE_CONFIGURED) return()

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
        submit_opportunity(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, record)
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
}

shinyApp(ui, server)
