library(shiny)

destination <- "https://shiny.vims.edu/OpportunityBoard/"

ui <- fluidPage(
  tags$head(
    tags$title("VIMS Opportunity Board — Redirect"),

    # Automatic redirect, including for browsers without JavaScript
    tags$meta(
      `http-equiv` = "refresh",
      content = paste0("0; url=", destination)
    ),

    # Avoid leaving the old URL in browser history
    tags$script(HTML(
      "window.location.replace('https://shiny.vims.edu/OpportunityBoard/');"
    ))
  ),

  div(
    style = paste(
      "max-width:600px; margin:80px auto;",
      "padding:20px; text-align:center;",
      "font-family:Arial,sans-serif;"
    ),

    h2("The Opportunity Board has moved"),

    p("You are being redirected to the new VIMS-hosted board."),

    p(
      a(
        "Click here if you are not redirected automatically.",
        href = destination
      )
    )
  )
)

server <- function(input, output, session) {}

shinyApp(ui, server)
