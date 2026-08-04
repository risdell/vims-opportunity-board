required_packages <- c(
  "shiny", "bslib", "httr2", "jsonlite", "dplyr", "stringr",
  "purrr", "lubridate", "readr", "htmltools", "rsconnect"
)

missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages)) {
  install.packages(missing_packages)
}

rsconnect::writeManifest()
message("Created manifest.json. Commit it before deploying to Connect Cloud.")
