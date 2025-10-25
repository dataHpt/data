#!/usr/bin/env Rscript
# 02-integrate-all-data.R - Integrate auto-fetched and static CSV data
#
# Combines:
# - Auto-fetched data from INE/DGT APIs (22 indicators)
# - Static CSV data (23 indicators including valor_med_m2)
#
# Output: Complete dataset with all 45 indicators for 308 municipalities

library(tidyverse)
library(glue)

# Source fetcher
source("scripts/01-fetch-data.R")

message("=== DataH Indicator Integration ===\n")

# Step 1: Fetch all auto-fetched indicators ----
message("Step 1: Fetching automatically-fetched indicators...")

auto_indicators <- ine_indicator_mappings %>%
  filter(!is.na(code), code != "", code != "TODO") %>%
  pull(indicator_id)

message(glue("Found {length(auto_indicators)} indicators to auto-fetch"))

auto_data_list <- list()
for (ind in auto_indicators) {
  message(glue("  Fetching {ind}..."))

  data <- tryCatch({
    fetch_indicator(ind)
  }, error = function(e) {
    warning(glue("Failed to fetch {ind}: {e$message}"))
    NULL
  })

  if (!is.null(data)) {
    auto_data_list[[ind]] <- data
  }
}

# Combine all auto-fetched data
auto_data <- bind_rows(auto_data_list)
message(glue("✓ Auto-fetched {length(auto_data_list)} indicators"))

# Step 2: Load static CSV data ----
message("\nStep 2: Loading static CSV data...")

static_absolute <- read_csv2(
  "scripts/utils/static-data-absolute.csv",
  locale = locale(decimal_mark = ",", grouping_mark = "."),
  show_col_types = FALSE
)

static_scaled <- read_csv2(
  "scripts/utils/static-data-scaled.csv",
  locale = locale(decimal_mark = ",", grouping_mark = "."),
  show_col_types = FALSE
)

# Get static indicator columns (exclude DICO and Localizacao)
static_indicators <- setdiff(names(static_absolute), c("DICO", "Localizacao"))
message(glue("Found {length(static_indicators)} static indicators"))

# Transform static data to long format
static_data <- static_absolute %>%
  select(DICO, all_of(static_indicators)) %>%
  pivot_longer(
    cols = all_of(static_indicators),
    names_to = "indicator_id",
    values_to = "raw_value"
  ) %>%
  rename(dico = DICO) %>%
  mutate(dico = as.character(dico))

message(glue("✓ Loaded {length(static_indicators)} static indicators"))

# Step 3: Combine auto-fetched and static data ----
message("\nStep 3: Combining all data sources...")

# Ensure consistent structure
auto_data <- auto_data %>%
  select(dico, indicator_id, raw_value) %>%
  mutate(
    dico = as.character(dico),
    source = "auto"
  )

static_data <- static_data %>%
  mutate(source = "static")

# Combine
all_data <- bind_rows(auto_data, static_data)

# Step 4: Validation ----
message("\nStep 4: Validating combined data...")

# Check counts
total_indicators <- n_distinct(all_data$indicator_id)
total_municipalities <- n_distinct(all_data$dico)
total_rows <- nrow(all_data)

message(glue("  Total indicators: {total_indicators}"))
message(glue("  Total municipalities: {total_municipalities}"))
message(glue("  Total rows: {total_rows}"))

# Expected: 45 indicators × 308 municipalities = 13,860 rows
expected_rows <- 45 * 308

if (total_rows < expected_rows) {
  warning(glue("Missing data! Expected {expected_rows} rows, got {total_rows}"))

  # Identify missing combinations
  missing <- expand_grid(
    dico = unique(all_data$dico),
    indicator_id = unique(all_data$indicator_id)
  ) %>%
    anti_join(all_data, by = c("dico", "indicator_id"))

  if (nrow(missing) > 0) {
    message("\nMissing indicator-municipality combinations:")
    missing_summary <- missing %>%
      count(indicator_id, sort = TRUE)
    print(missing_summary)
  }
} else {
  message("✓ All data present!")
}

# Step 5: Save combined data ----
message("\nStep 5: Saving combined data...")

# Create output directory if needed
if (!dir.exists("data-cache")) {
  dir.create("data-cache", recursive = TRUE)
}

# Save as RDS (for R processing)
saveRDS(all_data, "data-cache/all-indicators-raw.rds")
message("✓ Saved to data-cache/all-indicators-raw.rds")

# Save as CSV (for inspection)
write_csv(all_data, "data-cache/all-indicators-raw.csv")
message("✓ Saved to data-cache/all-indicators-raw.csv")

# Summary by source
source_summary <- all_data %>%
  group_by(source) %>%
  summarise(
    indicators = n_distinct(indicator_id),
    municipalities = n_distinct(dico),
    rows = n()
  )

message("\nData Summary by Source:")
print(source_summary)

message("\n=== Integration Complete ===")
message(glue("Total: {total_indicators} indicators × {total_municipalities} municipalities = {total_rows} rows"))
