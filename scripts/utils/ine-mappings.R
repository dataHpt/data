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
script_dir <- ifelse(
  interactive(),
  tryCatch(dirname(rstudioapi::getSourceEditorContext()$path), error = function(e) NULL),
  tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NULL)
)

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
    indicator_name = col_character(),
    dimension = col_character(),
    sub_dimension = col_character(),
    gaveta = col_character(),
    code = col_character(),          # Unified: INE varcd or DGT ID
    unit = col_character(),
    direction = col_character(),
    year = col_character(),           # NA é lido como string
    source = col_character(),         # NEW: "INE" or "DGT"
    source_url = col_character(),     # Renamed from ine_url
    dim3_filter = col_character(),    # Filter for dim_3 (for complex indicators)
    dim4_filter = col_character()     # Filter for dim_4 (for 4-dimensional indicators)
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
    "indicator_name",
    "dimension",
    "sub_dimension",
    "gaveta",
    "code",
    "unit",
    "direction",
    "year",
    "source"
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

  # Check valores TODO
  todo_count <- sum(mappings$code == "TODO" | mappings$code == "" | is.na(mappings$code), na.rm = TRUE)
  if (todo_count > 0) {
    warning(glue("{todo_count} indicators still have TODO/empty code"))
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
  valid_dimensions <- c("coesao_territorial", "sustentabilidade_ambiental")
  invalid_dims <- mappings %>%
    filter(!dimension %in% valid_dimensions) %>%
    pull(indicator_id)

  if (length(invalid_dims) > 0) {
    stop(glue("Invalid dimension values for: {paste(invalid_dims, collapse=', ')}"))
  }

  # Check valid source values
  valid_sources <- c("INE", "DGT")
  invalid_sources <- mappings %>%
    filter(!is.na(source), !source %in% valid_sources) %>%
    pull(indicator_id)

  if (length(invalid_sources) > 0) {
    stop(glue("Invalid source values for: {paste(invalid_sources, collapse=', ')}. Must be INE or DGT"))
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

#' Get all indicators for a gaveta
get_gaveta_indicators <- function(gaveta_name) {
  ine_indicator_mappings %>%
    filter(gaveta == gaveta_name)
}

#' Print summary statistics
print_mapping_summary <- function() {
  cat("\n=== INE Indicator Mappings Summary ===\n\n")

  cat("Total indicators:", nrow(ine_indicator_mappings), "\n\n")

  cat("By dimension:\n")
  ine_indicator_mappings %>%
    count(dimension) %>%
    print()

  cat("\nBy sub-dimension:\n")
  ine_indicator_mappings %>%
    count(dimension, sub_dimension) %>%
    print()

  cat("\nBy gaveta:\n")
  ine_indicator_mappings %>%
    count(gaveta) %>%
    print()

  cat("\nBy direction:\n")
  ine_indicator_mappings %>%
    count(direction) %>%
    print()

  # Count TODO/empty varcd
  todo_count <- sum(
    ine_indicator_mappings$ine_varcd == "TODO" |
    ine_indicator_mappings$ine_varcd == "" |
    is.na(ine_indicator_mappings$ine_varcd)
  )
  mapped_count <- nrow(ine_indicator_mappings) - todo_count

  cat("\nMapping status:\n")
  cat(glue("  ✓ Mapped: {mapped_count}\n"))
  cat(glue("  ⚠ TODO: {todo_count}\n"))
}

# Uncomment to see summary when sourcing this file
# print_mapping_summary()
