#!/usr/bin/env Rscript
# create-nuts-mapping.R - Create mapping from NUTS 2024 7-digit to legacy 4-digit DICO
#
# Uses municipality names to match between:
# - INE NUTS 2024 (7-digit codes)
# - Legacy DICO (4-digit codes from static CSV)

library(tidyverse)
library(httr)
library(jsonlite)

# Get legacy DICO codes and names from static CSV
legacy_mapping <- read_csv2(
  "scripts/utils/static-data-absolute.csv",
  locale = locale(decimal_mark = ",", grouping_mark = "."),
  show_col_types = FALSE
) %>%
  select(dico_legacy = DICO, name = Localizacao) %>%
  mutate(
    dico_legacy = str_pad(dico_legacy, 4, pad = "0"),
    # Normalize names for matching
    name_normalized = str_to_lower(name) %>%
      str_replace_all("á", "a") %>%
      str_replace_all("é|ê", "e") %>%
      str_replace_all("í", "i") %>%
      str_replace_all("ó|ô", "o") %>%
      str_replace_all("ú", "u") %>%
      str_replace_all("ã", "a") %>%
      str_replace_all("õ", "o") %>%
      str_replace_all("ç", "c") %>%
      str_trim()
  )

message(glue("Loaded {nrow(legacy_mapping)} legacy DICO codes"))

# Fetch from a known INE indicator to get NUTS 2024 codes and names
message("Fetching NUTS 2024 codes from INE...")

url <- "https://www.ine.pt/ine/json_indicador/pindicaNoLevel.jsp?op=2&varcd=0013420&Dim1=S7A2024&Dim2=lvl@5&lang=PT"
response <- GET(url, timeout(30))
data <- fromJSON(content(response, "text", encoding = "UTF-8"))

nuts2024_mapping <- data[[1]]$Dados %>%
  as_tibble() %>%
  select(dico_nuts2024 = dim_2, name = dim_2_t) %>%
  distinct() %>%
  mutate(
    # Normalize names for matching
    name_normalized = str_to_lower(name) %>%
      str_replace_all("á", "a") %>%
      str_replace_all("é|ê", "e") %>%
      str_replace_all("í", "i") %>%
      str_replace_all("ó|ô", "o") %>%
      str_replace_all("ú", "u") %>%
      str_replace_all("ã", "a") %>%
      str_replace_all("õ", "o") %>%
      str_replace_all("ç", "c") %>%
      str_trim()
  )

message(glue("Fetched {nrow(nuts2024_mapping)} NUTS 2024 codes"))

# Match by normalized names
nuts_to_dico_mapping <- nuts2024_mapping %>%
  left_join(legacy_mapping, by = "name_normalized") %>%
  select(dico_nuts2024, dico_legacy, name_nuts2024 = name.x, name_legacy = name.y)

# Check for unmatched
unmatched <- nuts_to_dico_mapping %>% filter(is.na(dico_legacy))
if (nrow(unmatched) > 0) {
  warning(glue("Found {nrow(unmatched)} unmatched NUTS 2024 codes:"))
  print(unmatched)
}

# Save mapping
saveRDS(nuts_to_dico_mapping, "scripts/utils/nuts2024-to-dico-mapping.rds")
write_csv(nuts_to_dico_mapping, "scripts/utils/nuts2024-to-dico-mapping.csv")

message(glue("\n✓ Saved mapping: {nrow(nuts_to_dico_mapping)} codes"))
message(glue("  Matched: {sum(!is.na(nuts_to_dico_mapping$dico_legacy))}"))
message(glue("  Unmatched: {sum(is.na(nuts_to_dico_mapping$dico_legacy))}"))
