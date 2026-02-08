#!/usr/bin/env Rscript
# 06-generate-descriptions.R
# Multi-agent LLM description generator for municipality profiles
#
# Uses a 6-stage prompt chain with enriched comparative data (rankings,
# percentiles, medians) so agents can make statements like "Lisboa has
# the highest housing prices in the country".
#
# Workflow:
#   Pre-compute comparative stats (R) →
#   Stage 1a: Social & Territory Analyst →
#   Stage 1b: Economy & Housing Analyst →
#   Stage 1c: Climate & Risks Analyst →
#   Stage 2: Storyteller →
#   Stage 3: Critical Editor →
#   Stage 4: Editorial Polish →
#   data-cache/municipality-descriptions.csv
#
# Usage:
#   Rscript scripts/06-generate-descriptions.R          # All 308 municipalities
#   Rscript scripts/06-generate-descriptions.R --test    # Only 3 test municipalities

library(tidyverse)
library(jsonlite)
library(glue)
library(httr2)
library(uuid)

# ============================================================================
# 0. Configuration
# ============================================================================

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
TEST_MODE <- "--test" %in% args

# Load .env
env_path <- ".env"
if (file.exists(env_path)) {
  env_lines <- readLines(env_path, warn = FALSE)
  for (line in env_lines) {
    line <- trimws(line)
    if (nchar(line) == 0 || startsWith(line, "#")) next
    parts <- strsplit(line, "=", fixed = TRUE)[[1]]
    if (length(parts) >= 2) {
      key <- trimws(parts[1])
      value <- trimws(paste(parts[-1], collapse = "="))
      do.call(Sys.setenv, setNames(list(value), key))
    }
  }
}

API_KEY <- Sys.getenv("IAEDU_API_KEY")
CHANNEL_ID <- Sys.getenv("IAEDU_CHANNEL_ID")
API_ENDPOINT <- Sys.getenv("IAEDU_ENDPOINT")

if (API_KEY == "" || CHANNEL_ID == "" || API_ENDPOINT == "") {
  stop("Missing API credentials. Check .env file (IAEDU_API_KEY, IAEDU_CHANNEL_ID, IAEDU_ENDPOINT)")
}

# Paths
NORMALIZED_DATA_PATH <- "data-cache/all-indicators-normalized.csv"
MUNICIPALITIES_PATH <- "data-cache/municipalities.csv"
OUTPUT_CSV <- "data-cache/municipality-descriptions.csv"

# Test municipalities
TEST_DICOS <- c("1106", "0101", "0401")  # Lisboa, Águeda, Alfândega da Fé

# Delays (seconds)
DELAY_BETWEEN_STAGES <- 1
DELAY_BETWEEN_MUNICIPALITIES <- 2

message("=" , strrep("=", 70))
message(glue("GENERATING MUNICIPALITY DESCRIPTIONS ({if (TEST_MODE) '3 TEST' else '308 FULL'} MODE)"))
message(strrep("=", 71), "\n")

# ============================================================================
# 1. Load Data
# ============================================================================

message("Loading data...")

# Load indicator mappings
source("scripts/utils/ine-mappings.R")

# Load normalized data
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

# Load municipality names
municipality_names <- read_csv(
  MUNICIPALITIES_PATH,
  col_types = cols(dico = col_character(), name = col_character()),
  show_col_types = FALSE
)

message(glue("  Loaded {nrow(normalized_data)} data rows, {nrow(municipality_names)} municipalities\n"))

# ============================================================================
# 2. Pre-compute Comparative Statistics
# ============================================================================

message("Pre-computing comparative statistics (rankings, percentiles, medians)...")

# Join with indicator metadata for labels
data_enriched <- normalized_data %>%
  left_join(
    ine_indicator_mappings %>%
      select(indicator_id, indicator_number, indicator_name, frontend_name,
             dimension, sub_dimension, unit, direction),
    by = "indicator_id"
  )

# Compute rankings, percentiles, medians per indicator
comparative_stats <- data_enriched %>%
  group_by(indicator_id) %>%
  mutate(
    # Rank: 1 = highest raw value
    rank = rank(-raw_value, ties.method = "min", na.last = "keep"),
    total = sum(!is.na(raw_value)),
    percentile = round((1 - (rank - 1) / (total - 1)) * 100, 1),
    median_val = median(raw_value, na.rm = TRUE)
  ) %>%
  ungroup()

# Generate position labels
comparative_stats <- comparative_stats %>%
  mutate(
    position_label = case_when(
      is.na(rank) ~ "sem dados",
      rank == 1 ~ "o mais alto do pa\u00eds",
      rank == total ~ "o mais baixo do pa\u00eds",
      rank <= 10 ~ glue("{rank}\u00ba mais alto do pa\u00eds (top 10)"),
      rank >= total - 9 ~ glue("{rank}\u00ba de {total} (bottom 10)"),
      percentile >= 75 ~ glue("{rank}\u00ba de {total} \u2014 acima do percentil 75"),
      percentile <= 25 ~ glue("{rank}\u00ba de {total} \u2014 abaixo do percentil 25"),
      TRUE ~ glue("{rank}\u00ba de {total}")
    )
  )

# Compute "extremeness" score: how far from the median rank (154) each indicator is
comparative_stats <- comparative_stats %>%
  mutate(
    extremeness = abs(rank - (total / 2))
  )

message(glue("  Computed rankings for {n_distinct(comparative_stats$indicator_id)} indicators\n"))

# ============================================================================
# 3. Helper: Format Data Briefing
# ============================================================================

# Sub-dimension groupings for the 3 analyst stages
social_territory_subs <- c("socio_demograficas", "socio_economicas")
economy_housing_subs <- c("socio_territoriais", "acesso_habitacao", "parque_habitacional")
climate_risks_subs <- c("habitacao_energia", "habitat", "riscos_naturais")

format_number_pt <- function(x, unit) {
  if (is.na(x)) return("sem dados")
  formatted <- if (abs(x) >= 1000) {
    formatC(x, format = "f", digits = 1, big.mark = ".", decimal.mark = ",")
  } else {
    formatC(x, format = "f", digits = 2, big.mark = ".", decimal.mark = ",")
  }
  # Trim trailing zeros after decimal
  formatted <- sub("(,\\d*?)0+$", "\\1", formatted)
  formatted <- sub(",$", "", formatted)
  paste0(formatted, " ", unit)
}

format_briefing_section <- function(mun_data, sub_dims, section_title) {
  section_data <- mun_data %>%
    filter(sub_dimension %in% sub_dims) %>%
    filter(!is.na(raw_value)) %>%
    arrange(sub_dimension, indicator_number)

  if (nrow(section_data) == 0) return("")

  lines <- c()
  for (sd in unique(section_data$sub_dimension)) {
    sd_data <- section_data %>% filter(sub_dimension == sd)
    sd_label <- switch(sd,
      "socio_demograficas" = "S\u00d3CIO-DEMOGR\u00c1FICAS",
      "socio_economicas" = "S\u00d3CIO-ECON\u00d3MICAS",
      "socio_territoriais" = "S\u00d3CIO-TERRITORIAIS",
      "acesso_habitacao" = "ACESSO \u00c0 HABITA\u00c7\u00c3O",
      "parque_habitacional" = "PARQUE HABITACIONAL",
      "habitacao_energia" = "HABITA\u00c7\u00c3O E ENERGIA",
      "habitat" = "HABITAT",
      "riscos_naturais" = "RISCOS NATURAIS",
      toupper(sd)
    )
    lines <- c(lines, glue("\n{sd_label}:"))

    for (j in 1:nrow(sd_data)) {
      row <- sd_data[j, ]
      raw_fmt <- format_number_pt(row$raw_value, row$unit)
      median_fmt <- format_number_pt(row$median_val, row$unit)
      lines <- c(lines, glue("- {row$frontend_name}: {raw_fmt} ({row$position_label}. Mediana: {median_fmt})"))
    }
  }

  paste(lines, collapse = "\n")
}

format_top_extremes <- function(mun_data, n = 5) {
  top <- mun_data %>%
    filter(!is.na(rank)) %>%
    arrange(desc(extremeness)) %>%
    head(n)

  if (nrow(top) == 0) return("")

  lines <- c("\nOS 5 INDICADORES MAIS EXTREMOS DESTE MUNIC\u00cdPIO:")
  for (i in 1:nrow(top)) {
    row <- top[i, ]
    raw_fmt <- format_number_pt(row$raw_value, row$unit)
    lines <- c(lines, glue("{i}. {row$frontend_name}: {raw_fmt} \u2192 {row$position_label}"))
  }

  paste(lines, collapse = "\n")
}

# ============================================================================
# 4. API Call Function (SSE Streaming)
# ============================================================================

call_agent_api <- function(message_text, thread_id) {
  resp <- tryCatch({
    req <- request(API_ENDPOINT) %>%
      req_headers(
        "x-api-key" = API_KEY
      ) %>%
      req_body_multipart(
        message = message_text,
        thread_id = thread_id,
        channel_id = CHANNEL_ID,
        user_info = toJSON(list(name = "DataH Pipeline", email = "datah@publico.pt"), auto_unbox = TRUE)
      ) %>%
      req_timeout(120)

    resp <- req_perform(req)
    body <- resp_body_string(resp)
    parse_streaming_response(body)
  },
  error = function(e) {
    warning(glue("API call failed: {e$message}"))
    return(NULL)
  })

  return(resp)
}

parse_streaming_response <- function(body) {
  # Response is newline-separated JSON objects with type field
  lines <- strsplit(body, "\n")[[1]]
  lines <- lines[nchar(trimws(lines)) > 0]

  full_text <- ""

  for (line in lines) {
    parsed <- tryCatch(fromJSON(trimws(line), simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(parsed)) next

    if (!is.null(parsed$type)) {
      if (parsed$type == "token" && !is.null(parsed$content)) {
        full_text <- paste0(full_text, parsed$content)
      } else if (parsed$type == "message" && !is.null(parsed$content$content)) {
        # Final message contains the complete text — use it if we missed tokens
        if (full_text == "") {
          full_text <- parsed$content$content
        }
      }
    }
  }

  return(trimws(full_text))
}

# ============================================================================
# 5. Stage Prompts
# ============================================================================

prompt_stage1a <- function(name, enriched_data, top_extremes) {
  glue("
\u00c9s um analista de dados demogr\u00e1ficos e territoriais. Analisa os dados do munic\u00edpio de {name}
e identifica os 3-4 factos mais relevantes. Usa SEMPRE linguagem comparativa
(\"o mais alto do pa\u00eds\", \"acima da mediana nacional\", \"no top 10\").

{enriched_data}

{top_extremes}

Escreve 3-4 bullet points com os factos mais not\u00e1veis.
Cada bullet deve incluir o valor concreto e a posi\u00e7\u00e3o relativa.")
}

prompt_stage1b <- function(name, enriched_data, top_extremes) {
  glue("
\u00c9s um analista econ\u00f3mico e de habita\u00e7\u00e3o. Analisa os dados do munic\u00edpio de {name}
e identifica os 3-4 factos mais relevantes sobre economia, acesso \u00e0 habita\u00e7\u00e3o
e estado do parque habitacional.

{enriched_data}

{top_extremes}

Escreve 3-4 bullet points com os factos mais not\u00e1veis.
Cada bullet deve incluir o valor concreto e a posi\u00e7\u00e3o relativa.")
}

prompt_stage1c <- function(name, enriched_data, top_extremes) {
  glue("
\u00c9s um analista ambiental e de riscos naturais. Analisa os dados do munic\u00edpio de {name}
e identifica os 2-3 factos mais relevantes sobre energia, ambiente e riscos.
Ignora riscos com valores zero ou muito baixos.

{enriched_data}

{top_extremes}

Escreve 2-3 bullet points com os factos mais not\u00e1veis.
Cada bullet deve incluir o valor concreto e a posi\u00e7\u00e3o relativa.")
}

prompt_stage2 <- function(name, stage1a, stage1b, stage1c) {
  glue("
\u00c9s jornalista de dados. Tens tr\u00eas an\u00e1lises do munic\u00edpio de {name}.
Escreve um par\u00e1grafo narrativo (5-6 frases) que conte a \"hist\u00f3ria\" deste munic\u00edpio.

O que o define? Qual \u00e9 o \u00e2ngulo mais interessante? Qual \u00e9 o desafio central
em termos de sustentabilidade habitacional?

AN\u00c1LISE SOCIAL:
{stage1a}

AN\u00c1LISE ECON\u00d3MICA E HABITACIONAL:
{stage1b}

AN\u00c1LISE AMBIENTAL E RISCOS:
{stage1c}

Regras:
- Integra as tr\u00eas an\u00e1lises numa narrativa coerente
- Mant\u00e9m os n\u00fameros concretos e as compara\u00e7\u00f5es nacionais
- Identifica o fio condutor \u2014 o que liga estes dados
- Portugu\u00eas europeu, linguagem acess\u00edvel")
}

prompt_stage3 <- function(name, stage2_output) {
  glue("
\u00c9s o editor-chefe de um projeto de jornalismo de dados. Edita este texto sobre {name}.

RASCUNHO:
{stage2_output}

ANTES de editar, responde mentalmente:
- Este texto podia aplicar-se a qualquer munic\u00edpio? Se sim, falta-lhe identidade.
- Qual \u00e9 o facto mais surpreendente ou distintivo? Deve abrir o texto.
- H\u00e1 frases gen\u00e9ricas (\"enfrenta desafios\", \"apresenta valores\") que podem ser cortadas?

REGRAS:
- M\u00e1ximo 3-4 frases (idealmente 3)
- Abre com o facto mais marcante \u2014 o que surpreende
- Mant\u00e9m n\u00fameros concretos e compara\u00e7\u00f5es nacionais
- Cada frase acrescenta informa\u00e7\u00e3o nova
- Corta generalidades, mant\u00e9m especificidades
- N\u00c3O comeces com \"{name} \u00e9 um munic\u00edpio\"
- Portugu\u00eas europeu

Escreve APENAS o texto final, sem explica\u00e7\u00f5es.")
}

prompt_stage4 <- function(name, stage3_output) {
  glue("
Reescreve este texto como uma DESCRI\u00c7\u00c3O DO MUNIC\u00cdPIO de {name} para um painel interativo
de sustentabilidade habitacional. O texto deve ler-se como um perfil do lugar \u2014 quem l\u00e1 vive,
como se vive, e quais s\u00e3o os desafios \u2014 e n\u00e3o como um relat\u00f3rio de dados.

Texto base:
{stage3_output}

O resultado deve:
1. Descrever {name} como um lugar \u2014 que tipo de munic\u00edpio \u00e9, o que o caracteriza
2. Integrar os dados naturalmente na descri\u00e7\u00e3o (n\u00e3o como uma lista de factos)
3. Identificar os desafios de sustentabilidade habitacional de forma clara
4. Ter no m\u00e1ximo 3-4 frases
5. Usar linguagem clara e acess\u00edvel, tom informativo mas envolvente
6. Manter n\u00fameros concretos e compara\u00e7\u00f5es nacionais quando relevantes
7. Portugu\u00eas europeu

Bom exemplo:
'Com mais de 5.700 habitantes por km\u00b2 e os pre\u00e7os de habita\u00e7\u00e3o mais altos do pa\u00eds (4.340\u20ac/m\u00b2),
Lisboa \u00e9 onde o acesso \u00e0 habita\u00e7\u00e3o \u00e9 mais dif\u00edcil \u2014 o arrendamento consome 77% do rendimento
das fam\u00edlias. A capital concentra poder de compra e popula\u00e7\u00e3o qualificada, mas tamb\u00e9m
a maior desigualdade de rendimentos a n\u00edvel nacional. Ao risco s\u00edsmico elevado somam-se
as maiores emiss\u00f5es de carbono dos transportes, pressionando a sustentabilidade urbana.'

Mau exemplo:
'O munic\u00edpio apresenta valores elevados nos indicadores de acesso \u00e0 habita\u00e7\u00e3o.
Os desafios s\u00e3o significativos em termos de sustentabilidade.'

Escreve APENAS a descri\u00e7\u00e3o final, em texto corrido sem formata\u00e7\u00e3o markdown.")
}

# ============================================================================
# 6. Process One Municipality (6 stages)
# ============================================================================

process_municipality <- function(dico, name, mun_stats) {
  thread_id <- UUIDgenerate()
  message(glue("  [{dico}] {name} (thread: {substr(thread_id, 1, 8)}...)"))

  # Prepare enriched data sections
  social_data <- format_briefing_section(mun_stats, social_territory_subs, "DADOS SOCIAIS")
  economy_data <- format_briefing_section(mun_stats, economy_housing_subs, "DADOS ECON\u00d3MICOS E HABITACIONAIS")
  climate_data <- format_briefing_section(mun_stats, climate_risks_subs, "DADOS AMBIENTAIS E RISCOS")
  top_extremes <- format_top_extremes(mun_stats)

  # Stage 1a: Social & Territory Analyst
  message(glue("    Stage 1a: Social & Territory..."))
  stage1a <- call_agent_api(
    prompt_stage1a(name, social_data, top_extremes),
    thread_id
  )
  if (is.null(stage1a) || stage1a == "") {
    warning(glue("Stage 1a failed for {name}"))
    return(NULL)
  }
  Sys.sleep(DELAY_BETWEEN_STAGES)

  # Stage 1b: Economy & Housing Analyst
  message(glue("    Stage 1b: Economy & Housing..."))
  stage1b <- call_agent_api(
    prompt_stage1b(name, economy_data, top_extremes),
    thread_id
  )
  if (is.null(stage1b) || stage1b == "") {
    warning(glue("Stage 1b failed for {name}"))
    return(NULL)
  }
  Sys.sleep(DELAY_BETWEEN_STAGES)

  # Stage 1c: Climate & Risks Analyst
  message(glue("    Stage 1c: Climate & Risks..."))
  stage1c <- call_agent_api(
    prompt_stage1c(name, climate_data, top_extremes),
    thread_id
  )
  if (is.null(stage1c) || stage1c == "") {
    warning(glue("Stage 1c failed for {name}"))
    return(NULL)
  }
  Sys.sleep(DELAY_BETWEEN_STAGES)

  # Stage 2: Storyteller
  message(glue("    Stage 2: Storyteller..."))
  stage2 <- call_agent_api(
    prompt_stage2(name, stage1a, stage1b, stage1c),
    thread_id
  )
  if (is.null(stage2) || stage2 == "") {
    warning(glue("Stage 2 failed for {name}"))
    return(NULL)
  }
  Sys.sleep(DELAY_BETWEEN_STAGES)

  # Stage 3: Critical Editor
  message(glue("    Stage 3: Critical Editor..."))
  stage3 <- call_agent_api(
    prompt_stage3(name, stage2),
    thread_id
  )
  if (is.null(stage3) || stage3 == "") {
    warning(glue("Stage 3 failed for {name}"))
    return(NULL)
  }
  Sys.sleep(DELAY_BETWEEN_STAGES)

  # Stage 4: Editorial Polish
  message(glue("    Stage 4: Editorial Polish..."))
  stage4 <- call_agent_api(
    prompt_stage4(name, stage3),
    thread_id
  )
  if (is.null(stage4) || stage4 == "") {
    warning(glue("Stage 4 failed for {name}"))
    return(NULL)
  }

  # Strip markdown formatting (bold, italic)
  stage4 <- gsub("\\*\\*(.+?)\\*\\*", "\\1", stage4)
  stage4 <- gsub("\\*(.+?)\\*", "\\1", stage4)
  stage4 <- trimws(stage4)

  message(glue("    \u2713 Done: {substr(stage4, 1, 80)}..."))
  return(stage4)
}

# ============================================================================
# 7. Main Loop
# ============================================================================

# Determine which municipalities to process
if (TEST_MODE) {
  target_dicos <- TEST_DICOS
  message(glue("TEST MODE: Processing {length(target_dicos)} municipalities\n"))
} else {
  target_dicos <- sort(unique(normalized_data$dico))
  message(glue("FULL MODE: Processing {length(target_dicos)} municipalities\n"))
}

# Load existing results (for resume support)
existing_results <- tibble(dico = character(), name = character(),
                           description = character(), status = character())

if (file.exists(OUTPUT_CSV) && !TEST_MODE) {
  existing_results <- read_csv(OUTPUT_CSV, show_col_types = FALSE,
                               col_types = cols(.default = col_character()))
  completed_dicos <- existing_results %>%
    filter(status == "generated") %>%
    pull(dico)
  target_dicos <- setdiff(target_dicos, completed_dicos)
  message(glue("  Resuming: {length(completed_dicos)} already done, {length(target_dicos)} remaining\n"))
}

# Process municipalities
total <- length(target_dicos)
success_count <- 0
fail_count <- 0

for (i in seq_along(target_dicos)) {
  dico <- target_dicos[i]

  # Get municipality name
  mun_name <- municipality_names %>%
    filter(dico == !!dico) %>%
    pull(name) %>%
    first()

  if (is.na(mun_name)) {
    warning(glue("No name found for dico {dico}, skipping"))
    next
  }

  message(glue("\n[{i}/{total}] Processing {mun_name} ({dico})"))

  # Get this municipality's comparative stats
  mun_stats <- comparative_stats %>%
    filter(dico == !!dico)

  # Run 6-stage pipeline
  description <- tryCatch(
    process_municipality(dico, mun_name, mun_stats),
    error = function(e) {
      warning(glue("Error processing {mun_name}: {e$message}"))
      return(NULL)
    }
  )

  if (!is.null(description) && nchar(description) > 0) {
    # Append result
    new_row <- tibble(
      dico = dico,
      name = mun_name,
      description = description,
      status = "generated"
    )
    existing_results <- bind_rows(existing_results, new_row)
    success_count <- success_count + 1
  } else {
    # Record failure
    new_row <- tibble(
      dico = dico,
      name = mun_name,
      description = NA_character_,
      status = "failed"
    )
    existing_results <- bind_rows(existing_results, new_row)
    fail_count <- fail_count + 1
  }

  # Save after each municipality (crash-safe)
  write_csv(existing_results, OUTPUT_CSV)

  # Delay between municipalities
  if (i < total) {
    Sys.sleep(DELAY_BETWEEN_MUNICIPALITIES)
  }
}

# ============================================================================
# 8. Summary
# ============================================================================

message("\n", strrep("=", 71))
message("DESCRIPTION GENERATION COMPLETE")
message(strrep("=", 71))

message(glue("
Results:
  \u2713 Successful: {success_count}
  \u2717 Failed:     {fail_count}
  Total:      {success_count + fail_count}

Output: {OUTPUT_CSV}

{if (fail_count > 0) glue('Failed municipalities can be retried by running the script again (resume support).\n') else ''}
Next steps:
  1. Review descriptions in {OUTPUT_CSV}
  2. Run: Rscript scripts/04-generate-json.R  (inject into JSONs)
  3. Run: Rscript scripts/05-validate.R       (validate)
"))
