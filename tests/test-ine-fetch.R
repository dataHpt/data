#!/usr/bin/env Rscript
# test-ine-fetch.R - Tests for INE data fetching (with mocks)

library(testthat)
library(tibble)

source("scripts/utils/ine-mappings.R")

context("INE Mappings")

test_that("ine_indicator_mappings has required columns", {
  required_cols <- c(
    "indicator_id", "indicator_name", "dimension", "sub_dimension",
    "gaveta", "ine_table", "ine_variable", "unit", "direction", "year"
  )

  expect_true(all(required_cols %in% names(ine_indicator_mappings)))
})

test_that("ine_indicator_mappings has no duplicate IDs", {
  duplicates <- ine_indicator_mappings %>%
    count(indicator_id) %>%
    filter(n > 1)

  expect_equal(nrow(duplicates), 0)
})

test_that("all directions are valid", {
  valid_directions <- c("lower_is_better", "higher_is_better")

  invalid <- ine_indicator_mappings %>%
    filter(!direction %in% valid_directions)

  expect_equal(nrow(invalid), 0)
})

test_that("get_indicator_mapping returns correct data", {
  # Assuming "beneficiarios_rsi" exists in mappings
  mapping <- get_indicator_mapping("beneficiarios_rsi")

  expect_true(is.list(mapping))
  expect_equal(mapping$indicator_id, "beneficiarios_rsi")
  expect_true("ine_table" %in% names(mapping))
  expect_true("direction" %in% names(mapping))
})

test_that("get_indicator_mapping fails for non-existent indicator", {
  expect_error(
    get_indicator_mapping("nonexistent_indicator"),
    "No mapping found"
  )
})

test_that("get_dimension_indicators filters correctly", {
  coesao_indicators <- get_dimension_indicators("coesao_territorial")

  expect_true(nrow(coesao_indicators) > 0)
  expect_true(all(coesao_indicators$dimension == "coesao_territorial"))
})

test_that("get_gaveta_indicators filters correctly", {
  desig_indicators <- get_gaveta_indicators("desigualdade")

  expect_true(nrow(desig_indicators) > 0)
  expect_true(all(desig_indicators$gaveta == "desigualdade"))
})

context("Mock Data Generation")

test_that("generate_mock_municipality_data returns correct structure", {
  # Source the fetch script to access mock functions
  source("scripts/01-fetch-data.R", local = TRUE)

  mock_data <- generate_mock_municipality_data()

  expect_true("dico" %in% names(mock_data))
  expect_true("value" %in% names(mock_data))
  expect_true(nrow(mock_data) > 0)
  expect_true(all(!is.na(mock_data$value)))
})

test_that("generate_mock_municipalities returns correct structure", {
  source("scripts/01-fetch-data.R", local = TRUE)

  mock_municipalities <- generate_mock_municipalities()

  expect_true("dico" %in% names(mock_municipalities))
  expect_true("name" %in% names(mock_municipalities))
  expect_true(nrow(mock_municipalities) > 0)
  expect_equal(mock_municipalities$dico[1], "0101")
  expect_equal(mock_municipalities$name[1], "Águeda")
})

context("Data Validation")

test_that("validate_fetched_data accepts valid data", {
  source("scripts/01-fetch-data.R", local = TRUE)

  valid_data <- tribble(
    ~dico,  ~indicator_id,         ~raw_value,
    "1106", "beneficiarios_rsi",   15.0,
    "0101", "beneficiarios_rsi",   8.5,
    "1106", "rendimento_mediano",  1200
  )

  expect_true(validate_fetched_data(valid_data))
})

test_that("validate_fetched_data detects missing columns", {
  source("scripts/01-fetch-data.R", local = TRUE)

  invalid_data <- tribble(
    ~dico,  ~raw_value,
    "1106", 15.0
  )

  expect_warning(
    result <- validate_fetched_data(invalid_data),
    "Validation failed"
  )
})

test_that("validate_fetched_data warns about high NA percentage", {
  source("scripts/01-fetch-data.R", local = TRUE)

  data_with_nas <- tribble(
    ~dico,  ~indicator_id,  ~raw_value,
    "1106", "test",         15.0,
    "0101", "test",         NA,
    "1311", "test",         NA,
    "0102", "test",         NA,
    "0103", "test",         NA
  )

  expect_warning(
    validate_fetched_data(data_with_nas),
    "NA values"
  )
})
