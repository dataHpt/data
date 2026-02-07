#!/usr/bin/env Rscript
# 02-integrate-all-data.R - Integrate auto-fetched and static baseline data
#
# Combines:
# - Auto-fetched data from INE/DGT APIs (~22 indicators)
# - Static baseline from Excel extraction (~27 indicators)
#
# Output: Complete dataset with all 49 indicators for 308 municipalities

library(tidyverse)
library(glue)

# Source mappings (not the full fetcher — that runs separately)
source("scripts/utils/ine-mappings.R")

message("=== DataH Indicator Integration ===\n")

STATIC_PATH <- "data-cache/static-indicators.csv"
API_DATA_PATH <- "data-cache/raw_indicators.rds"
OUTPUT_CSV <- "data-cache/all-indicators-raw.csv"
OUTPUT_RDS <- "data-cache/all-indicators-raw.rds"

EXPECTED_INDICATORS <- 49
EXPECTED_MUNICIPALITIES <- 308

# ============================================================================
# 1. Load static baseline (all 49 indicators from Excel)
# ============================================================================

message("Step 1: Loading static baseline data...")

if (!file.exists(STATIC_PATH)) {
  stop(glue("Static baseline not found: {STATIC_PATH}\nRun scripts/00-extract-excel-data.R first"))
}

static_data <- read_csv(
  STATIC_PATH,
  col_types = cols(
    dico = col_character(),
    indicator_id = col_character(),
    raw_value = col_double()
  ),
  show_col_types = FALSE
)

message(glue("  ✓ Loaded {nrow(static_data)} static rows"))
message(glue("    {n_distinct(static_data$indicator_id)} indicators × {n_distinct(static_data$dico)} municipalities\n"))

# ============================================================================
# 2. Load auto-fetched data (if available)
# ============================================================================

message("Step 2: Loading auto-fetched API data...")

api_data <- NULL

if (file.exists(API_DATA_PATH)) {
  api_raw <- readRDS(API_DATA_PATH)

  if (!is.null(api_raw) && nrow(api_raw) > 0) {
    api_data <- api_raw %>%
      select(dico, indicator_id, raw_value) %>%
      mutate(dico = as.character(dico))

    message(glue("  ✓ Loaded {nrow(api_data)} API rows"))
    message(glue("    {n_distinct(api_data$indicator_id)} indicators"))
  } else {
    message("  ⚠ API data file exists but is empty")
  }
} else {
  message("  ⚠ No API data found (data-cache/raw_indicators.rds)")
  message("    Using static baseline for all indicators")
}

# ============================================================================
# 3. Merge: API data takes priority over static baseline
# ============================================================================

message("\nStep 3: Merging data sources...")

if (!is.null(api_data) && nrow(api_data) > 0) {
  # For each indicator: use API data if available and valid, otherwise static
  api_indicators <- unique(api_data$indicator_id)

  # API data (tagged as "api")
  api_merged <- api_data %>%
    mutate(source = "api")

  # Static data for indicators NOT in API results
  static_remaining <- static_data %>%
    filter(!indicator_id %in% api_indicators) %>%
    mutate(source = "static")

  # For API indicators where some municipalities are missing, fill from static
  api_dicos <- api_data %>%
    group_by(indicator_id) %>%
    summarise(dicos = list(unique(dico)), .groups = "drop")

  static_fill <- static_data %>%
    filter(indicator_id %in% api_indicators) %>%
    anti_join(api_data, by = c("dico", "indicator_id")) %>%
    mutate(source = "static")

  if (nrow(static_fill) > 0) {
    message(glue("  Filling {nrow(static_fill)} gaps in API data from static baseline"))
  }

  all_data <- bind_rows(api_merged, static_remaining, static_fill)

  message(glue("  ✓ {length(api_indicators)} indicators from API"))
  message(glue("  ✓ {n_distinct(static_remaining$indicator_id)} indicators from static only"))
} else {
  # Use all static data
  all_data <- static_data %>%
    mutate(source = "static")
  message("  Using static baseline for all indicators")
}

# ============================================================================
# 4. Validation
# ============================================================================

message("\nStep 4: Validating combined data...")

total_indicators <- n_distinct(all_data$indicator_id)
total_municipalities <- n_distinct(all_data$dico)
total_rows <- nrow(all_data)

message(glue("  Total indicators: {total_indicators}"))
message(glue("  Total municipalities: {total_municipalities}"))
message(glue("  Total rows: {total_rows}"))

expected_rows <- EXPECTED_INDICATORS * EXPECTED_MUNICIPALITIES

if (total_indicators != EXPECTED_INDICATORS) {
  warning(glue("Expected {EXPECTED_INDICATORS} indicators, got {total_indicators}"))

  # Show which are missing
  expected_ids <- ine_indicator_mappings$indicator_id
  actual_ids <- unique(all_data$indicator_id)
  missing_ids <- setdiff(expected_ids, actual_ids)
  extra_ids <- setdiff(actual_ids, expected_ids)

  if (length(missing_ids) > 0) {
    message(glue("  Missing: {paste(missing_ids, collapse=', ')}"))
  }
  if (length(extra_ids) > 0) {
    message(glue("  Extra: {paste(extra_ids, collapse=', ')}"))
  }
}

if (total_rows < expected_rows) {
  warning(glue("Missing data! Expected {expected_rows} rows, got {total_rows}"))
} else {
  message("  ✓ All data present!")
}

# ============================================================================
# 5. Save combined data
# ============================================================================

message("\nStep 5: Saving combined data...")

dir.create("data-cache", showWarnings = FALSE, recursive = TRUE)

saveRDS(all_data, OUTPUT_RDS)
message(glue("  ✓ Saved to {OUTPUT_RDS}"))

write_csv(all_data, OUTPUT_CSV)
message(glue("  ✓ Saved to {OUTPUT_CSV}"))

# Summary by source
source_summary <- all_data %>%
  group_by(source) %>%
  summarise(
    indicators = n_distinct(indicator_id),
    municipalities = n_distinct(dico),
    rows = n(),
    .groups = "drop"
  )

message("\nData Summary by Source:")
print(source_summary)

message(glue("\n=== Integration Complete ==="))
message(glue("Total: {total_indicators} indicators × {total_municipalities} municipalities = {total_rows} rows"))
