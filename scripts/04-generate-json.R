# 04-generate-json.R
# Generates hierarchical JSON files for the DataH Static API
#
# Input:  data-cache/all-indicators-normalized.csv
# Output: v1/municipalities/*.json (308 files)
#         v1/metadata/*.json
#         v1/bulk/all-municipalities.json
#         v1/downloads/*.csv
#         LAST_UPDATE.json
#
# Structure: Dimension → Sub-dimension → Indicators (no gavetas)

library(tidyverse)
library(jsonlite)
library(glue)
library(lubridate)

# Load utilities
source("scripts/utils/ine-mappings.R")

# Configuration
NORMALIZED_DATA_PATH <- "data-cache/all-indicators-normalized.csv"
OUTPUT_DIR <- "v1"
API_VERSION <- "2.0.0"

message("=" %+% strrep("=", 70))
message("GENERATING JSON API FILES")
message(strrep("=", 70) %+% "\n")

# ============================================================================
# 1. Load Data
# ============================================================================

message("Loading normalized data...")
normalized_data <- read_csv(
  NORMALIZED_DATA_PATH,
  col_types = cols(
    dico = col_character(),
    indicator_id = col_character(),
    raw_value = col_double(),
    normalized_value = col_double(),
    source = col_character()
  ),
  show_col_types = FALSE
)

message(glue("  ✓ Loaded {nrow(normalized_data)} rows\n"))

# ============================================================================
# 2. Load Municipality Names
# ============================================================================

message("Loading municipality names...")

municipalities_path <- "data-cache/municipalities.csv"
if (file.exists(municipalities_path)) {
  municipality_names <- read_csv(
    municipalities_path,
    col_types = cols(dico = col_character(), name = col_character()),
    show_col_types = FALSE
  )
} else {
  # Fallback: try old static CSV
  static_path <- "scripts/utils/static-data-absolute.csv"
  if (file.exists(static_path)) {
    static_absolute <- read_csv2(
      static_path,
      locale = locale(decimal_mark = ",", grouping_mark = "."),
      show_col_types = FALSE
    )
    municipality_names <- static_absolute %>%
      select(DICO, Localizacao) %>%
      rename(dico = DICO, name = Localizacao) %>%
      mutate(dico = as.character(dico))
  } else {
    stop("No municipality names file found. Run 00-extract-excel-data.R first.")
  }
}

message(glue("  ✓ Loaded {nrow(municipality_names)} municipality names\n"))

# ============================================================================
# 3. Prepare Metadata
# ============================================================================

message("Preparing indicator metadata...")

# Join normalized data with metadata (no gaveta - new structure)
data_with_meta <- normalized_data %>%
  left_join(
    ine_indicator_mappings %>%
      select(indicator_id, indicator_name, dimension, sub_dimension, unit),
    by = "indicator_id"
  )

# Get current timestamp
last_updated <- format(now(tzone = "UTC"), "%Y-%m-%dT%H:%M:%SZ")

message(glue("  ✓ Metadata prepared\n"))

# ============================================================================
# 4. Build Hierarchical Structure for Each Municipality
# ============================================================================

message("Building hierarchical JSON structures...")

# Get unique municipalities
municipalities <- unique(normalized_data$dico) %>% sort()

message(glue("  Processing {length(municipalities)} municipalities...\n"))

# Create output directories
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(OUTPUT_DIR, "municipalities"), showWarnings = FALSE)
dir.create(file.path(OUTPUT_DIR, "metadata"), showWarnings = FALSE)

# Progress counter
processed <- 0

for (mun_dico in municipalities) {
  processed <- processed + 1

  if (processed %% 50 == 0) {
    message(glue("  [{processed}/{length(municipalities)}] Processing..."))
  }

  # Get municipality name
  mun_name <- municipality_names %>%
    filter(dico == mun_dico) %>%
    pull(name) %>%
    first()

  if (is.na(mun_name)) {
    mun_name <- paste("Municipality", mun_dico)
  }

  # Get all data for this municipality
  mun_data <- data_with_meta %>%
    filter(dico == mun_dico)

  # Build nested structure: Dimension → Sub-dimension → Indicators (flat, no gavetas)
  dimensions <- list()

  for (dim in unique(mun_data$dimension)) {
    if (is.na(dim)) next

    dim_data <- mun_data %>% filter(dimension == dim)
    sub_dimensions <- list()

    for (sub_dim in unique(dim_data$sub_dimension)) {
      if (is.na(sub_dim)) next

      sub_dim_data <- dim_data %>% filter(sub_dimension == sub_dim)
      indicators <- list()

      for (i in 1:nrow(sub_dim_data)) {
        row <- sub_dim_data[i, ]

        indicators[[row$indicator_id]] <- list(
          normalized = if (!is.na(row$normalized_value)) round(row$normalized_value, 2) else NULL,
          raw = if (!is.na(row$raw_value)) round(row$raw_value, 2) else NULL,
          unit = row$unit
        )
      }

      sub_dimensions[[sub_dim]] <- list(indicators = indicators)
    }

    dimensions[[dim]] <- list(sub_dimensions = sub_dimensions)
  }

  # Build final JSON structure
  mun_json <- list(
    metadata = list(
      dico = mun_dico,
      name = mun_name,
      last_updated = last_updated,
      api_version = API_VERSION
    ),
    dimensions = dimensions
  )

  # Write to file
  output_file <- file.path(OUTPUT_DIR, "municipalities", glue("{mun_dico}.json"))
  write_json(
    mun_json,
    output_file,
    pretty = TRUE,
    auto_unbox = TRUE,
    null = "null"
  )
}

message(glue("  ✓ Generated {length(municipalities)} municipality JSON files\n"))

# ============================================================================
# 4b. Inject LLM-generated Descriptions (if available)
# ============================================================================

desc_path <- "data-cache/municipality-descriptions.csv"
if (file.exists(desc_path)) {
  message("Injecting LLM-generated descriptions...")
  descriptions <- read_csv(desc_path, show_col_types = FALSE,
                           col_types = cols(.default = col_character()))
  injected <- 0
  for (i in 1:nrow(descriptions)) {
    row <- descriptions[i, ]
    mun_file <- file.path(OUTPUT_DIR, "municipalities", glue("{row$dico}.json"))
    if (file.exists(mun_file) && !is.na(row$description) && nchar(row$description) > 0) {
      mun_json <- read_json(mun_file)
      mun_json$metadata$description <- row$description
      write_json(mun_json, mun_file, pretty = TRUE, auto_unbox = TRUE, null = "null")
      injected <- injected + 1
    }
  }
  message(glue("  ✓ Injected descriptions into {injected} municipality JSONs\n"))
} else {
  message("No municipality descriptions found (run 06-generate-descriptions.R first)\n")
}

# ============================================================================
# 5. Generate Index File
# ============================================================================

message("Generating municipality index...")

index_data <- municipality_names %>%
  filter(dico %in% municipalities) %>%
  arrange(dico) %>%
  mutate(url = glue("/v1/municipalities/{dico}.json")) %>%
  select(dico, name, url)

index_json <- list(
  total = nrow(index_data),
  municipalities = index_data
)

write_json(
  index_json,
  file.path(OUTPUT_DIR, "municipalities", "index.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)

message(glue("  ✓ Generated index with {nrow(index_data)} municipalities\n"))

# ============================================================================
# 6. Generate Metadata Files
# ============================================================================

message("Generating metadata files...")

# indicators.json - Full indicator metadata with descriptions and polarity
indicators_metadata <- ine_indicator_mappings %>%
  rowwise() %>%
  mutate(
    normalization = list(list(
      method = "min-max",
      range = c(0, 100),
      inverted = direction == "higher_is_better"
    ))
  ) %>%
  ungroup() %>%
  select(
    indicator_id,
    indicator_number,
    indicator_name,
    description,
    frontend_name,
    frontend_text,
    polarity,
    direction,
    dimension,
    sub_dimension,
    unit,
    source,
    source_url,
    normalization
  )

indicators_json <- list(
  version = API_VERSION,
  last_updated = last_updated,
  indicators = indicators_metadata
)

write_json(
  indicators_json,
  file.path(OUTPUT_DIR, "metadata", "indicators.json"),
  pretty = TRUE,
  auto_unbox = FALSE  # Keep arrays as arrays
)

message("  ✓ Generated indicators.json")

# hierarchy.json - New structure with 8 sub-dimensions, no gavetas
dimension_labels <- list(
  territorio_populacao_habitacao = "Território, População e Habitação",
  ambiente_energia_riscos = "Ambiente, Energia e Riscos"
)

sub_dimension_labels <- list(
  socio_demograficas = "Sócio-demográficas",
  socio_economicas = "Sócio-económicas",
  socio_territoriais = "Sócio-territoriais",
  acesso_habitacao = "Acesso à Habitação",
  parque_habitacional = "Parque Habitacional",
  habitacao_energia = "Habitação e Energia",
  habitat = "Habitat",
  riscos_naturais = "Riscos Naturais"
)

hierarchy_structure <- list()

for (dim_id in unique(ine_indicator_mappings$dimension)) {
  dim_indicators <- ine_indicator_mappings %>% filter(dimension == dim_id)
  sub_dims <- list()

  for (sd_id in unique(dim_indicators$sub_dimension)) {
    sd_indicators <- dim_indicators %>% filter(sub_dimension == sd_id)
    sub_dims[[sd_id]] <- list(
      name = sub_dimension_labels[[sd_id]] %||% sd_id,
      indicators = sd_indicators$indicator_id
    )
  }

  hierarchy_structure[[dim_id]] <- list(
    name = dimension_labels[[dim_id]] %||% dim_id,
    sub_dimensions = sub_dims
  )
}

hierarchy_json <- list(
  version = API_VERSION,
  last_updated = last_updated,
  structure = hierarchy_structure
)

write_json(
  hierarchy_json,
  file.path(OUTPUT_DIR, "metadata", "hierarchy.json"),
  pretty = TRUE,
  auto_unbox = FALSE
)

message("  ✓ Generated hierarchy.json")

# sources.json - Data sources
source_counts <- ine_indicator_mappings %>%
  count(source) %>%
  filter(!is.na(source))

sources_list <- list()
sources_list[[1]] <- list(
  name = "INE",
  full_name = "Instituto Nacional de Estatística",
  url = "https://www.ine.pt",
  indicators_count = sum(ine_indicator_mappings$source == "INE", na.rm = TRUE)
)
sources_list[[2]] <- list(
  name = "DGT",
  full_name = "Direção-Geral do Território",
  url = "https://observatorioindicadores.dgterritorio.gov.pt",
  indicators_count = sum(ine_indicator_mappings$source == "DGT", na.rm = TRUE)
)
sources_list[[3]] <- list(
  name = "ANPC",
  full_name = "Autoridade Nacional de Proteção Civil",
  url = "https://prociv.gov.pt",
  indicators_count = sum(ine_indicator_mappings$source == "ANPC", na.rm = TRUE)
)

sources_json <- list(
  version = API_VERSION,
  last_updated = last_updated,
  sources = sources_list
)

write_json(
  sources_json,
  file.path(OUTPUT_DIR, "metadata", "sources.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)

message("  ✓ Generated sources.json\n")

# ============================================================================
# 7. Generate Global Timestamp
# ============================================================================

message("Generating global update timestamp...")

timestamp_json <- list(
  last_updated = last_updated,
  api_version = API_VERSION,
  municipalities_count = length(municipalities),
  indicators_count = n_distinct(normalized_data$indicator_id)
)

write_json(
  timestamp_json,
  "LAST_UPDATE.json",
  pretty = TRUE,
  auto_unbox = TRUE
)

message("  ✓ Generated LAST_UPDATE.json\n")

# ============================================================================
# 8. Generate Bulk Endpoint (All Municipalities in One File)
# ============================================================================

message("Generating bulk endpoint (all municipalities)...")

# Create bulk directory
dir.create(file.path(OUTPUT_DIR, "bulk"), showWarnings = FALSE)

# Collect all municipality data
all_municipalities_data <- list()

for (mun_dico in municipalities) {
  mun_file <- file.path(OUTPUT_DIR, "municipalities", glue("{mun_dico}.json"))
  mun_data <- read_json(mun_file)
  all_municipalities_data[[mun_dico]] <- mun_data
}

# Create bulk JSON structure
bulk_json <- list(
  metadata = list(
    last_updated = last_updated,
    api_version = API_VERSION,
    total_municipalities = length(municipalities),
    total_indicators = n_distinct(normalized_data$indicator_id)
  ),
  municipalities = all_municipalities_data
)

# Write bulk file
write_json(
  bulk_json,
  file.path(OUTPUT_DIR, "bulk", "all-municipalities.json"),
  pretty = TRUE,
  auto_unbox = TRUE,
  null = "null"
)

bulk_size_mb <- file.info(file.path(OUTPUT_DIR, "bulk", "all-municipalities.json"))$size / 1024 / 1024
message(glue("  ✓ Generated all-municipalities.json ({round(bulk_size_mb, 2)} MB)\n"))

# ============================================================================
# 9. Generate CSV Downloads
# ============================================================================

message("Generating CSV download files...")

# Create downloads directory
dir.create(file.path(OUTPUT_DIR, "downloads"), showWarnings = FALSE)

# 1. Raw data CSV (with municipality names)
raw_data_download <- normalized_data %>%
  left_join(municipality_names, by = "dico") %>%
  select(
    municipality_code = dico,
    municipality_name = name,
    indicator_id,
    raw_value,
    source
  ) %>%
  arrange(municipality_code, indicator_id)

write_csv(
  raw_data_download,
  file.path(OUTPUT_DIR, "downloads", "raw-data.csv")
)

message(glue("  ✓ Generated raw-data.csv ({nrow(raw_data_download)} rows)"))

# 2. Normalized data CSV
normalized_data_download <- normalized_data %>%
  left_join(municipality_names, by = "dico") %>%
  select(
    municipality_code = dico,
    municipality_name = name,
    indicator_id,
    normalized_value,
    raw_value,
    source
  ) %>%
  arrange(municipality_code, indicator_id)

write_csv(
  normalized_data_download,
  file.path(OUTPUT_DIR, "downloads", "normalized-data.csv")
)

message(glue("  ✓ Generated normalized-data.csv ({nrow(normalized_data_download)} rows)"))

# 3. Wide format (one row per municipality, columns for indicators)
wide_normalized <- normalized_data %>%
  select(dico, indicator_id, normalized_value) %>%
  pivot_wider(
    names_from = indicator_id,
    values_from = normalized_value
  ) %>%
  left_join(municipality_names, by = "dico") %>%
  select(municipality_code = dico, municipality_name = name, everything())

write_csv(
  wide_normalized,
  file.path(OUTPUT_DIR, "downloads", "normalized-data-wide.csv")
)

message(glue("  ✓ Generated normalized-data-wide.csv (308 municipalities × {ncol(wide_normalized)-2} indicators)"))

# 4. Wide format for raw data
wide_raw <- normalized_data %>%
  select(dico, indicator_id, raw_value) %>%
  pivot_wider(
    names_from = indicator_id,
    values_from = raw_value
  ) %>%
  left_join(municipality_names, by = "dico") %>%
  select(municipality_code = dico, municipality_name = name, everything())

write_csv(
  wide_raw,
  file.path(OUTPUT_DIR, "downloads", "raw-data-wide.csv")
)

message(glue("  ✓ Generated raw-data-wide.csv (308 municipalities × {ncol(wide_raw)-2} indicators)\n"))

# ============================================================================
# 10. Final Report
# ============================================================================

# Count files generated
json_files <- list.files(file.path(OUTPUT_DIR, "municipalities"), pattern = "\\.json$")
metadata_files <- list.files(file.path(OUTPUT_DIR, "metadata"), pattern = "\\.json$")
bulk_files <- list.files(file.path(OUTPUT_DIR, "bulk"), pattern = "\\.json$")
download_files <- list.files(file.path(OUTPUT_DIR, "downloads"), pattern = "\\.csv$")

message(strrep("=", 71))
message("JSON GENERATION COMPLETE")
message(strrep("=", 71))

message(glue("
Output directory: {OUTPUT_DIR}/

Files generated:
  • Municipality JSONs:  {length(json_files) - 1} files (+ 1 index)
  • Metadata files:      {length(metadata_files)} files
  • Bulk endpoint:       {length(bulk_files)} file ({round(bulk_size_mb, 2)} MB)
  • CSV downloads:       {length(download_files)} files
  • Global timestamp:    LAST_UPDATE.json

API structure:
  • /v1/municipalities/{{dico}}.json     - Individual municipality data
  • /v1/municipalities/index.json        - List of all municipalities
  • /v1/metadata/indicators.json         - Indicator metadata (with descriptions, polarity)
  • /v1/metadata/hierarchy.json          - Dimension structure (8 sub-dimensions)
  • /v1/metadata/sources.json            - Data sources
  • /v1/bulk/all-municipalities.json     - All municipalities in one file
  • /v1/downloads/raw-data.csv           - Raw values (long format)
  • /v1/downloads/normalized-data.csv    - Normalized values (long format)
  • /v1/downloads/raw-data-wide.csv      - Raw values (wide format)
  • /v1/downloads/normalized-data-wide.csv - Normalized values (wide format)
  • /LAST_UPDATE.json                    - Global update timestamp

Next step: Validate API with scripts/05-validate.R
"))

message(strrep("=", 71))
