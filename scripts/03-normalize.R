# 03-normalize.R
# Normalizes raw indicator values to 0-100 scale
#
# Input:  data-cache/all-indicators-raw.csv
# Output: data-cache/all-indicators-normalized.csv
#
# Normalization method: Min-Max scaling
# - higher_is_better: (value - min) / (max - min) * 100
# - lower_is_better:  (max - value) / (max - min) * 100 (inverted)

library(tidyverse)
library(glue)

# Load utilities
source("scripts/utils/ine-mappings.R")

# Configuration
RAW_DATA_PATH <- "data-cache/all-indicators-raw.csv"
OUTPUT_PATH <- "data-cache/all-indicators-normalized.csv"

message("=" %+% strrep("=", 70))
message("NORMALIZING INDICATOR VALUES")
message(strrep("=", 70) %+% "\n")

# ============================================================================
# 1. Load Raw Data
# ============================================================================

message("Loading raw data...")
raw_data <- read_csv(
  RAW_DATA_PATH,
  col_types = cols(
    dico = col_character(),
    indicator_id = col_character(),
    raw_value = col_double(),
    source = col_character()
  ),
  show_col_types = FALSE
)

message(glue("  ✓ Loaded {nrow(raw_data)} rows"))
message(glue("  ✓ {length(unique(raw_data$indicator_id))} indicators"))
message(glue("  ✓ {length(unique(raw_data$dico))} municipalities\n"))

# ============================================================================
# 2. Join with Indicator Metadata
# ============================================================================

message("Joining with indicator metadata...")

# Get direction info from mappings
indicator_metadata <- ine_indicator_mappings %>%
  select(indicator_id, direction, indicator_name, unit)

# Join
data_with_metadata <- raw_data %>%
  left_join(indicator_metadata, by = "indicator_id")

# Check for missing metadata
missing_metadata <- data_with_metadata %>%
  filter(is.na(direction)) %>%
  pull(indicator_id) %>%
  unique()

if (length(missing_metadata) > 0) {
  warning(glue("Missing metadata for {length(missing_metadata)} indicators: {paste(missing_metadata, collapse=', ')}"))
}

message(glue("  ✓ Joined metadata successfully\n"))

# ============================================================================
# 3. Normalize Values (Min-Max 0-100)
# ============================================================================

message("Normalizing values to 0-100 scale...")

normalized_data <- data_with_metadata %>%
  # Group by indicator to calculate min/max per indicator
  group_by(indicator_id) %>%
  mutate(
    min_val = min(raw_value, na.rm = TRUE),
    max_val = max(raw_value, na.rm = TRUE),
    range_val = max_val - min_val
  ) %>%
  ungroup() %>%
  # Apply normalization based on direction
  mutate(
    normalized_value = case_when(
      # If no range (all values are the same), set to 50
      range_val == 0 ~ 50,

      # higher_is_better: min → 0, max → 100
      direction == "higher_is_better" ~ ((raw_value - min_val) / range_val) * 100,

      # lower_is_better: max → 0, min → 100 (inverted)
      direction == "lower_is_better" ~ ((max_val - raw_value) / range_val) * 100,

      # Unknown direction: default to higher_is_better
      TRUE ~ ((raw_value - min_val) / range_val) * 100
    )
  ) %>%
  # Clean up temporary columns
  select(dico, indicator_id, raw_value, normalized_value, source)

message(glue("  ✓ Normalized {nrow(normalized_data)} values\n"))

# ============================================================================
# 4. Validation
# ============================================================================

message("Validating normalization...")

# Check that all normalized values are in 0-100 range
out_of_range <- normalized_data %>%
  filter(!is.na(normalized_value) & (normalized_value < 0 | normalized_value > 100))

if (nrow(out_of_range) > 0) {
  warning(glue("Found {nrow(out_of_range)} values outside 0-100 range!"))
  print(out_of_range %>% head(10))
} else {
  message("  ✓ All normalized values are within 0-100 range")
}

# Check for NAs
na_count <- sum(is.na(normalized_data$normalized_value))
if (na_count > 0) {
  message(glue("  ⚠ {na_count} NA values in normalized data (expected for missing raw values)"))
} else {
  message("  ✓ No NA values")
}

# Summary statistics
message("\nNormalization summary by direction:")
summary_stats <- data_with_metadata %>%
  filter(!is.na(direction)) %>%
  group_by(direction) %>%
  summarise(
    indicators = n_distinct(indicator_id),
    .groups = "drop"
  )
print(summary_stats)

message("")

# ============================================================================
# 5. Save Normalized Data
# ============================================================================

message(glue("Saving normalized data to {OUTPUT_PATH}..."))

write_csv(normalized_data, OUTPUT_PATH)

message(glue("  ✓ Saved {nrow(normalized_data)} rows\n"))

# ============================================================================
# 6. Final Report
# ============================================================================

message(strrep("=", 71))
message("NORMALIZATION COMPLETE")
message(strrep("=", 71))

# Calculate coverage
total_expected <- length(unique(normalized_data$indicator_id)) * length(unique(normalized_data$dico))
total_actual <- nrow(normalized_data %>% filter(!is.na(normalized_value)))
coverage_pct <- (total_actual / total_expected) * 100

message(glue("
Output: {OUTPUT_PATH}

Summary:
  • Total rows:        {nrow(normalized_data)}
  • Indicators:        {length(unique(normalized_data$indicator_id))}
  • Municipalities:    {length(unique(normalized_data$dico))}
  • Coverage:          {round(coverage_pct, 2)}% ({total_actual}/{total_expected})
  • Missing values:    {sum(is.na(normalized_data$normalized_value))}

Next step: Run scripts/04-generate-json.R to create API JSON files
"))

message(strrep("=", 71))
