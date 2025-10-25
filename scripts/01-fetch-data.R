#!/usr/bin/env Rscript
# 01-fetch-data.R - Multi-source data fetcher for DataH indicators
#
# Fetches indicator data from multiple sources:
# - INE: Instituto Nacional de Estatística (https://www.ine.pt)
# - DGT: Direção-Geral do Território (https://observatorioindicadores.dgterritorio.gov.pt)
#
# Routes fetching based on 'source' column in ine-mappings.csv
# See: scripts/utils/ine-mappings.csv

library(tidyverse)
library(httr)
library(jsonlite)
library(glue)
library(memoise)

# Disable proxy settings that may cause timeouts
Sys.unsetenv("http_proxy")
Sys.unsetenv("https_proxy")
Sys.unsetenv("HTTP_PROXY")
Sys.unsetenv("HTTPS_PROXY")

source("scripts/utils/ine-mappings.R")
source("scripts/utils/fetch-dgt.R")

# INE API Configuration ----

INE_BASE_URL <- "https://www.ine.pt"

# API Endpoints
INE_API_ENDPOINTS <- list(
  # Catalog API (XML) - Para listar indicadores
  catalog = "{base}/ine/xml_indic.jsp?opc={opc}&varcd={varcd}&lang={lang}",

  # Database API (JSON) - Para extrair dados
  data = "{base}/ine/json_indicador/pindica.jsp?op=2&varcd={varcd}&Dim1={dim1}&Dim2={dim2}&lang={lang}",

  # Database API sem nível específico (para obter todos os municípios)
  data_level = "{base}/ine/json_indicador/pindicaNoLevel.jsp?op=2&varcd={varcd}&Dim1={dim1}&Dim2={dim2}&lang={lang}",

  # Metainformation API (JSON) - Para obter metadata de indicadores
  metadata = "{base}/ine/json_indicador/pindicaMeta.jsp?varcd={varcd}&lang={lang}"
)

# Helper Functions ----

#' Standardize DICO codes to 4 digits
#'
#' Converts both 4-digit (legacy) and 7-digit (NUTS 2024) codes to 4-digit format
#' NUTS 2024 mapping: takes LAST 4 digits (e.g., 1111605 → 1605)
#' Filters out non-municipal codes (freguesias with letters in code)
#'
#' @param dico Character vector - DICO codes (4 or 7 digits)
#' @return Character vector - Standardized 4-digit DICO codes (or NA for invalid)
standardize_dico <- function(dico) {
  dico <- as.character(dico)
  # If 7 digits, take LAST 4 digits (NUTS 2024 → legacy mapping)
  # If 4 digits, keep as is
  dico_4 <- ifelse(nchar(dico) == 7, str_sub(dico, -4, -1), dico)
  # Only keep 4-digit numeric codes (municipalities)
  # Set codes with letters (freguesias) to NA so they get filtered out
  ifelse(grepl("^[0-9]{4}$", dico_4), dico_4, NA_character_)
}

#' Build INE API URL
#'
#' Constrói URL para API do INE
#'
#' @param endpoint Character - Tipo de endpoint ("data", "metadata", "catalog")
#' @param params List - Parâmetros para substituir no template
#' @return Character - URL completa
build_ine_url <- function(endpoint = "data", params = list()) {
  template <- INE_API_ENDPOINTS[[endpoint]]
  params$base <- INE_BASE_URL

  url <- template
  for (param_name in names(params)) {
    url <- str_replace(url, glue("\\{{{param_name}\\}}"), as.character(params[[param_name]]))
  }

  return(url)
}

#' Fetch from INE API
#'
#' Faz request à API do INE com tratamento de erros
#'
#' @param url Character - URL completa da API
#' @param timeout Numeric - Timeout em segundos (default: 30)
#' @return Parsed JSON response
fetch_ine_api <- function(url, timeout = 30) {
  tryCatch({
    response <- GET(url, httr::timeout(timeout))

    # Check HTTP status
    if (http_error(response)) {
      stop(glue("HTTP error {status_code(response)}: {http_status(response)$message}"))
    }

    # Parse JSON
    content <- content(response, as = "text", encoding = "UTF-8")
    data <- fromJSON(content, simplifyVector = TRUE)

    return(data)

  }, error = function(e) {
    stop(glue("Failed to fetch from INE API: {e$message}\nURL: {url}"))
  })
}

#' Get Indicator Metadata
#'
#' Obtém metadata de um indicador (dimensões disponíveis, períodos, etc.)
#'
#' @param varcd Character - Código do indicador (7 dígitos)
#' @param lang Character - Idioma ("PT" ou "EN")
#' @return List com metadata do indicador
get_indicator_metadata <- function(varcd, lang = "PT") {
  url <- build_ine_url("metadata", list(varcd = varcd, lang = lang))

  message(glue("Fetching metadata for indicator {varcd}..."))
  metadata <- fetch_ine_api(url)

  return(metadata)
}

# Main Fetch Functions ----

#' Fetch INE Indicator Data
#'
#' Faz fetch de dados de um indicador do INE para todos os municípios
#' Usa estratégia de 2 passos: metadata primeiro para obter período mais recente
#'
#' @param varcd Character - Código do indicador INE (7 dígitos, ex: "0013420")
#' @param year Numeric/Character - Ano de referência (ex: 2023). Se NULL/NA, usa o mais recente
#' @param lang Character - Idioma ("PT" ou "EN")
#' @param dim3_filter Character - Se presente, filtra dim_3 (opcional)
#' @param dim4_filter Character - Se presente, filtra dim_4 (opcional)
#' @return Dataframe com colunas: dico, value, period, geodsg
#'
#' Nota: Esta função usa Dim2=lvl@5 para obter dados de todos os municípios
#' (nível 5 da dimensão geográfica = município)
fetch_ine_indicator_data <- function(varcd, year = NULL, lang = "PT", dim3_filter = NULL, dim4_filter = NULL) {

  # Step 1: Determinar período a usar
  if (is.null(year) || is.na(year)) {
    # Fetch metadata para obter último período disponível
    message(glue("Fetching metadata for indicator {varcd} to get latest period..."))
    metadata <- get_indicator_metadata(varcd, lang)

    if (is.null(metadata) || is.null(metadata$UltimoPeriodo)) {
      stop(glue("Could not fetch metadata for indicator {varcd}"))
    }

    ultimo_periodo <- metadata$UltimoPeriodo
    dim1 <- glue("S7A{ultimo_periodo}")
    message(glue("Using latest period: {ultimo_periodo}"))
  } else {
    # Usa ano especificado
    dim1 <- glue("S7A{year}")
    message(glue("Using specified year: {year}"))
  }

  # Step 2: Fetch dados usando o período determinado
  # Dim2=lvl@5 significa: nível 5 da dimensão geográfica (municípios)
  dim2 <- "lvl@5"

  # Build URL para dados
  url <- build_ine_url(
    "data_level",
    list(varcd = varcd, dim1 = dim1, dim2 = dim2, lang = lang)
  )

  message(glue("Fetching data for indicator {varcd} with Dim1={dim1}..."))

  # Fetch data
  response <- fetch_ine_api(url)

  if (is.null(response) || length(response) == 0) {
    warning(glue("No data returned for indicator {varcd}"))
    return(NULL)
  }

  # Parse INE JSON response (new Dados[] structure)
  parsed_data <- parse_ine_response_new(response, varcd, dim3_filter, dim4_filter)

  return(parsed_data)
}

#' Parse INE JSON Response
#'
#' Processa a resposta JSON do INE e extrai dados de municípios
#'
#' @param response List - Resposta JSON parseada do INE
#' @param varcd Character - Código do indicador (para referência)
#' @return Dataframe com dico, value, period
parse_ine_response <- function(response, varcd) {
  # A estrutura da resposta INE varia dependendo do indicador
  # Geralmente contém arrays aninhados com:
  # - geocod: código geográfico (DICO)
  # - valor: valor do indicador
  # - período: período de referência

  tryCatch({
    # Verifica se resposta é array
    if (!is.list(response)) {
      stop("Response is not a list/array")
    }

    # Extrai dados (estrutura pode variar)
    # Opção 1: Array direto de objetos
    if ("geocod" %in% names(response[[1]]) || "geodsg" %in% names(response[[1]])) {
      data <- map_dfr(response, function(item) {
        tibble(
          geocod = item$geocod %||% item$geodsg %||% NA,
          value = as.numeric(item$valor %||% item$value %||% NA),
          period = item$periodo %||% item$period %||% NA,
          geodsg = item$geodsg %||% NA  # Nome do município
        )
      })
    } else {
      # Opção 2: Estrutura mais complexa (tentar extrair recursivamente)
      data <- extract_data_recursive(response)
    }

    # Converte geocod para formato DICO (4 dígitos)
    # Geocod do INE pode ter 6 dígitos (DICOFRE), precisamos dos primeiros 4 (DICO)
    if ("geocod" %in% names(data)) {
      data <- data %>%
        mutate(
          dico = str_sub(as.character(geocod), 1, 4),
          dico = str_pad(dico, 4, pad = "0")
        ) %>%
        select(dico, value, period, geodsg)
    } else {
      warning(glue("Could not find geocod in response for {varcd}"))
      return(NULL)
    }

    # Remove NAs e duplicados (mantém último período se houver múltiplos)
    data <- data %>%
      filter(!is.na(value), !is.na(dico)) %>%
      group_by(dico) %>%
      arrange(desc(period)) %>%
      slice(1) %>%
      ungroup()

    return(data)

  }, error = function(e) {
    warning(glue("Failed to parse INE response for {varcd}: {e$message}"))
    return(NULL)
  })
}

#' Extract Data Recursively
#'
#' Helper para extrair dados de estruturas JSON aninhadas
extract_data_recursive <- function(obj, depth = 0) {
  if (depth > 10) return(NULL)  # Evita recursão infinita

  if (is.list(obj)) {
    # Se tem campos que esperamos, extrai
    if (all(c("geocod", "valor") %in% names(obj)) ||
        all(c("geodsg", "value") %in% names(obj))) {
      return(tibble(
        geocod = obj$geocod %||% obj$geodsg %||% NA,
        value = as.numeric(obj$valor %||% obj$value %||% NA),
        period = obj$periodo %||% obj$period %||% NA,
        geodsg = obj$geodsg %||% NA
      ))
    }

    # Senão, tenta recursivamente em cada elemento
    results <- map(obj, ~extract_data_recursive(.x, depth + 1))
    results <- results[!map_lgl(results, is.null)]

    if (length(results) > 0) {
      return(bind_rows(results))
    }
  }

  return(NULL)
}

#' Parse INE JSON Response (New Structure)
#'
#' Processa a nova estrutura de resposta do INE (desde 2024)
#' Estrutura: response[].Dados[] com dim_2 (geocod) e valor
#'
#' @param response List - Resposta JSON parseada do INE
#' @param varcd Character - Código do indicador (para referência)
#' @return Dataframe com dico, value, period, geodsg
parse_ine_response_new <- function(response, varcd, dim3_filter = NULL, dim4_filter = NULL) {
  tryCatch({
    # Nova estrutura INE: array com IndicadorCod, Dados[], etc.
    # response é uma lista, pegamos o primeiro elemento
    if (!is.list(response) || length(response) == 0) {
      stop("Response is not a list or is empty")
    }

    # O response pode ser um array de objetos, pegamos o primeiro
    data_obj <- if (is.list(response[[1]])) response[[1]] else response

    # Verifica se tem campo Dados
    if (is.null(data_obj$Dados) || length(data_obj$Dados) == 0) {
      warning(glue("No 'Dados' field found in response for {varcd}"))
      return(NULL)
    }

    # Extrai dados do array Dados[]
    # Estrutura: dim_1, dim_1_t (período), dim_2 (geocod), dim_2_t (nome), valor
    # Alguns indicadores têm também dim_3 (ex: tipo de aquecimento)
    dados <- data_obj$Dados

    # Converte lista para data frame primeiro (evita problema de colunas não nomeadas)
    df <- bind_rows(dados)

    # Se dim3_filter está presente, filtramos dim_3
    if (!is.null(dim3_filter) && "dim_3" %in% names(df)) {

      # Check if this is a filter by dim_3_t (text) or dim_3 (code)
      # If dim3_filter contains letters, filter by dim_3_t, otherwise by dim_3
      if (grepl("[A-Za-z]", dim3_filter)) {
        message(glue("Filtering for dim_3_t == '{dim3_filter}'"))

        # Simple filter: just keep rows where dim_3_t matches
        df <- df %>%
          filter(dim_3_t == dim3_filter) %>%
          mutate(
            dico = standardize_dico(dim_2),
            value = as.numeric(valor),
            period = as.character(dim_1_t),
            geodsg = as.character(dim_2_t)
          ) %>%
          select(dico, value, period, geodsg)

      } else {
        # Numeric filter: calculate proportion (category / Total)
        message(glue("Calculating proportion for dim_3 == '{dim3_filter}'"))

        # Separar dados filtrados e totais
        df_filtered <- df %>%
          filter(dim_3 == dim3_filter) %>%
          mutate(
            dico = standardize_dico(dim_2),
            value_filtered = as.numeric(valor),
            period = as.character(dim_1_t),
            geodsg = as.character(dim_2_t)
          ) %>%
          select(dico, value_filtered, period, geodsg)

        # Procurar "Total" em dim_3_t
        df_total <- df %>%
          filter(dim_3_t == "Total") %>%
          mutate(
            dico = standardize_dico(dim_2),
            value_total = as.numeric(valor)
          ) %>%
          select(dico, value_total)

        # Join e calcular proporção
        df <- df_filtered %>%
          left_join(df_total, by = "dico") %>%
          mutate(
            value = ifelse(value_total > 0, (value_filtered / value_total) * 100, NA)
          ) %>%
          select(dico, value, period, geodsg)
      }

    } else {
      # Sem filtro dim_3, processar normalmente
      df <- df %>%
        mutate(
          dico = standardize_dico(dim_2),
          value = as.numeric(valor),
          period = as.character(dim_1_t),  # Ano legível (ex: "2024")
          geodsg = as.character(dim_2_t)   # Nome do município
        ) %>%
        select(dico, value, period, geodsg)
    }

    # Se dim4_filter está presente E temos dados com valor já extraído, filtramos dim_4
    # (dim4 filtering happens after dim3, using original dados if needed)
    if (!is.null(dim4_filter) && "dim_4" %in% names(bind_rows(dados))) {
      message(glue("Filtering for dim_4_t == '{dim4_filter}'"))

      # Re-process from original dados but with both filters
      df_raw <- bind_rows(dados)

      # Apply both dim3 and dim4 filters
      if (!is.null(dim3_filter)) {
        # Filter both dimensions
        if (grepl("[A-Za-z]", dim3_filter)) {
          df_raw <- df_raw %>% filter(dim_3_t == dim3_filter)
        } else {
          df_raw <- df_raw %>% filter(dim_3 == dim3_filter)
        }
      }

      # Now filter dim_4
      # Check if dim4_filter contains "|" for multiple values to sum
      if (grepl("\\|", dim4_filter)) {
        # Multiple values: sum them and calculate proportion vs Total
        dim4_values <- str_split(dim4_filter, "\\|")[[1]]
        message(glue("Calculating proportion for dim_4_t values: {paste(dim4_values, collapse=', ')}"))

        # Get the sum of target categories
        df_filtered <- df_raw %>%
          filter(dim_4_t %in% dim4_values) %>%
          mutate(
            dico = standardize_dico(dim_2),
            value_filtered = as.numeric(valor),
            period = as.character(dim_1_t),
            geodsg = as.character(dim_2_t)
          ) %>%
          group_by(dico, period, geodsg) %>%
          summarise(value_filtered = sum(value_filtered, na.rm = TRUE), .groups = "drop")

        # Get the Total
        df_total <- df_raw %>%
          filter(dim_4_t == "Total") %>%
          mutate(
            dico = standardize_dico(dim_2),
            value_total = as.numeric(valor)
          ) %>%
          select(dico, value_total)

        # Calculate proportion
        df <- df_filtered %>%
          left_join(df_total, by = "dico") %>%
          mutate(
            value = ifelse(value_total > 0, (value_filtered / value_total) * 100, NA)
          ) %>%
          select(dico, value, period, geodsg)

      } else {
        # Single value: simple filter
        if (grepl("[A-Za-z]", dim4_filter)) {
          df_raw <- df_raw %>% filter(dim_4_t == dim4_filter)
        } else {
          df_raw <- df_raw %>% filter(dim_4 == dim4_filter)
        }

        # Extract final values
        df <- df_raw %>%
          mutate(
            dico = standardize_dico(dim_2),
            value = as.numeric(valor),
            period = as.character(dim_1_t),
            geodsg = as.character(dim_2_t)
          ) %>%
          select(dico, value, period, geodsg)
      }
    }

    # Remove NAs
    df <- df %>%
      filter(!is.na(dico), !is.na(value))

    # Se houver múltiplos períodos, mantém apenas o mais recente
    if (n_distinct(df$period) > 1) {
      df <- df %>%
        arrange(desc(period)) %>%
        group_by(dico) %>%
        slice(1) %>%
        ungroup()
    }

    message(glue("Parsed {nrow(df)} municipalities from INE response"))

    return(df)

  }, error = function(e) {
    warning(glue("Failed to parse INE response for {varcd}: {e$message}"))
    return(NULL)
  })
}

#' Fetch Single Indicator (multi-source: INE or DGT)
#'
#' Routes fetching based on source column in mapping
#'
#' @param indicator_id Character - ID do indicador (ex: "beneficiarios_rsi")
#' @return Dataframe com colunas: dico, indicator_id, raw_value
fetch_indicator <- function(indicator_id) {
  message(glue("\n=== Fetching {indicator_id} ==="))

  # Obtém mapeamento
  mapping <- get_indicator_mapping(indicator_id)

  # Determina source (default: INE se não especificado)
  source <- mapping$source %||% "INE"
  message(glue("Source: {source}"))

  # Verifica se indicador está mapeado
  # Suporta 'code' (novo) ou 'ine_varcd'/'ine_table' (legacy)
  code <- mapping$code %||% mapping$ine_varcd %||% mapping$ine_table

  if (is.null(code) || code == "TODO" || code == "") {
    warning(glue("Indicator {indicator_id} not yet mapped (code = TODO or empty)"))
    return(NULL)
  }

  # Route fetching based on source
  tryCatch({
    if (source == "DGT") {
      # Fetch from DGT Observatório
      data <- fetch_dgt_indicator(indicator_id = as.numeric(code))

      if (is.null(data) || nrow(data) == 0) {
        warning(glue("No data returned for {indicator_id} from DGT"))
        return(NULL)
      }

      # Padroniza formato: dico, value, geodsg
      result <- data %>%
        mutate(
          indicator_id = indicator_id,
          raw_value = value
        ) %>%
        select(dico, indicator_id, raw_value)

    } else {
      # Fetch from INE (default)
      data <- fetch_ine_indicator_data(
        varcd = code,  # Código do indicador INE (7 dígitos)
        year = mapping$year,
        dim3_filter = mapping$dim3_filter,  # Filtro para dim_3 (se aplicável)
        dim4_filter = mapping$dim4_filter   # Filtro para dim_4 (se aplicável)
      )

      if (is.null(data) || nrow(data) == 0) {
        warning(glue("No data returned for {indicator_id} from INE"))
        return(NULL)
      }

      # Adiciona indicator_id e renomeia colunas
      result <- data %>%
        mutate(
          indicator_id = indicator_id,
          raw_value = value
        ) %>%
        select(dico, indicator_id, raw_value)
    }

    message(glue("✓ Fetched {nrow(result)} municipalities for {indicator_id}"))

    # Valida que temos dados para número razoável de municípios
    if (nrow(result) < 100) {
      warning(glue("Only {nrow(result)} municipalities found (expected ~308)"))
    }

    return(result)

  }, error = function(e) {
    warning(glue("Failed to fetch {indicator_id}: {e$message}"))
    return(NULL)
  })
}

# Legacy wrapper for compatibility
fetch_ine_indicator <- fetch_indicator

#' Fetch All Indicators
#'
#' Faz fetch de todos os indicadores definidos no mapeamento (INE + DGT)
#'
#' @param use_cache Logical - Usar cache para evitar fetches repetidos
#' @return Dataframe com colunas: dico, indicator_id, raw_value
fetch_all_indicators <- function(use_cache = TRUE) {
  message("=== Fetching All Indicators (INE + DGT) ===\n")

  # Filtra apenas indicadores com mapeamento completo
  # Suporta: code (novo), ine_varcd (legacy), ine_table (legacy)
  indicators_to_fetch <- ine_indicator_mappings %>%
    filter(
      # Check 'code' column if it exists, otherwise check legacy columns
      if ("code" %in% names(.)) {
        code != "TODO" & code != "" & !is.na(code)
      } else if ("ine_varcd" %in% names(.)) {
        ine_varcd != "TODO" & ine_varcd != "" & !is.na(ine_varcd)
      } else {
        ine_table != "TODO" & ine_table != "" & !is.na(ine_table)
      }
    ) %>%
    pull(indicator_id)

  if (length(indicators_to_fetch) == 0) {
    warning("No indicators with complete mappings found")
    warning("Please update scripts/utils/ine-mappings.csv with real codes")
    return(NULL)
  }

  # Count by source
  source_counts <- ine_indicator_mappings %>%
    filter(indicator_id %in% indicators_to_fetch) %>%
    count(source = source %||% "INE")

  message(glue("Found {length(indicators_to_fetch)} indicators to fetch:"))
  for (i in 1:nrow(source_counts)) {
    message(glue("  - {source_counts$source[i]}: {source_counts$n[i]} indicators"))
  }
  message("")

  # Setup caching se solicitado
  if (use_cache) {
    dir.create(".cache/indicators", showWarnings = FALSE, recursive = TRUE)
    fetch_cached <- memoise(
      fetch_indicator,
      cache = cache_filesystem(".cache/indicators")
    )
  } else {
    fetch_cached <- fetch_indicator
  }

  # Fetch cada indicador (com progresso)
  all_data <- list()
  pb <- txtProgressBar(min = 0, max = length(indicators_to_fetch), style = 3)

  for (i in seq_along(indicators_to_fetch)) {
    ind_id <- indicators_to_fetch[i]

    result <- fetch_cached(ind_id)

    if (!is.null(result)) {
      all_data[[ind_id]] <- result
    }

    setTxtProgressBar(pb, i)

    # Rate limiting: pausa entre requests para não sobrecarregar APIs
    Sys.sleep(0.5)
  }

  close(pb)

  # Combina todos os dados
  if (length(all_data) == 0) {
    warning("No data fetched from any source")
    return(NULL)
  }

  all_data_df <- bind_rows(all_data)

  message(glue("\n✓ Successfully fetched {length(all_data)} indicators"))
  message(glue("✓ Total data points: {nrow(all_data_df)}"))

  return(all_data_df)
}

# Municipality Reference Data ----

#' Fetch Municipality Names and Codes from INE
#'
#' Obtém lista de municípios usando um indicador populacional
#' (garantido ter dados para todos os 308 municípios)
#'
#' @return Dataframe com colunas: dico, name
fetch_municipalities_reference <- function() {
  message("Fetching municipalities reference from INE...")

  # Usa indicador de população residente (sempre disponível para todos os municípios)
  # Código 0011292 = População residente
  POPULATION_INDICATOR <- "0011292"

  tryCatch({
    # Fetch dados populacionais (qualquer ano recente)
    pop_data <- fetch_ine_indicator_data(
      varcd = POPULATION_INDICATOR,
      year = 2021  # Ano dos Censos
    )

    if (is.null(pop_data) || nrow(pop_data) == 0) {
      stop("Could not fetch municipality data from population indicator")
    }

    # Extrai DICO e nome
    municipalities <- pop_data %>%
      select(dico, name = geodsg) %>%
      distinct() %>%
      arrange(dico)

    # Validação
    if (nrow(municipalities) < 300) {
      warning(glue("Only {nrow(municipalities)} municipalities found (expected 308)"))
    }

    message(glue("✓ Fetched {nrow(municipalities)} municipalities"))

    return(municipalities)

  }, error = function(e) {
    warning(glue("Failed to fetch municipalities from INE: {e$message}"))
    warning("Falling back to static list...")

    # Fallback: usar lista estática mínima
    return(get_static_municipalities_list())
  })
}

#' Get Static Municipalities List
#'
#' Fallback: lista estática de municípios (caso API falhe)
#' TODO: Expandir para os 308 municípios se necessário
get_static_municipalities_list <- function() {
  # Lista parcial de municípios como fallback
  # Idealmente, ter os 308 num ficheiro CSV/JSON
  tibble(
    dico = c("0101", "0102", "0103", "1106", "1311", "1308"),
    name = c("Águeda", "Albergaria-a-Velha", "Anadia", "Lisboa", "Porto", "Braga")
  )
}

# Data Quality Checks ----

#' Validate Fetched Data
#'
#' Verifica integridade dos dados fetched do INE
validate_fetched_data <- function(data) {
  checks <- list()

  # 1. Check colunas obrigatórias
  required_cols <- c("dico", "indicator_id", "raw_value")
  checks$has_required_cols <- all(required_cols %in% names(data))

  if (!checks$has_required_cols) {
    warning(glue("Missing required columns: {paste(setdiff(required_cols, names(data)), collapse=', ')}"))
  }

  # 2. Check valores NA
  na_count <- sum(is.na(data$raw_value))
  na_pct <- round(na_count / nrow(data) * 100, 2)
  checks$acceptable_na <- na_pct < 10 # <10% NA aceitável

  if (!checks$acceptable_na) {
    warning(glue("High percentage of NA values: {na_pct}%"))
  }

  # 3. Check número de municípios
  unique_dicos <- n_distinct(data$dico)
  checks$has_municipalities <- unique_dicos > 0

  message(glue("  - {unique_dicos} unique municipalities"))

  if (unique_dicos < 300) {
    warning(glue("Only {unique_dicos} municipalities (expected ~308)"))
  }

  # 4. Check número de indicadores
  unique_indicators <- n_distinct(data$indicator_id)
  checks$has_indicators <- unique_indicators > 0

  message(glue("  - {unique_indicators} unique indicators"))
  message(glue("  - {nrow(data)} total data points"))
  message(glue("  - {na_pct}% NA values"))

  # Summary
  if (all(unlist(checks))) {
    message("✓ Data validation passed")
  } else {
    failed <- names(checks)[!unlist(checks)]
    warning(glue("⚠ Validation failed: {paste(failed, collapse=', ')}"))
  }

  return(all(unlist(checks)))
}

# Main Pipeline ----

#' Run Fetch Pipeline
#'
#' Executa pipeline completo de fetch de dados multi-source (INE + DGT)
#'
#' @param output_file Character - Path para guardar dados raw (RDS)
#' @param municipalities_output Character - Path para guardar referência de municípios
#' @param use_cache Logical - Usar cache de requests
run_fetch_pipeline <- function(
    output_file = "data-cache/raw_indicators.rds",
    municipalities_output = "data-cache/municipalities.rds",
    use_cache = TRUE
) {
  message("=== Starting Multi-Source Data Fetch Pipeline (INE + DGT) ===\n")
  message(glue("Date: {Sys.time()}"))
  message(glue("INE API: {INE_BASE_URL}"))
  message(glue("DGT API: {DGT_BASE_URL}\n"))

  # 1. Fetch municipalities reference
  message("Step 1: Fetching municipalities reference...")
  tryCatch({
    municipalities <- fetch_municipalities_reference()

    # Save
    dir.create(dirname(municipalities_output), showWarnings = FALSE, recursive = TRUE)
    saveRDS(municipalities, municipalities_output)
    message(glue("✓ Saved municipalities to {municipalities_output}\n"))

  }, error = function(e) {
    stop(glue("Failed to fetch municipalities: {e$message}"))
  })

  # 2. Fetch indicators
  message("Step 2: Fetching indicators from all sources (INE + DGT)...")
  tryCatch({
    raw_data <- fetch_all_indicators(use_cache = use_cache)

    if (is.null(raw_data) || nrow(raw_data) == 0) {
      stop("No data fetched from any source")
    }

    # 3. Validate
    message("\nStep 3: Validating fetched data...")
    if (!validate_fetched_data(raw_data)) {
      warning("⚠ Data validation failed, but continuing...")
    }

    # 4. Save
    message(glue("\nStep 4: Saving to {output_file}..."))
    dir.create(dirname(output_file), showWarnings = FALSE, recursive = TRUE)
    saveRDS(raw_data, output_file)

    message("\n" %+% strrep("=", 50))
    message("✓ Fetch pipeline completed successfully")
    message(strrep("=", 50))
    message(glue("Raw data: {output_file}"))
    message(glue("Municipalities: {municipalities_output}"))
    message(glue("Total indicators: {n_distinct(raw_data$indicator_id)}"))
    message(glue("Total municipalities: {n_distinct(raw_data$dico)}"))
    message(glue("Total data points: {nrow(raw_data)}"))

    return(raw_data)

  }, error = function(e) {
    stop(glue("Fetch pipeline failed: {e$message}"))
  })
}

# Execute if run directly ----
if (sys.nframe() == 0) {
  run_fetch_pipeline()
}
