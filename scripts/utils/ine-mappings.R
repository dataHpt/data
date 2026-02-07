#!/usr/bin/env Rscript
# ine-mappings.R - Load indicator mappings from CSV
#
# ✅ EDITAR INDICADORES: Abrir ine-mappings.csv (Excel/Google Sheets)
#
# Este script carrega automaticamente os dados do CSV e valida

library(readr)
library(dplyr)
library(glue)

# Load Mappings from CSV ----

# Get script directory
script_dir <- if (interactive()) {
  tryCatch(dirname(rstudioapi::getSourceEditorContext()$path), error = function(e) NULL)
} else {
  tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NULL)
}

# Fallback if neither works
if (is.null(script_dir) || script_dir == "") {
  script_dir <- "scripts/utils"
}

# Path to CSV file
csv_path <- file.path(script_dir, "ine-mappings.csv")

# Check if CSV exists
if (!file.exists(csv_path)) {
  # Try alternative path (if running from project root)
  csv_path <- "scripts/utils/ine-mappings.csv"

  if (!file.exists(csv_path)) {
    stop("Cannot find ine-mappings.csv. Please ensure it exists in scripts/utils/")
  }
}

# Load CSV
message(glue("Loading indicator mappings from {csv_path}"))

ine_indicator_mappings <- read_csv(
  csv_path,
  col_types = cols(
    indicator_id = col_character(),
    indicator_number = col_character(),
    indicator_name = col_character(),
    description = col_character(),
    frontend_name = col_character(),
    frontend_text = col_character(),
    dimension = col_character(),
    sub_dimension = col_character(),
    unit = col_character(),
    direction = col_character(),
    polarity = col_character(),
    year = col_character(),
    source = col_character(),
    source_url = col_character(),
    code = col_character(),
    fetch_type = col_character(),
    dim3_filter = col_character(),
    dim4_filter = col_character(),
    notes = col_character()
  ),
  show_col_types = FALSE
)

# Convert year column: "NA" string → NA value
ine_indicator_mappings <- ine_indicator_mappings %>%
  mutate(
    year = ifelse(year == "NA" | is.na(year), NA_real_, as.numeric(year))
  )

message(glue("✓ Loaded {nrow(ine_indicator_mappings)} indicators"))

# Validation ----

validate_mappings <- function(mappings) {
  # Check campos obrigatórios
  required_cols <- c(
    "indicator_id",
    "indicator_number",
    "indicator_name",
    "dimension",
    "sub_dimension",
    "unit",
    "direction",
    "fetch_type"
  )

  missing_cols <- setdiff(required_cols, names(mappings))
  if (length(missing_cols) > 0) {
    stop(glue("Missing required columns in CSV: {paste(missing_cols, collapse=', ')}"))
  }

  # Check duplicados
  if (any(duplicated(mappings$indicator_id))) {
    duplicates <- mappings$indicator_id[duplicated(mappings$indicator_id)]
    stop(glue("Duplicate indicator IDs found: {paste(duplicates, collapse=', ')}"))
  }

  # Check direction values
  valid_directions <- c("lower_is_better", "higher_is_better")
  invalid_directions <- mappings %>%
    filter(!direction %in% valid_directions) %>%
    pull(indicator_id)

  if (length(invalid_directions) > 0) {
    stop(glue("Invalid direction values for: {paste(invalid_directions, collapse=', ')}"))
  }

  # Check valid dimensions
  valid_dimensions <- c("territorio_populacao_habitacao", "ambiente_energia_riscos")
  invalid_dims <- mappings %>%
    filter(!dimension %in% valid_dimensions) %>%
    pull(indicator_id)

  if (length(invalid_dims) > 0) {
    stop(glue("Invalid dimension values for: {paste(invalid_dims, collapse=', ')}"))
  }

  # Check valid sub-dimensions
  valid_sub_dimensions <- c(
    "socio_demograficas", "socio_economicas", "socio_territoriais",
    "acesso_habitacao", "parque_habitacional",
    "habitacao_energia", "habitat", "riscos_naturais"
  )
  invalid_sub_dims <- mappings %>%
    filter(!sub_dimension %in% valid_sub_dimensions) %>%
    pull(indicator_id)

  if (length(invalid_sub_dims) > 0) {
    stop(glue("Invalid sub_dimension values for: {paste(invalid_sub_dims, collapse=', ')}"))
  }

  # Check valid fetch_type values
  valid_fetch_types <- c("ine_api", "dgt_api", "static")
  invalid_fetch_types <- mappings %>%
    filter(!fetch_type %in% valid_fetch_types) %>%
    pull(indicator_id)

  if (length(invalid_fetch_types) > 0) {
    stop(glue("Invalid fetch_type values for: {paste(invalid_fetch_types, collapse=', ')}"))
  }

  # Check API indicators have codes
  api_without_code <- mappings %>%
    filter(fetch_type %in% c("ine_api", "dgt_api"), (is.na(code) | code == "")) %>%
    pull(indicator_id)

  if (length(api_without_code) > 0) {
    warning(glue("API indicators missing code: {paste(api_without_code, collapse=', ')}"))
  }

  message(glue("✓ Validation passed ({nrow(mappings)} indicators)"))
  return(TRUE)
}

# Run validation
validate_mappings(ine_indicator_mappings)

# Helper Functions ----

#' Get mapping for specific indicator
get_indicator_mapping <- function(indicator_id) {
  mapping <- ine_indicator_mappings %>%
    filter(indicator_id == !!indicator_id)

  if (nrow(mapping) == 0) {
    stop(glue("No mapping found for indicator: {indicator_id}"))
  }

  return(as.list(mapping[1, ]))
}

#' Get all indicators for a dimension
get_dimension_indicators <- function(dimension_name) {
  ine_indicator_mappings %>%
    filter(dimension == dimension_name)
}

#' Get all indicators for a sub-dimension
get_sub_dimension_indicators <- function(sub_dimension_name) {
  ine_indicator_mappings %>%
    filter(sub_dimension == sub_dimension_name)
}

#' Get all auto-fetchable indicators (ine_api or dgt_api)
get_api_indicators <- function() {
  ine_indicator_mappings %>%
    filter(fetch_type %in% c("ine_api", "dgt_api"))
}

#' Get all static indicators
get_static_indicators <- function() {
  ine_indicator_mappings %>%
    filter(fetch_type == "static")
}

#' Print summary statistics
print_mapping_summary <- function() {
  cat("\n=== Indicator Mappings Summary ===\n\n")

  cat("Total indicators:", nrow(ine_indicator_mappings), "\n\n")

  cat("By dimension:\n")
  ine_indicator_mappings %>%
    count(dimension) %>%
    print()

  cat("\nBy sub-dimension:\n")
  ine_indicator_mappings %>%
    count(dimension, sub_dimension) %>%
    print()

  cat("\nBy direction:\n")
  ine_indicator_mappings %>%
    count(direction) %>%
    print()

  cat("\nBy fetch_type:\n")
  ine_indicator_mappings %>%
    count(fetch_type) %>%
    print()

  # Count API indicators with codes
  api_with_code <- ine_indicator_mappings %>%
    filter(fetch_type %in% c("ine_api", "dgt_api"), !is.na(code), code != "") %>%
    nrow()

  api_total <- ine_indicator_mappings %>%
    filter(fetch_type %in% c("ine_api", "dgt_api")) %>%
    nrow()

  cat("\nAPI mapping status:\n")
  cat(glue("  ✓ With code: {api_with_code}/{api_total}\n"))
  cat(glue("  Static: {nrow(ine_indicator_mappings) - api_total}\n"))
}
