#!/usr/bin/env Rscript
# test-data-integrity.R - Tests for data normalization and integrity

library(testthat)
library(tibble)

source("scripts/02-normalize.R")

context("Data Normalization")

test_that("normalize_min_max works for higher_is_better", {
  values <- c(10, 50, 90)

  normalized <- normalize_min_max(values, direction = "higher_is_better")

  expect_equal(normalized[1], 0)    # Min value = 0
  expect_equal(normalized[3], 100)  # Max value = 100
  expect_equal(normalized[2], 50)   # Middle value = 50
})

test_that("normalize_min_max works for lower_is_better", {
  values <- c(10, 50, 90)

  normalized <- normalize_min_max(values, direction = "lower_is_better")

  expect_equal(normalized[1], 100)  # Min value = 100 (inverted)
  expect_equal(normalized[3], 0)    # Max value = 0 (inverted)
  expect_equal(normalized[2], 50)   # Middle value = 50
})

test_that("normalize_min_max handles NA values", {
  values <- c(10, NA, 50, NA, 90)

  normalized <- normalize_min_max(values, direction = "higher_is_better")

  expect_equal(normalized[1], 0)
  expect_equal(normalized[5], 100)
  expect_true(is.na(normalized[2]))
  expect_true(is.na(normalized[4]))
})

test_that("normalize_min_max handles all NA values", {
  values <- c(NA, NA, NA)

  expect_warning(
    normalized <- normalize_min_max(values),
    "All values are NA"
  )

  expect_true(all(is.na(normalized)))
})

test_that("normalize_min_max handles identical values", {
  values <- c(50, 50, 50, 50)

  expect_warning(
    normalized <- normalize_min_max(values),
    "Min equals max"
  )

  expect_true(all(normalized == 50))
})

test_that("normalize_min_max respects custom min/max", {
  values <- c(20, 50, 80)

  normalized <- normalize_min_max(
    values,
    direction = "higher_is_better",
    custom_min = 0,
    custom_max = 100
  )

  expect_equal(normalized[1], 20)  # (20-0)/(100-0) * 100
  expect_equal(normalized[2], 50)
  expect_equal(normalized[3], 80)
})

test_that("normalize_min_max keeps values in [0, 100]", {
  values <- runif(100, min = -1000, max = 1000)

  normalized <- normalize_min_max(values)

  expect_true(all(normalized >= 0))
  expect_true(all(normalized <= 100))
})

test_that("normalize_all_indicators works end-to-end", {
  # Mock mappings
  test_mappings <- tribble(
    ~indicator_id,         ~direction,          ~unit,
    "beneficiarios_rsi",   "lower_is_better",   "%",
    "rendimento_mediano",  "higher_is_better",  "€"
  )

  # Mock data
  test_data <- tribble(
    ~dico,  ~indicator_id,         ~raw_value,
    "1106", "beneficiarios_rsi",   15.0,
    "0101", "beneficiarios_rsi",   8.5,
    "1311", "beneficiarios_rsi",   22.3,
    "1106", "rendimento_mediano",  1200,
    "0101", "rendimento_mediano",  950,
    "1311", "rendimento_mediano",  1100
  )

  result <- normalize_all_indicators(test_data, mappings = test_mappings)

  # Check structure
  expect_true("normalized_value" %in% names(result))
  expect_equal(nrow(result), 6)

  # Check ranges
  expect_true(all(result$normalized_value >= 0))
  expect_true(all(result$normalized_value <= 100))

  # Check direction: beneficiarios_rsi (lower is better)
  # Min raw = 8.5 → should be 100
  rsi_data <- result %>% filter(indicator_id == "beneficiarios_rsi")
  min_raw_row <- rsi_data %>% filter(raw_value == min(raw_value))
  expect_equal(min_raw_row$normalized_value, 100)

  # Check direction: rendimento_mediano (higher is better)
  # Max raw = 1200 → should be 100
  rend_data <- result %>% filter(indicator_id == "rendimento_mediano")
  max_raw_row <- rend_data %>% filter(raw_value == max(raw_value))
  expect_equal(max_raw_row$normalized_value, 100)
})

test_that("validate_normalized_data detects out-of-range values", {
  # Invalid data (normalized > 100)
  invalid_data <- tribble(
    ~dico,  ~indicator_id,  ~raw_value, ~normalized_value, ~unit,
    "1106", "test_ind",     10,         150,               "%"
  )

  expect_warning(
    result <- validate_normalized_data(invalid_data),
    "out of .* range"
  )
  expect_false(result$range_valid)
})

test_that("validate_normalized_data accepts valid data", {
  valid_data <- tribble(
    ~dico,  ~indicator_id,  ~raw_value, ~normalized_value, ~unit,
    "1106", "test_ind",     10,         50,                "%",
    "0101", "test_ind",     20,         75,                "%"
  )

  # Should not produce warnings
  expect_silent(
    result <- validate_normalized_data(valid_data)
  )
})
