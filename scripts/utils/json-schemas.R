#!/usr/bin/env Rscript
# json-schemas.R - JSON schema definitions and generation functions
#
# Este ficheiro define a estrutura hierárquica dos JSONs da API:
# Dimension → Sub-dimension → Indicators (no gavetas in v2)

library(jsonlite)
library(glue)
library(lubridate)

# API Configuration ----
API_VERSION <- "2.0.0"

# Get current timestamp in ISO 8601 format
get_timestamp <- function() {
  format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# Municipality JSON Schema ----
generate_municipality_json <- function(dico, name, dimensions_data) {
  structure <- list(
    metadata = list(
      dico = dico,
      name = name,
      last_updated = get_timestamp(),
      api_version = API_VERSION
    ),
    dimensions = dimensions_data
  )

  toJSON(structure, auto_unbox = TRUE, pretty = TRUE, na = "null")
}

# Index JSON Schema ----
generate_index_json <- function(municipalities_df) {
  structure <- list(
    total = nrow(municipalities_df),
    last_updated = get_timestamp(),
    municipalities = lapply(1:nrow(municipalities_df), function(i) {
      list(
        dico = municipalities_df$dico[i],
        name = municipalities_df$name[i],
        url = glue("/v1/municipalities/{municipalities_df$dico[i]}.json")
      )
    })
  )

  toJSON(structure, auto_unbox = TRUE, pretty = TRUE)
}

# Helper: Build Indicator Object ----
build_indicator <- function(normalized, raw, unit) {
  if (!is.numeric(normalized) || normalized < 0 || normalized > 100) {
    warning(glue("Normalized value out of range [0,100]: {normalized}"))
  }

  list(
    normalized = round(normalized, 2),
    raw = raw,
    unit = unit
  )
}

# Helper: Validate Municipality JSON ----
validate_municipality_json <- function(json_string) {
  tryCatch({
    data <- fromJSON(json_string)

    checks <- c(
      "metadata" %in% names(data),
      "dimensions" %in% names(data),
      "dico" %in% names(data$metadata),
      "name" %in% names(data$metadata),
      "last_updated" %in% names(data$metadata),
      "api_version" %in% names(data$metadata)
    )

    if (!all(checks)) {
      warning("JSON structure validation failed: missing required fields")
      return(FALSE)
    }

    return(TRUE)
  }, error = function(e) {
    warning(glue("JSON validation error: {e$message}"))
    return(FALSE)
  })
}
