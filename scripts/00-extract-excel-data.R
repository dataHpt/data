#!/usr/bin/env Rscript
# 00-extract-excel-data.R - Extract baseline data from Excel reference file
#
# Reads the DataH reference Excel and produces:
# 1. data-cache/static-indicators.csv  — raw values for all 49 indicators
# 2. data-cache/excel-normalized-reference.csv — Excel's normalized values for comparison
# 3. data-cache/municipalities.csv — municipality names and codes
#
# Run once initially, or whenever the Excel is updated.

library(tidyverse)
library(readxl)
library(glue)

EXCEL_PATH <- "reference/Estrutura_Indicadores_DataH_28102025.xlsx"
SHEET_RAW <- "TABELA FINAL 4122025"
SHEET_NORMALIZED <- "Normalizado"

message("=" %+% strrep("=", 70))
message("EXTRACTING DATA FROM EXCEL REFERENCE FILE")
message(strrep("=", 70) %+% "\n")

# Ensure output directory exists
dir.create("data-cache", showWarnings = FALSE, recursive = TRUE)

# ============================================================================
# Column-to-indicator mapping (Excel col index → indicator_id)
# Excel cols: 0=DICO, 1=Localizacao, 2-51=indicators
# We exclude col 48 (Risco de ventos fortes) → 49 indicators
# ============================================================================

col_mapping <- tibble::tribble(
  ~excel_col, ~indicator_id,
  2,  "taxa_crescimento_efetivo",
  3,  "taxa_bruta_natalidade",
  4,  "prop_pop_65_mais",
  5,  "prop_ensino_secundario",
  6,  "prop_nacionalidade_estrangeira",
  7,  "densidade_populacional",
  8,  "empresas_volume_negocios",
  9,  "percentagem_poder_compra",
  10, "coeficiente_gini",
  11, "disparidade_ganho_mensal",
  12, "taxa_desemprego",
  13, "prop_risco_pobreza",
  14, "prop_agregados_unipessoais",
  15, "prop_edificios_fora_urbano",
  16, "prop_mais_20min_escola",
  17, "prop_mais_30min_hospital",
  18, "duracao_pendulares",
  19, "acessos_internet_banda_larga",
  20, "valor_mediano_vendas_m2",
  21, "racio_vendas_estrangeiros",
  22, "taxa_esforco_arrendamento",
  23, "prop_alojamentos_arrendados",
  24, "prop_alojamentos_sobrelotados",
  25, "prop_habitacao_social",
  26, "prop_alojamentos_locais",
  27, "indice_envelhecimento_edificios",
  28, "prop_necessidade_reparacao",
  29, "prop_reabilitacao_edificado",
  30, "prop_alojamentos_vagos",
  31, "prop_vagos_bom_estado",
  32, "prop_alojamentos_nao_classicos",
  33, "certificacao_energetica_cf",
  34, "consumo_energia_eletrica",
  35, "emissoes_gee_edificios",
  36, "prop_sem_aquecimento",
  37, "prop_ar_condicionado",
  38, "emissoes_gee_transportes",
  39, "prop_modo_pedonal",
  40, "prop_transporte_coletivo",
  41, "risco_incendio_rural",
  42, "risco_inundacao",
  43, "risco_galgamentos_costeiros",
  44, "risco_ondas_calor",
  45, "risco_ondas_frio",
  46, "risco_nevao",
  47, "risco_seca",
  # 48 = Risco de ventos fortes (EXCLUDED)
  49, "risco_sismo",
  50, "risco_movimento_massa",
  51, "risco_tsunami"
)

message(glue("Mapping {nrow(col_mapping)} indicator columns\n"))

# ============================================================================
# 1. Read raw data from TABELA FINAL
# ============================================================================

message(glue("Reading sheet: {SHEET_RAW}..."))

raw_df <- read_excel(
  EXCEL_PATH,
  sheet = SHEET_RAW,
  col_names = FALSE,
  skip = 4  # Skip 4 header rows (rows 0-3)
)

# Extract DICO and municipality names
municipalities <- raw_df %>%
  select(dico = 1, name = 2) %>%
  mutate(dico = as.character(dico)) %>%
  filter(!is.na(dico), grepl("^[0-9]{4}$", dico))

message(glue("  Found {nrow(municipalities)} municipalities"))

# Pivot indicator columns to long format
raw_long <- raw_df %>%
  select(dico = 1, all_of(col_mapping$excel_col + 1)) %>%  # +1 because R is 1-indexed
  mutate(dico = as.character(dico)) %>%
  filter(!is.na(dico), grepl("^[0-9]{4}$", dico))

# Set column names to indicator IDs
names(raw_long) <- c("dico", col_mapping$indicator_id)

# Ensure all indicator columns are numeric (some may be read as character)
raw_long <- raw_long %>%
  mutate(across(-dico, ~as.numeric(.x)))

# Pivot to long format
static_raw <- raw_long %>%
  pivot_longer(
    cols = -dico,
    names_to = "indicator_id",
    values_to = "raw_value"
  )

message(glue("  Extracted {nrow(static_raw)} raw values"))
message(glue("  Indicators: {n_distinct(static_raw$indicator_id)}"))
message(glue("  Municipalities: {n_distinct(static_raw$dico)}\n"))

# ============================================================================
# 2. Read normalized data from Normalizado sheet
# ============================================================================

message(glue("Reading sheet: {SHEET_NORMALIZED}..."))

norm_df <- read_excel(
  EXCEL_PATH,
  sheet = SHEET_NORMALIZED,
  col_names = FALSE,
  skip = 4  # Same header structure
)

# Extract same columns
norm_long <- norm_df %>%
  select(dico = 1, all_of(col_mapping$excel_col + 1)) %>%
  mutate(dico = as.character(dico)) %>%
  filter(!is.na(dico), grepl("^[0-9]{4}$", dico))

names(norm_long) <- c("dico", col_mapping$indicator_id)

# Ensure all indicator columns are numeric
norm_long <- norm_long %>%
  mutate(across(-dico, ~as.numeric(.x)))

excel_normalized <- norm_long %>%
  pivot_longer(
    cols = -dico,
    names_to = "indicator_id",
    values_to = "excel_normalized"
  )

message(glue("  Extracted {nrow(excel_normalized)} normalized values\n"))

# ============================================================================
# 3. Save outputs
# ============================================================================

message("Saving outputs...")

# Static indicators (raw values)
write_csv(static_raw, "data-cache/static-indicators.csv")
message("  ✓ data-cache/static-indicators.csv")

# Excel normalized reference
write_csv(excel_normalized, "data-cache/excel-normalized-reference.csv")
message("  ✓ data-cache/excel-normalized-reference.csv")

# Municipalities reference
write_csv(municipalities, "data-cache/municipalities.csv")
message("  ✓ data-cache/municipalities.csv")

# ============================================================================
# 4. Validation summary
# ============================================================================

message(glue("\n{strrep('=', 71)}"))
message("EXCEL EXTRACTION COMPLETE")
message(strrep("=", 71))

# Check for NAs
na_count <- sum(is.na(static_raw$raw_value))
na_pct <- round(na_count / nrow(static_raw) * 100, 2)

message(glue("
Output:
  • static-indicators.csv:         {nrow(static_raw)} rows ({n_distinct(static_raw$indicator_id)} indicators × {n_distinct(static_raw$dico)} municipalities)
  • excel-normalized-reference.csv: {nrow(excel_normalized)} rows
  • municipalities.csv:             {nrow(municipalities)} municipalities

Data quality:
  • Missing raw values:  {na_count} ({na_pct}%)
  • Missing normalized:  {sum(is.na(excel_normalized$excel_normalized))}

Next step: Run scripts/01-fetch-data.R to fetch API indicators
"))

message(strrep("=", 71))
