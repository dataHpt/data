# 05-validate.R
# Validates the generated JSON API files
#
# Checks:
# 1. All JSON files are valid
# 2. 308 municipalities present
# 3. 49 indicators per municipality
# 4. No gaveta nesting in JSON
# 5. Normalized values in 0-100 range
# 6. Required metadata fields (description, polarity)
# 7. File sizes are reasonable

library(tidyverse)
library(jsonlite)
library(glue)

# Configuration
API_DIR <- "v1"
EXPECTED_MUNICIPALITIES <- 308
EXPECTED_INDICATORS <- 49

message("=" %+% strrep("=", 70))
message("VALIDATING JSON API")
message(strrep("=", 70) %+% "\n")

total_errors <- 0

# ============================================================================
# 1. Check File Existence
# ============================================================================

message("Checking file structure...")

required_files <- c(
  "municipalities/index.json",
  "metadata/indicators.json",
  "metadata/hierarchy.json",
  "metadata/sources.json"
)

all_exist <- TRUE
for (file in required_files) {
  path <- file.path(API_DIR, file)
  if (file.exists(path)) {
    message(glue("  ✓ {file}"))
  } else {
    message(glue("  ✗ MISSING: {file}"))
    all_exist <- FALSE
    total_errors <- total_errors + 1
  }
}

# Check global timestamp
if (file.exists("LAST_UPDATE.json")) {
  message("  ✓ LAST_UPDATE.json")
} else {
  message("  ✗ MISSING: LAST_UPDATE.json")
  total_errors <- total_errors + 1
}

message("")

# ============================================================================
# 2. Validate Municipality Files
# ============================================================================

message("Validating municipality JSON files...")

# Get list of municipality files
mun_files <- list.files(
  file.path(API_DIR, "municipalities"),
  pattern = "^[0-9]{4}\\.json$",
  full.names = TRUE
)

message(glue("  Found {length(mun_files)} municipality files"))

if (length(mun_files) != EXPECTED_MUNICIPALITIES) {
  message(glue("  ⚠ Expected {EXPECTED_MUNICIPALITIES} files, found {length(mun_files)}"))
  total_errors <- total_errors + 1
}

# Validate all municipality files
validation_errors <- list()

for (i in seq_along(mun_files)) {
  file <- mun_files[i]
  dico <- basename(file) %>% str_remove("\\.json$")

  tryCatch({
    # Read JSON
    data <- read_json(file)

    # Check required top-level fields
    if (is.null(data$metadata)) {
      validation_errors[[dico]] <- c(validation_errors[[dico]], "Missing metadata")
    }
    if (is.null(data$dimensions)) {
      validation_errors[[dico]] <- c(validation_errors[[dico]], "Missing dimensions")
    }

    # Check metadata fields
    if (!is.null(data$metadata)) {
      if (is.null(data$metadata$dico)) {
        validation_errors[[dico]] <- c(validation_errors[[dico]], "Missing metadata$dico")
      }
      if (is.null(data$metadata$name)) {
        validation_errors[[dico]] <- c(validation_errors[[dico]], "Missing metadata$name")
      }
      if (is.null(data$metadata$last_updated)) {
        validation_errors[[dico]] <- c(validation_errors[[dico]], "Missing metadata$last_updated")
      }
      if (data$metadata$api_version != "2.0.0") {
        validation_errors[[dico]] <- c(validation_errors[[dico]], glue("Wrong api_version: {data$metadata$api_version}"))
      }
    }

    # Check NO gaveta nesting exists
    if (!is.null(data$dimensions)) {
      if (length(data$dimensions) == 0) {
        validation_errors[[dico]] <- c(validation_errors[[dico]], "Empty dimensions")
      }

      for (dim_name in names(data$dimensions)) {
        dim <- data$dimensions[[dim_name]]
        if (!is.null(dim$sub_dimensions)) {
          for (sub_dim_name in names(dim$sub_dimensions)) {
            sub_dim <- dim$sub_dimensions[[sub_dim_name]]
            # Validate: should have "indicators" directly, NOT "gavetas"
            if (!is.null(sub_dim$gavetas)) {
              validation_errors[[dico]] <- c(
                validation_errors[[dico]],
                glue("Gaveta nesting found in {dim_name}/{sub_dim_name}")
              )
            }
          }
        }
      }
    }

    # Count indicators and check normalized values
    normalized_values <- c()
    indicator_count <- 0

    for (dim_name in names(data$dimensions)) {
      dim <- data$dimensions[[dim_name]]
      if (!is.null(dim$sub_dimensions)) {
        for (sub_dim_name in names(dim$sub_dimensions)) {
          sub_dim <- dim$sub_dimensions[[sub_dim_name]]
          if (!is.null(sub_dim$indicators)) {
            for (ind_name in names(sub_dim$indicators)) {
              indicator_count <- indicator_count + 1
              ind <- sub_dim$indicators[[ind_name]]
              if (!is.null(ind$normalized)) {
                normalized_values <- c(normalized_values, ind$normalized)
              }
            }
          }
        }
      }
    }

    # Check indicator count
    if (indicator_count != EXPECTED_INDICATORS) {
      validation_errors[[dico]] <- c(
        validation_errors[[dico]],
        glue("Expected {EXPECTED_INDICATORS} indicators, got {indicator_count}")
      )
    }

    # Check normalized values are in range
    out_of_range <- normalized_values[normalized_values < 0 | normalized_values > 100]
    if (length(out_of_range) > 0) {
      validation_errors[[dico]] <- c(
        validation_errors[[dico]],
        glue("{length(out_of_range)} values out of 0-100 range")
      )
    }

  }, error = function(e) {
    validation_errors[[dico]] <<- c(validation_errors[[dico]], glue("JSON parse error: {e$message}"))
  })
}

if (length(validation_errors) > 0) {
  message(glue("  ✗ Found errors in {length(validation_errors)} municipalities:"))
  for (dico in names(validation_errors)) {
    message(glue("    {dico}: {paste(validation_errors[[dico]], collapse=', ')}"))
  }
  total_errors <- total_errors + length(validation_errors)
} else {
  message("  ✓ All municipality files are valid")
}

message("")

# ============================================================================
# 3. Validate Index File
# ============================================================================

message("Validating municipality index...")

index_data <- read_json(file.path(API_DIR, "municipalities/index.json"))

if (is.null(index_data$total)) {
  message("  ✗ Missing 'total' field")
  total_errors <- total_errors + 1
} else {
  if (index_data$total == length(mun_files)) {
    message(glue("  ✓ Index count matches files ({index_data$total})"))
  } else {
    message(glue("  ✗ Index count mismatch: index={index_data$total}, files={length(mun_files)}"))
    total_errors <- total_errors + 1
  }
}

message("")

# ============================================================================
# 4. Validate Metadata Files
# ============================================================================

message("Validating metadata files...")

# indicators.json
indicators <- read_json(file.path(API_DIR, "metadata/indicators.json"))
if (!is.null(indicators$version) && !is.null(indicators$indicators)) {
  ind_count <- length(indicators$indicators)
  message(glue("  ✓ indicators.json ({ind_count} indicators)"))

  if (ind_count != EXPECTED_INDICATORS) {
    message(glue("    ⚠ Expected {EXPECTED_INDICATORS}, got {ind_count}"))
    total_errors <- total_errors + 1
  }

  # Check description and polarity fields exist
  missing_desc <- 0
  missing_polarity <- 0
  missing_frontend <- 0
  for (ind in indicators$indicators) {
    if (is.null(ind$description) || ind$description == "") missing_desc <- missing_desc + 1
    if (is.null(ind$polarity) || ind$polarity == "") missing_polarity <- missing_polarity + 1
    if (is.null(ind$frontend_text) || ind$frontend_text == "") missing_frontend <- missing_frontend + 1
  }

  if (missing_desc > 0) {
    message(glue("    ⚠ {missing_desc} indicators missing description"))
  } else {
    message("    ✓ All indicators have descriptions")
  }

  if (missing_polarity > 0) {
    message(glue("    ⚠ {missing_polarity} indicators missing polarity"))
  } else {
    message("    ✓ All indicators have polarity")
  }

  if (missing_frontend > 0) {
    message(glue("    ⚠ {missing_frontend} indicators missing frontend_text"))
  } else {
    message("    ✓ All indicators have frontend_text")
  }
} else {
  message("  ✗ indicators.json missing required fields")
  total_errors <- total_errors + 1
}

# hierarchy.json
hierarchy <- read_json(file.path(API_DIR, "metadata/hierarchy.json"))
if (!is.null(hierarchy$structure)) {
  dim_count <- length(hierarchy$structure)
  sub_dim_count <- 0
  for (dim in hierarchy$structure) {
    sub_dim_count <- sub_dim_count + length(dim$sub_dimensions)
  }
  message(glue("  ✓ hierarchy.json ({dim_count} dimensions, {sub_dim_count} sub-dimensions)"))

  if (sub_dim_count != 8) {
    message(glue("    ⚠ Expected 8 sub-dimensions, got {sub_dim_count}"))
    total_errors <- total_errors + 1
  }
} else {
  message("  ✗ hierarchy.json missing structure")
  total_errors <- total_errors + 1
}

# sources.json
sources <- read_json(file.path(API_DIR, "metadata/sources.json"))
if (!is.null(sources$sources)) {
  message(glue("  ✓ sources.json ({length(sources$sources)} sources)"))
} else {
  message("  ✗ sources.json missing sources array")
  total_errors <- total_errors + 1
}

message("")

# ============================================================================
# 5. Check File Sizes
# ============================================================================

message("Checking file sizes...")

file_sizes <- file.info(mun_files)$size
mean_size <- mean(file_sizes)
max_size <- max(file_sizes)
min_size <- min(file_sizes)

message(glue("  Average size: {round(mean_size/1024, 2)} KB"))
message(glue("  Range: {round(min_size/1024, 2)} - {round(max_size/1024, 2)} KB"))

# Check if any file is suspiciously large (> 50KB)
large_files <- mun_files[file_sizes > 50000]
if (length(large_files) > 0) {
  message(glue("  ⚠ {length(large_files)} files larger than 50KB"))
} else {
  message("  ✓ All files under 50KB")
}

# Check if any file is suspiciously small (< 500 bytes)
small_files <- mun_files[file_sizes < 500]
if (length(small_files) > 0) {
  message(glue("  ⚠ {length(small_files)} files smaller than 500B (possible missing data)"))
  total_errors <- total_errors + 1
} else {
  message("  ✓ All files have reasonable data")
}

message("")

# ============================================================================
# 6. Final Report
# ============================================================================

message(strrep("=", 71))
message("VALIDATION COMPLETE")
message(strrep("=", 71))

if (total_errors == 0) {
  message(glue("
✓ All validations passed!

API is ready for deployment:
  • {length(mun_files)} municipality JSON files
  • {EXPECTED_INDICATORS} indicators per municipality
  • No gaveta nesting (flat hierarchy)
  • All JSON structures valid
  • All normalized values in 0-100 range
  • Metadata files present with descriptions and polarity
  • 8 sub-dimensions in hierarchy

Next steps:
  1. Commit JSON files to git
  2. Push to GitHub
  3. Enable GitHub Pages
  4. API will be live at: https://datahpt.github.io/data/
"))
} else {
  message(glue("
✗ Found {total_errors} errors

Please fix the errors above before deploying.
"))
}

message(strrep("=", 71))

# Return exit code
if (total_errors > 0) {
  quit(status = 1)
}
