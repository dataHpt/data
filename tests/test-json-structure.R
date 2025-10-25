#!/usr/bin/env Rscript
# test-json-structure.R - Tests for JSON structure validation

library(testthat)
library(jsonlite)

source("scripts/utils/json-schemas.R")

context("JSON Schema Generation")

test_that("Municipality JSON has correct structure", {
  # Mock data
  test_dimensions <- list(
    coesao_territorial = list(
      sub_dimensions = list(
        dinamicas_sociais = list(
          gavetas = list(
            desigualdade = list(
              indicators = list(
                beneficiarios_rsi = list(normalized = 6.97, raw = 15.0, unit = "%")
              )
            )
          )
        )
      )
    )
  )

  # Generate JSON
  json_output <- generate_municipality_json(
    dico = "1106",
    name = "Lisboa",
    dimensions_data = test_dimensions
  )

  # Parse back
  parsed <- fromJSON(json_output)

  # Tests
  expect_true("metadata" %in% names(parsed))
  expect_true("dimensions" %in% names(parsed))
  expect_equal(parsed$metadata$dico, "1106")
  expect_equal(parsed$metadata$name, "Lisboa")
  expect_true("last_updated" %in% names(parsed$metadata))
  expect_true("api_version" %in% names(parsed$metadata))
})

test_that("Index JSON has correct structure", {
  test_municipalities <- data.frame(
    dico = c("0101", "1106"),
    name = c("Águeda", "Lisboa"),
    stringsAsFactors = FALSE
  )

  json_output <- generate_index_json(test_municipalities)
  parsed <- fromJSON(json_output)

  expect_equal(parsed$total, 2)
  expect_true("municipalities" %in% names(parsed))
  expect_equal(length(parsed$municipalities), 2)
  expect_equal(parsed$municipalities[[1]]$dico, "0101")
})

test_that("Indicators metadata JSON has correct structure", {
  test_indicators <- data.frame(
    id = "beneficiarios_rsi",
    name = "Beneficiários do RSI",
    description = "Test description",
    dimension = "coesao_territorial",
    sub_dimension = "dinamicas_sociais",
    gaveta = "desigualdade",
    unit = "%",
    direction = "lower_is_better",
    source_name = "INE",
    source_year = 2023,
    source_table_code = "0010245",
    source_url = "https://www.ine.pt/test",
    stringsAsFactors = FALSE
  )

  json_output <- generate_indicators_metadata_json(test_indicators)
  parsed <- fromJSON(json_output)

  expect_true("version" %in% names(parsed))
  expect_true("indicators" %in% names(parsed))
  expect_equal(length(parsed$indicators), 1)
  expect_equal(parsed$indicators[[1]]$id, "beneficiarios_rsi")
  expect_equal(parsed$indicators[[1]]$normalization$method, "min-max")
})

test_that("Hierarchy JSON has correct structure", {
  json_output <- generate_hierarchy_json()
  parsed <- fromJSON(json_output)

  expect_true("hierarchy" %in% names(parsed))
  expect_true(length(parsed$hierarchy) >= 2) # At least 2 dimensions
  expect_true("id" %in% names(parsed$hierarchy[[1]]))
  expect_true("name" %in% names(parsed$hierarchy[[1]]))
  expect_true("sub_dimensions" %in% names(parsed$hierarchy[[1]]))
})

test_that("build_indicator creates correct structure", {
  indicator <- build_indicator(
    normalized = 67.45,
    raw = 15.3,
    unit = "%"
  )

  expect_equal(indicator$normalized, 67.45)
  expect_equal(indicator$raw, 15.3)
  expect_equal(indicator$unit, "%")
})

test_that("build_indicator validates range", {
  expect_warning(
    build_indicator(normalized = 150, raw = 100, unit = "%"),
    "out of range"
  )

  expect_warning(
    build_indicator(normalized = -10, raw = 5, unit = "%"),
    "out of range"
  )
})

test_that("validate_municipality_json detects invalid JSON", {
  invalid_json <- '{"metadata": {"dico": "1106"}}'

  expect_warning(
    result <- validate_municipality_json(invalid_json),
    "validation failed"
  )
  expect_false(result)
})

test_that("validate_municipality_json accepts valid JSON", {
  valid_dimensions <- list(
    coesao_territorial = list(
      sub_dimensions = list(
        dinamicas_sociais = list(
          gavetas = list(
            desigualdade = list(
              indicators = list(
                test_indicator = list(normalized = 50, raw = 10, unit = "%")
              )
            )
          )
        )
      )
    )
  )

  valid_json <- generate_municipality_json(
    dico = "1106",
    name = "Lisboa",
    dimensions_data = valid_dimensions
  )

  expect_true(validate_municipality_json(valid_json))
})
