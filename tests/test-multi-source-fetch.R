#!/usr/bin/env Rscript
# test-multi-source-fetch.R - Test multi-source data fetching (INE + DGT)
#
# Phase 1 Testing: Verify INE and DGT fetching works before adding static CSV data

library(tidyverse)

# Source the multi-source fetch script
message("Loading multi-source fetch script...")
source("scripts/01-fetch-data.R")

# Test 1: Fetch single INE indicator ----
message("\n" %+% strrep("=", 60))
message("TEST 1: Fetch INE Indicator (beneficiarios_rsi)")
message(strrep("=", 60))

tryCatch({
  ine_test <- fetch_indicator("beneficiarios_rsi")

  if (!is.null(ine_test)) {
    message("\n✓ INE fetch successful!")
    message(glue("  Rows: {nrow(ine_test)}"))
    message(glue("  Columns: {paste(names(ine_test), collapse=', ')}"))
    message("\nSample data:")
    print(head(ine_test, 5))

    # Validation
    if (nrow(ine_test) < 100) {
      warning(glue("⚠ Only {nrow(ine_test)} municipalities (expected ~308)"))
    }
  } else {
    stop("❌ INE fetch returned NULL")
  }
}, error = function(e) {
  message("\n❌ INE fetch failed!")
  message(glue("Error: {e$message}"))
})

# Test 2: Fetch single DGT indicator ----
message("\n" %+% strrep("=", 60))
message("TEST 2: Fetch DGT Indicator (edificios_fora_perimetro_urbano)")
message(strrep("=", 60))

tryCatch({
  dgt_test <- fetch_indicator("edificios_fora_perimetro_urbano")

  if (!is.null(dgt_test)) {
    message("\n✓ DGT fetch successful!")
    message(glue("  Rows: {nrow(dgt_test)}"))
    message(glue("  Columns: {paste(names(dgt_test), collapse=', ')}"))
    message("\nSample data:")
    print(head(dgt_test, 5))

    # Validation
    if (nrow(dgt_test) < 100) {
      warning(glue("⚠ Only {nrow(dgt_test)} municipalities (expected ~308)"))
    }
  } else {
    stop("❌ DGT fetch returned NULL")
  }
}, error = function(e) {
  message("\n❌ DGT fetch failed!")
  message(glue("Error: {e$message}"))
})

# Test 3: Fetch all mapped indicators (batch) ----
message("\n" %+% strrep("=", 60))
message("TEST 3: Fetch All Mapped Indicators (Batch)")
message(strrep("=", 60))

tryCatch({
  all_data <- fetch_all_indicators(use_cache = TRUE)

  if (!is.null(all_data) && nrow(all_data) > 0) {
    message("\n✓ Batch fetch successful!")
    message(glue("  Total indicators: {n_distinct(all_data$indicator_id)}"))
    message(glue("  Total municipalities: {n_distinct(all_data$dico)}"))
    message(glue("  Total data points: {nrow(all_data)}"))

    # Source breakdown
    source_counts <- ine_indicator_mappings %>%
      filter(indicator_id %in% unique(all_data$indicator_id)) %>%
      count(source)

    message("\nSource breakdown:")
    print(source_counts)

    message("\nSample data:")
    print(head(all_data, 10))

    # Validation
    validate_fetched_data(all_data)
  } else {
    stop("❌ Batch fetch returned NULL or empty data")
  }
}, error = function(e) {
  message("\n❌ Batch fetch failed!")
  message(glue("Error: {e$message}"))
})

# Summary ----
message("\n" %+% strrep("=", 60))
message("TEST SUMMARY")
message(strrep("=", 60))
message("\nPhase 1 testing complete!")
message("Next steps:")
message("  1. Review any errors or warnings above")
message("  2. If tests pass, proceed to Phase 2 (static CSV integration)")
message("  3. If tests fail, debug INE/DGT API issues")
