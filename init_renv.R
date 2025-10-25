if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = "https://cloud.r-project.org")
}

renv::init(bare = TRUE, restart = FALSE)

# Install core packages for the project
packages <- c(
  "tidyverse",
  "jsonlite",
  "glue",
  "lubridate",
  "httr",
  "rvest",
  "testthat",
  "arrow",
  "memoise"
)

renv::install(packages)
renv::snapshot()
