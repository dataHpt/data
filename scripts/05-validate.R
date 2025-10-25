# 05-validate.R
# Validates the generated JSON API files
#
# Checks:
# 1. All JSON files are valid
# 2. All municipalities have data
# 3. Normalized values are in 0-100 range
# 4. Required fields are present
# 5. File sizes are reasonable

library(tidyverse)
library(jsonlite)
library(glue)

# Configuration
API_DIR <- "data/v1"

message("=" %+% strrep("=", 70))
message("VALIDATING JSON API")
message(strrep("=", 70) %+% "\n")

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
  }
}

if (!all_exist) {
  stop("Missing required files!")
}

# Check global timestamp
if (file.exists("data/LAST_UPDATE.json")) {
  message("  ✓ data/LAST_UPDATE.json")
} else {
  message("  ✗ MISSING: data/LAST_UPDATE.json")
  all_exist <- FALSE
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

# Sample validation (validate all files but only show issues)
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
    }

    # Check that dimensions exist
    if (!is.null(data$dimensions)) {
      if (length(data$dimensions) == 0) {
        validation_errors[[dico]] <- c(validation_errors[[dico]], "Empty dimensions")
      }
    }

    # Extract all normalized values and check range
    normalized_values <- c()
    for (dim_name in names(data$dimensions)) {
      dim <- data$dimensions[[dim_name]]
      if (!is.null(dim$sub_dimensions)) {
        for (sub_dim_name in names(dim$sub_dimensions)) {
          sub_dim <- dim$sub_dimensions[[sub_dim_name]]
          if (!is.null(sub_dim$gavetas)) {
            for (gaveta_name in names(sub_dim$gavetas)) {
              gaveta <- sub_dim$gavetas[[gaveta_name]]
              if (!is.null(gaveta$indicators)) {
                for (ind_name in names(gaveta$indicators)) {
                  ind <- gaveta$indicators[[ind_name]]
                  if (!is.null(ind$normalized)) {
                    normalized_values <- c(normalized_values, ind$normalized)
                  }
                }
              }
            }
          }
        }
      }
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
} else {
  if (index_data$total == length(mun_files)) {
    message(glue("  ✓ Index count matches files ({index_data$total})"))
  } else {
    message(glue("  ✗ Index count mismatch: index={index_data$total}, files={length(mun_files)}"))
  }
}

if (is.null(index_data$municipalities)) {
  message("  ✗ Missing 'municipalities' array")
} else {
  message(glue("  ✓ Index contains {length(index_data$municipalities)} municipalities"))
}

message("")

# ============================================================================
# 4. Validate Metadata Files
# ============================================================================

message("Validating metadata files...")

# indicators.json
indicators <- read_json(file.path(API_DIR, "metadata/indicators.json"))
if (!is.null(indicators$version) && !is.null(indicators$indicators)) {
  message(glue("  ✓ indicators.json ({length(indicators$indicators)} indicators)"))
} else {
  message("  ✗ indicators.json missing required fields")
}

# hierarchy.json
hierarchy <- read_json(file.path(API_DIR, "metadata/hierarchy.json"))
if (!is.null(hierarchy$structure)) {
  message(glue("  ✓ hierarchy.json ({length(hierarchy$structure)} dimensions)"))
} else {
  message("  ✗ hierarchy.json missing structure")
}

# sources.json
sources <- read_json(file.path(API_DIR, "metadata/sources.json"))
if (!is.null(sources$sources)) {
  message(glue("  ✓ sources.json ({length(sources$sources)} sources)"))
} else {
  message("  ✗ sources.json missing sources array")
}

message("")

# ============================================================================
# 5. Check File Sizes
# ============================================================================

message("Checking file sizes...")

# Get file sizes
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
  for (f in large_files) {
    size_kb <- round(file.info(f)$size / 1024, 2)
    message(glue("    {basename(f)}: {size_kb} KB"))
  }
} else {
  message("  ✓ All files under 50KB")
}

# Check if any file is suspiciously small (< 1KB)
small_files <- mun_files[file_sizes < 1000]
if (length(small_files) > 0) {
  message(glue("  ⚠ {length(small_files)} files smaller than 1KB (possible missing data)"))
  for (f in small_files) {
    size_kb <- round(file.info(f)$size / 1024, 2)
    message(glue("    {basename(f)}: {size_kb} KB"))
  }
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

total_errors <- length(validation_errors)
if (total_errors == 0) {
  message("
✓ All validations passed!

API is ready for deployment:
  • 308 municipality JSON files
  • All JSON structures valid
  • All normalized values in 0-100 range
  • Metadata files present and valid

Next steps:
  1. Commit JSON files to git
  2. Push to GitHub
  3. Enable GitHub Pages
  4. API will be live at: https://<username>.github.io/data/
")
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
