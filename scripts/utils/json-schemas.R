#!/usr/bin/env Rscript
# json-schemas.R - JSON schema definitions and generation functions
#
# Este ficheiro define a estrutura hierárquica dos JSONs da API:
# Dimension → Sub-dimension → Gaveta → Indicators

library(jsonlite)
library(glue)
library(lubridate)

# API Configuration ----
API_VERSION <- "1.0.0"

# Get current timestamp in ISO 8601 format
get_timestamp <- function() {
  format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# Municipality JSON Schema ----
#
# Gera o JSON completo para um município individual
#
# @param dico Character - Código DICO do município (ex: "1106")
# @param name Character - Nome do município (ex: "Lisboa")
# @param dimensions_data List - Dados hierárquicos (ver exemplo abaixo)
# @return JSON string formatado
#
# Exemplo de estrutura esperada em dimensions_data:
# list(
#   coesao_territorial = list(
#     sub_dimensions = list(
#       dinamicas_sociais = list(
#         gavetas = list(
#           desigualdade = list(
#             indicators = list(
#               beneficiarios_rsi = list(normalized = 6.97, raw = 15.0, unit = "%"),
#               disparidade_ganho = list(normalized = 27.0, raw = 10.5, unit = "%")
#             )
#           )
#         )
#       )
#     )
#   )
# )
generate_municipality_json <- function(dico, name, dimensions_data) {
  structure <- list(
    metadata = list(
      dico = dico,
      name = name,
      last_updated = get_timestamp(),
      api_version = API_VERSION
    ),
    dimensions = dimensions_data
  )

  toJSON(structure, auto_unbox = TRUE, pretty = TRUE, na = "null")
}

# Index JSON Schema ----
#
# Gera o JSON de índice com lista de todos os municípios
#
# @param municipalities_df Dataframe com colunas: dico, name
# @return JSON string
generate_index_json <- function(municipalities_df) {
  structure <- list(
    total = nrow(municipalities_df),
    last_updated = get_timestamp(),
    municipalities = lapply(1:nrow(municipalities_df), function(i) {
      list(
        dico = municipalities_df$dico[i],
        name = municipalities_df$name[i],
        url = glue("/v1/municipalities/{municipalities_df$dico[i]}.json")
      )
    })
  )

  toJSON(structure, auto_unbox = TRUE, pretty = TRUE)
}

# Metadata - Indicators JSON Schema ----
#
# Gera JSON com metadata completa de todos os indicadores
#
# @param indicators_df Dataframe com colunas:
#   - id, name, description, dimension, sub_dimension, gaveta
#   - unit, direction (lower_is_better/higher_is_better)
#   - source_name, source_year, source_table_code, source_url
# @return JSON string
generate_indicators_metadata_json <- function(indicators_df) {
  structure <- list(
    version = API_VERSION,
    last_updated = get_timestamp(),
    indicators = lapply(1:nrow(indicators_df), function(i) {
      row <- indicators_df[i, ]
      list(
        id = row$id,
        name = row$name,
        description = row$description,
        dimension = row$dimension,
        sub_dimension = row$sub_dimension,
        gaveta = row$gaveta,
        unit = row$unit,
        direction = row$direction,
        normalization = list(
          method = "min-max",
          range = c(0, 100),
          inverted = row$direction == "lower_is_better"
        ),
        source = list(
          name = row$source_name,
          year = as.integer(row$source_year),
          table_code = row$source_table_code,
          url = row$source_url,
          fetch_date = as.character(Sys.Date())
        )
      )
    })
  )

  toJSON(structure, auto_unbox = TRUE, pretty = TRUE)
}

# Metadata - Hierarchy JSON Schema ----
#
# Gera JSON com a estrutura hierárquica completa
# Útil para frontends que precisam renderizar a árvore de dimensões
#
# @return JSON string com estrutura dimensional
generate_hierarchy_json <- function() {
  structure <- list(
    version = API_VERSION,
    last_updated = get_timestamp(),
    hierarchy = list(
      list(
        id = "coesao_territorial",
        name = "Coesão Territorial",
        sub_dimensions = list(
          list(
            id = "dinamicas_sociais",
            name = "Dinâmicas Sociais",
            gavetas = list(
              list(id = "desigualdade", name = "Desigualdade"),
              list(id = "isolamento", name = "Isolamento"),
              list(id = "acesso_mercado", name = "Acesso ao Mercado")
            )
          ),
          list(
            id = "dinamicas_habitacao",
            name = "Dinâmicas de Habitação",
            gavetas = list(
              list(id = "caracteristicas", name = "Características da Habitação"),
              list(id = "propriedade", name = "Regime de Propriedade")
            )
          )
        )
      ),
      list(
        id = "sustentabilidade_ambiental",
        name = "Sustentabilidade Ambiental",
        sub_dimensions = list(
          list(
            id = "eficiencia_energetica",
            name = "Eficiência Energética",
            gavetas = list(
              list(id = "consumo", name = "Consumo Energético"),
              list(id = "certificacao", name = "Certificação Energética")
            )
          ),
          list(
            id = "catastrofes_naturais",
            name = "Catástrofes Naturais",
            gavetas = list(
              list(id = "risco", name = "Risco de Catástrofes"),
              list(id = "resilience", name = "Resiliência")
            )
          )
        )
      )
    )
  )

  toJSON(structure, auto_unbox = TRUE, pretty = TRUE)
}

# Metadata - Sources JSON Schema ----
#
# Gera JSON com informação sobre fontes de dados (INE)
#
# @param sources_df Dataframe com colunas: dimension, last_ine_update, tables_used
# @return JSON string
generate_sources_json <- function(sources_df = NULL) {
  # Se não for fornecido dataframe, criar estrutura default
  if (is.null(sources_df)) {
    sources_df <- data.frame(
      dimension = c("coesao_territorial", "sustentabilidade_ambiental"),
      last_ine_update = c("2023", "2023"),
      tables_count = c(30, 16),
      stringsAsFactors = FALSE
    )
  }

  structure <- list(
    version = API_VERSION,
    last_updated = get_timestamp(),
    primary_source = list(
      name = "Instituto Nacional de Estatística (INE)",
      url = "https://www.ine.pt",
      api_url = "https://www.ine.pt/xportal/xmain?xpid=INE&xpgid=ine_api"
    ),
    dimensions = lapply(1:nrow(sources_df), function(i) {
      row <- sources_df[i, ]
      list(
        dimension = row$dimension,
        last_ine_update = row$last_ine_update,
        tables_count = as.integer(row$tables_count)
      )
    })
  )

  toJSON(structure, auto_unbox = TRUE, pretty = TRUE)
}

# Bulk JSON Schema ----
#
# Gera JSON único com dados de todos os municípios
# Útil para downloads completos ou análises batch
#
# @param all_municipalities List de listas (output de generate_municipality_json parseado)
# @return JSON string
generate_bulk_json <- function(all_municipalities) {
  structure <- list(
    metadata = list(
      total_municipalities = length(all_municipalities),
      last_updated = get_timestamp(),
      api_version = API_VERSION,
      warning = "Este ficheiro contém todos os 308 municípios (~2MB). Para uso em produção, prefira os endpoints individuais."
    ),
    municipalities = all_municipalities
  )

  toJSON(structure, auto_unbox = TRUE, pretty = FALSE) # Sem pretty para reduzir tamanho
}

# Helper: Build Indicator Object ----
#
# Função auxiliar para construir objeto de indicador com validação
#
# @param normalized Numeric - Valor normalizado (0-100)
# @param raw Numeric - Valor original
# @param unit Character - Unidade (ex: "%", "€", "n")
# @return List formatada
build_indicator <- function(normalized, raw, unit) {
  # Validação
  if (!is.numeric(normalized) || normalized < 0 || normalized > 100) {
    warning(glue("Normalized value out of range [0,100]: {normalized}"))
  }

  list(
    normalized = round(normalized, 2),
    raw = raw,
    unit = unit
  )
}

# Helper: Validate Municipality JSON ----
#
# Valida estrutura de um JSON de município
#
# @param json_string Character - JSON a validar
# @return Logical - TRUE se válido
validate_municipality_json <- function(json_string) {
  tryCatch({
    data <- fromJSON(json_string)

    # Checks básicos
    checks <- c(
      "metadata" %in% names(data),
      "dimensions" %in% names(data),
      "dico" %in% names(data$metadata),
      "name" %in% names(data$metadata),
      "last_updated" %in% names(data$metadata),
      "api_version" %in% names(data$metadata)
    )

    if (!all(checks)) {
      warning("JSON structure validation failed: missing required fields")
      return(FALSE)
    }

    # Check se normalized values estão no range correto
    # (implementar traversal recursivo se necessário)

    return(TRUE)
  }, error = function(e) {
    warning(glue("JSON validation error: {e$message}"))
    return(FALSE)
  })
}

# Export functions (se usar como módulo)
if (FALSE) { # Set TRUE se usar source() noutros scripts
  list(
    generate_municipality_json = generate_municipality_json,
    generate_index_json = generate_index_json,
    generate_indicators_metadata_json = generate_indicators_metadata_json,
    generate_hierarchy_json = generate_hierarchy_json,
    generate_sources_json = generate_sources_json,
    generate_bulk_json = generate_bulk_json,
    build_indicator = build_indicator,
    validate_municipality_json = validate_municipality_json
  )
}
