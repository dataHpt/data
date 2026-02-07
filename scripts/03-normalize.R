# 03-normalize.R
# Normalizes raw indicator values to 0-100 scale
#
# Input:  data-cache/all-indicators-raw.csv
# Output: data-cache/all-indicators-normalized.csv
#         data-cache/normalization-comparison.csv (audit vs Excel)
#
# Normalization method: Min-Max scaling (matching Excel "Normalizado" sheet)
# - higher_is_better (Positiva): 100 - (value - min) / (max - min) * 100
# - lower_is_better (Negativa):  (value - min) / (max - min) * 100

library(tidyverse)
library(glue)

# Load utilities
source("scripts/utils/ine-mappings.R")

# Configuration
RAW_DATA_PATH <- "data-cache/all-indicators-raw.csv"
EXCEL_REF_PATH <- "data-cache/excel-normalized-reference.csv"
OUTPUT_PATH <- "data-cache/all-indicators-normalized.csv"
COMPARISON_PATH <- "data-cache/normalization-comparison.csv"

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

      # Positiva (higher_is_better): high raw = good = low problem score
      direction == "higher_is_better" ~ ((max_val - raw_value) / range_val) * 100,

      # Negativa (lower_is_better): high raw = bad = high problem score
      direction == "lower_is_better" ~ ((raw_value - min_val) / range_val) * 100,

      # Unknown direction: default to standard
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
# 5. Compare with Excel Normalized Reference
# ============================================================================

if (file.exists(EXCEL_REF_PATH)) {
  message("Comparing with Excel normalized reference...")

  excel_ref <- read_csv(
    EXCEL_REF_PATH,
    col_types = cols(
      dico = col_character(),
      indicator_id = col_character(),
      excel_normalized = col_double()
    ),
    show_col_types = FALSE
  )

  # Join our normalized values with Excel's
  comparison <- normalized_data %>%
    select(dico, indicator_id, our_normalized = normalized_value) %>%
    inner_join(
      excel_ref,
      by = c("dico", "indicator_id")
    ) %>%
    mutate(
      abs_diff = abs(our_normalized - excel_normalized)
    )

  # Save full comparison
  write_csv(comparison, COMPARISON_PATH)
  message(glue("  ✓ Saved comparison to {COMPARISON_PATH}"))

  # Summary by indicator
  comparison_summary <- comparison %>%
    group_by(indicator_id) %>%
    summarise(
      mean_diff = mean(abs_diff, na.rm = TRUE),
      max_diff = max(abs_diff, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(desc(mean_diff))

  # Flag indicators with large discrepancies
  discrepancies <- comparison_summary %>%
    filter(mean_diff > 5)

  if (nrow(discrepancies) > 0) {
    message(glue("  ⚠ {nrow(discrepancies)} indicators with mean difference > 5%:"))
    for (i in 1:min(10, nrow(discrepancies))) {
      row <- discrepancies[i, ]
      message(glue("    {row$indicator_id}: mean={round(row$mean_diff, 2)}, max={round(row$max_diff, 2)}"))
    }
  } else {
    message("  ✓ All indicators within 5% of Excel reference")
  }

  message("")
} else {
  message("  ⚠ No Excel reference file found, skipping comparison\n")
}

# ============================================================================
# 6. Save Normalized Data
# ============================================================================

message(glue("Saving normalized data to {OUTPUT_PATH}..."))

write_csv(normalized_data, OUTPUT_PATH)

message(glue("  ✓ Saved {nrow(normalized_data)} rows\n"))

# ============================================================================
# 7. Final Report
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
