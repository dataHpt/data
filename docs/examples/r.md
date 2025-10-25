# DataH API - R Examples

## Setup

```r
library(jsonlite)
library(httr)
library(tidyverse)

BASE_URL <- "https://datah.github.io/data/v1"
```

## Fetch Single Municipality

```r
get_municipality <- function(dico) {
  url <- glue::glue("{BASE_URL}/municipalities/{dico}.json")
  data <- fromJSON(url)
  return(data)
}

# Usage
lisboa <- get_municipality("1106")
print(lisboa$metadata$name) # "Lisboa"
```

## Get All Municipalities

```r
get_all_municipalities <- function() {
  url <- glue::glue("{BASE_URL}/municipalities/index.json")
  index <- fromJSON(url)
  return(index$municipalities)
}

# Usage
municipalities <- get_all_municipalities()
municipalities_df <- as_tibble(municipalities)

print(nrow(municipalities_df)) # 308
```

## Extract Indicators to DataFrame

```r
extract_indicators <- function(municipality_data) {
  indicators_list <- list()

  dimensions <- municipality_data$dimensions

  for (dim_name in names(dimensions)) {
    dim <- dimensions[[dim_name]]

    for (subdim_name in names(dim$sub_dimensions)) {
      subdim <- dim$sub_dimensions[[subdim_name]]

      for (gaveta_name in names(subdim$gavetas)) {
        gaveta <- subdim$gavetas[[gaveta_name]]

        for (ind_name in names(gaveta$indicators)) {
          ind <- gaveta$indicators[[ind_name]]

          indicators_list[[length(indicators_list) + 1]] <- tibble(
            dimension = dim_name,
            sub_dimension = subdim_name,
            gaveta = gaveta_name,
            indicator_id = ind_name,
            normalized = ind$normalized,
            raw = ind$raw,
            unit = ind$unit
          )
        }
      }
    }
  }

  bind_rows(indicators_list)
}

# Usage
lisboa <- get_municipality("1106")
indicators_df <- extract_indicators(lisboa)

print(indicators_df)
```

## Compare Multiple Municipalities

```r
compare_municipalities <- function(dicos, indicator_id) {
  results <- map_dfr(dicos, function(dico) {
    data <- get_municipality(dico)
    indicators <- extract_indicators(data)

    indicators %>%
      filter(indicator_id == !!indicator_id) %>%
      mutate(
        municipality = data$metadata$name,
        dico = dico
      ) %>%
      select(dico, municipality, normalized, raw, unit)
  })

  results %>%
    arrange(desc(normalized))
}

# Usage
comparison <- compare_municipalities(
  dicos = c("1106", "1311", "0101"),
  indicator_id = "taxa_desemprego"
)

print(comparison)
```

## Fetch and Cache

```r
library(memoise)

# Cache fetches to avoid repeated requests
get_municipality_cached <- memoise(
  get_municipality,
  cache = cache_filesystem(".cache/datah")
)

# Usage (primeira vez faz fetch, depois usa cache)
lisboa <- get_municipality_cached("1106")
```

## Visualization Example

```r
library(ggplot2)

# Compare single indicator across municipalities
plot_indicator_comparison <- function(indicator_id) {
  # Get all municipalities
  all_muns <- get_all_municipalities()

  # Fetch data for first 10 municipalities (example)
  data <- map_dfr(all_muns$dico[1:10], function(dico) {
    mun_data <- get_municipality(dico)
    indicators <- extract_indicators(mun_data)

    indicators %>%
      filter(indicator_id == !!indicator_id) %>%
      mutate(municipality = mun_data$metadata$name)
  })

  # Plot
  ggplot(data, aes(x = reorder(municipality, normalized), y = normalized)) +
    geom_col(fill = "#3498db") +
    coord_flip() +
    labs(
      title = paste("Comparação:", indicator_id),
      x = "Município",
      y = "Valor Normalizado (0-100)"
    ) +
    theme_minimal()
}

# Usage
plot_indicator_comparison("beneficiarios_rsi")
```

## Bulk Download (All Municipalities)

```r
# Para análises que requerem todos os dados
get_bulk_data <- function() {
  url <- glue::glue("{BASE_URL}/bulk/all-municipalities.json")

  # Warning: ~2MB
  message("Downloading bulk data (~2MB)...")
  data <- fromJSON(url)

  return(data$municipalities)
}

# Usage
all_data <- get_bulk_data()
length(all_data) # 308
```
