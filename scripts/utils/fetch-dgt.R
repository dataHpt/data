#!/usr/bin/env Rscript
# fetch-dgt.R - Fetch indicator data from DGT Observatório API
#
# Based on working shell script that uses complete query parameters
# API: https://observatorioindicadores.dgterritorio.gov.pt/websig/bi/ngGeoAPI/

library(httr)
library(jsonlite)
library(dplyr)
library(glue)
library(stringr)

# DGT API Configuration ----

DGT_BASE_URL <- "https://observatorioindicadores.dgterritorio.gov.pt/websig/bi/ngGeoAPI/public/index.php"

# Level 5 = Municipality (Concelho)
DGT_LEVEL_MUNICIPALITY <- 5

# Time = 1 (most recent data)
DGT_TIME_CURRENT <- 1

#' Fetch DGT Indicator Data
#'
#' Fetches data for a specific indicator from DGT Observatório API using
#' the complete query parameters discovered from working shell script
#'
#' @param indicator_id Numeric DGT indicator ID (e.g., 552)
#' @param level Geographic level (default: 5 for municipality)
#' @param time Time period (default: 1 for most recent)
#' @param timeout Request timeout in seconds (default: 30)
#'
#' @return Data frame with columns: dico, value, geodsg (municipality name)
#'
#' @examples
#' # Fetch edificios fora do perímetro urbano (indicator 552)
#' data <- fetch_dgt_indicator(indicator_id = 552)
fetch_dgt_indicator <- function(indicator_id,
                                level = DGT_LEVEL_MUNICIPALITY,
                                time = DGT_TIME_CURRENT,
                                timeout = 30) {

  # Validate indicator_id
  if (is.null(indicator_id) || is.na(indicator_id)) {
    stop("indicator_id cannot be NULL or NA")
  }

  # Convert to numeric if character
  if (is.character(indicator_id)) {
    indicator_id <- as.numeric(indicator_id)
  }

  message(glue("Fetching DGT indicator {indicator_id}, level {level}, time {time}..."))

  # Build request URL with /metrics/load endpoint
  url <- glue("{DGT_BASE_URL}/metrics/load")

  # Build complete query parameters matching working shell script
  query_params <- list(
    par = "observatorio",
    mod = "metrics",
    param = indicator_id,
    type = "0",
    table = "t_new_observatorio_dat",
    identifier = "0",
    query = glue("and category_geo = {level} and category_time = {time}"),
    classification = "2",
    lang = "pt",
    numclasses = "5",
    indicator_type = "0",
    precision = "1",
    columns = "category_time",
    rows = "category_geo",
    colors = "#FED976,#FD8D3C,#FC4E2A,#E31A1C,#B10026,#770038,#4D0025"
  )

  # Make API request
  response <- tryCatch({
    GET(
      url,
      query = query_params,
      httr::timeout(timeout),
      add_headers(
        "User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "Accept" = "application/json"
      )
    )
  }, error = function(e) {
    stop(glue("HTTP request failed for DGT indicator {indicator_id}: {e$message}"))
  })

  # Check HTTP status
  if (status_code(response) != 200) {
    stop(glue(
      "DGT API returned status {status_code(response)} for indicator {indicator_id}"
    ))
  }

  # Parse JSON response
  content_text <- content(response, "text", encoding = "UTF-8")

  if (nchar(content_text) == 0) {
    stop(glue("Empty response from DGT API for indicator {indicator_id}"))
  }

  json_data <- tryCatch({
    fromJSON(content_text, simplifyVector = TRUE)
  }, error = function(e) {
    stop(glue("Failed to parse DGT JSON for indicator {indicator_id}: {e$message}"))
  })

  # Check response type
  if (json_data$type != "SUCCESS") {
    stop(glue("DGT API returned non-success type for indicator {indicator_id}: {json_data$type}"))
  }

  # Extract embedded GeoJSON from content
  if (is.null(json_data$content$geojson) || length(json_data$content$geojson) == 0) {
    warning(glue("No GeoJSON data found in DGT response for indicator {indicator_id}"))
    return(data.frame(
      dico = character(0),
      value = numeric(0),
      geodsg = character(0)
    ))
  }

  # Parse embedded GeoJSON string
  geojson_string <- json_data$content$geojson[1]
  geojson_data <- fromJSON(geojson_string, simplifyVector = TRUE)

  # Parse GeoJSON response
  parsed_data <- parse_dgt_geojson(geojson_data, indicator_id)

  message(glue("✓ Fetched {nrow(parsed_data)} municipalities from DGT indicator {indicator_id}"))

  return(parsed_data)
}

#' Parse DGT GeoJSON Response
#'
#' Converts DGT GeoJSON format to standardized data frame
#' Based on actual structure: features[].properties{id, code, name, value}
#'
#' @param geojson_data Parsed GeoJSON object from DGT API
#' @param indicator_id DGT indicator ID (for error messages)
#'
#' @return Data frame with columns: dico, value, geodsg
parse_dgt_geojson <- function(geojson_data, indicator_id) {

  # Extract features
  features <- geojson_data$features

  if (is.null(features) || nrow(features) == 0) {
    warning(glue("No features found in DGT response for indicator {indicator_id}"))
    return(data.frame(
      dico = character(0),
      value = numeric(0),
      geodsg = character(0)
    ))
  }

  # Extract properties (already a data frame from simplifyVector = TRUE)
  props <- features$properties

  # DGT structure: id, code, name, value
  # code is usually 4-digit DICO
  df <- props %>%
    as.data.frame() %>%
    mutate(
      code = as.character(code),
      value = as.numeric(value),
      name = as.character(name)
    ) %>%
    select(code, name, value)

  # Convert code to DICO format (4 digits)
  # Some DGT data might use DICOFRE (6 digits) or other formats
  df <- df %>%
    mutate(
      dico = case_when(
        nchar(code) == 4 ~ code,                # Already DICO
        nchar(code) == 6 ~ substr(code, 1, 4),  # DICOFRE → DICO
        TRUE ~ str_pad(code, 4, pad = "0")      # Pad if needed
      )
    ) %>%
    select(dico, value, geodsg = name)

  # Filter out invalid rows
  df <- df %>%
    filter(!is.na(dico), !is.na(value))

  # Validate DICO format (should be 4 digits)
  invalid_dico <- df %>%
    filter(nchar(dico) != 4)

  if (nrow(invalid_dico) > 0) {
    warning(glue(
      "Found {nrow(invalid_dico)} municipalities with invalid DICO format in DGT indicator {indicator_id}"
    ))
  }

  return(df)
}

#' Fetch DGT Indicator Metadata
#'
#' Retrieves metadata for a specific DGT indicator using complete query params
#'
#' @param indicator_id Numeric DGT indicator ID
#'
#' @return List with metadata fields (name, units, precision)
fetch_dgt_indicator_metadata <- function(indicator_id) {

  url <- glue("{DGT_BASE_URL}/metrics/getparaminfo")

  query_params <- list(
    par = "observatorio",
    mod = "metrics",
    rows = "category_geo",
    param = indicator_id,
    lang = "pt"
  )

  response <- GET(
    url,
    query = query_params,
    httr::timeout(10),
    add_headers(
      "User-Agent" = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
      "Accept" = "application/json"
    )
  )

  if (status_code(response) != 200) {
    warning(glue("Failed to fetch metadata for DGT indicator {indicator_id}"))
    return(NULL)
  }

  json_data <- fromJSON(content(response, "text", encoding = "UTF-8"))

  if (json_data$type != "SUCCESS") {
    warning(glue("DGT metadata request returned type: {json_data$type}"))
    return(NULL)
  }

  # Extract metadata from content$data
  metadata <- json_data$content$data

  return(metadata)
}

#' Helper: NULL coalescing operator
#' Returns first non-NULL value
`%||%` <- function(a, b) {
  if (!is.null(a)) a else b
}

# Example usage (commented out) ----
#
# # Fetch "Edifícios fora do perímetro urbano" (indicator 552)
# data <- fetch_dgt_indicator(indicator_id = 552)
#
# # View results
# head(data)
# #   dico value                geodsg
# # 1 3103   311               FUNCHAL
# # 2 4206   309 VILA FRANCA DO CAMPO
# # 3 4205   308        RIBEIRA GRANDE
#
# # Check coverage
# message(glue("Total municipalities: {nrow(data)}"))
# # Expected: 308 municipalities
#
# # Fetch metadata
# metadata <- fetch_dgt_indicator_metadata(indicator_id = 552)
# print(metadata)
# # $code: 552
# # $name: "Proporção de edifícios clássicos localizados fora do perímetro urbano"
# # $units: "[%]"
# # $precision: 1
