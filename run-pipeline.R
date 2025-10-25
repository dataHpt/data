#!/usr/bin/env Rscript
# run-pipeline.R
# Master script to run the complete DataH API generation pipeline
#
# Usage:
#   Rscript run-pipeline.R               # Run full pipeline
#   Rscript run-pipeline.R --skip-fetch   # Skip fetch (use existing cache)
#
# Pipeline stages:
#   1. Fetch data from INE/DGT APIs
#   2. Integrate auto-fetched + static CSV data
#   3. Normalize values to 0-100 scale
#   4. Generate JSON API files
#   5. Validate output

library(tidyverse)

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
skip_fetch <- "--skip-fetch" %in% args

# ASCII art header
cat("
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║                    DataH Static API Pipeline                         ║
║                                                                      ║
║                  Portuguese Municipality Housing                     ║
║                    Sustainability Indicators                         ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝

")

# Pipeline configuration
PIPELINE_STAGES <- list(
  list(
    name = "Data Integration (Auto + Static)",
    script = "scripts/02-integrate-all-data.R",
    skip = FALSE
  ),
  list(
    name = "Normalization (0-100 scale)",
    script = "scripts/03-normalize.R",
    skip = FALSE
  ),
  list(
    name = "JSON Generation",
    script = "scripts/04-generate-json.R",
    skip = FALSE
  ),
  list(
    name = "Validation",
    script = "scripts/05-validate.R",
    skip = FALSE
  )
)

# Track timing and results
start_time <- Sys.time()
results <- list()

# Helper function to run a script
run_stage <- function(stage_num, stage) {
  cat("\n")
  cat(strrep("=", 72), "\n")
  cat(sprintf("STAGE %d/%d: %s\n", stage_num, length(PIPELINE_STAGES), stage$name))
  cat(strrep("=", 72), "\n\n")

  if (stage$skip) {
    cat(stage$skip_message, "\n")
    return(list(status = "skipped", duration = 0))
  }

  stage_start <- Sys.time()

  tryCatch({
    cat(sprintf("Running: %s\n\n", stage$script))
    source(stage$script)

    stage_end <- Sys.time()
    duration <- as.numeric(difftime(stage_end, stage_start, units = "secs"))

    cat(sprintf("\n✓ Stage completed in %.1f seconds\n", duration))

    return(list(status = "success", duration = duration))

  }, error = function(e) {
    cat(sprintf("\n✗ ERROR: %s\n", e$message))
    cat("\nPipeline FAILED at this stage.\n")
    cat("Check the error message above for details.\n")

    return(list(status = "failed", duration = 0, error = e$message))
  })
}

# Run pipeline stages
for (i in seq_along(PIPELINE_STAGES)) {
  result <- run_stage(i, PIPELINE_STAGES[[i]])
  results[[i]] <- result

  # Stop on failure
  if (result$status == "failed") {
    quit(status = 1)
  }
}

# Final report
end_time <- Sys.time()
total_duration <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat("\n\n")
cat(strrep("=", 72), "\n")
cat("PIPELINE COMPLETE\n")
cat(strrep("=", 72), "\n\n")

# Summary table
success_count <- sum(sapply(results, function(r) r$status == "success"))
skipped_count <- sum(sapply(results, function(r) r$status == "skipped"))
total_stages <- length(PIPELINE_STAGES)

cat(sprintf("Stages completed: %d/%d\n", success_count, total_stages - skipped_count))
if (skipped_count > 0) {
  cat(sprintf("Stages skipped:   %d\n", skipped_count))
}

cat(sprintf("Total duration:   %.1f seconds (%.1f minutes)\n", total_duration, total_duration/60))

# Stage breakdown
cat("\nStage timings:\n")
for (i in seq_along(PIPELINE_STAGES)) {
  stage <- PIPELINE_STAGES[[i]]
  result <- results[[i]]

  if (result$status == "skipped") {
    status_icon <- "⊘"
    timing <- "skipped"
  } else if (result$status == "success") {
    status_icon <- "✓"
    timing <- sprintf("%.1fs", result$duration)
  } else {
    status_icon <- "✗"
    timing <- "FAILED"
  }

  cat(sprintf("  %s Stage %d: %-30s %s\n", status_icon, i, stage$name, timing))
}

cat("\n")
cat(strrep("-", 72), "\n")
cat("Next steps:\n")
cat("  1. Review generated files in data/v1/\n")
cat("  2. Check LAST_UPDATE.json for timestamp\n")
cat("  3. Commit and push to GitHub\n")
cat("  4. Enable GitHub Pages\n")
cat("  5. API will be live!\n")
cat(strrep("-", 72), "\n")

cat("\n✓ Pipeline completed successfully!\n\n")
