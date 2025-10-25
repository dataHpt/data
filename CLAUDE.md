# DataH Static API - Development Guide

## Project Mission
Build a static JSON API that exposes Portuguese municipal housing sustainability indicators, served via GitHub Pages with automated updates from INE (Instituto Nacional de Estatística).

## Core Principles

### 1. Static First
- Generate JSON files, serve via CDN (GitHub Pages)
- No server-side computation - all processing happens at build time
- Update on INE data release schedule, not on request
- Zero runtime dependencies = zero downtime

### 2. Transparency by Design
- Every indicator exposes **both** raw and normalized values
- Metadata includes sources, URLs, methodology
- Normalization methods are documented and reproducible
- Last update timestamp on every endpoint

### 3. API Versioning
- Use `/v1/` prefix for all endpoints
- Breaking changes require new version (`/v2/`)
- Maintain previous versions for 6 months minimum
- Document changes in `CHANGELOG.md`

### 4. Progressive Enhancement
- Don't build features until they're needed

---

## Project Structure

```
datah-api/
├── .github/
│   └── workflows/
│       └── update-data.yml          # Automated data updates
│
├── scripts/
│   ├── 01-fetch-data.R               # Fetch data from INE
│   ├── 02-normalize.R               # Normalize to 0-100 values
│   ├── 03-generate-json.R           # Transform to JSON structure
│   ├── 04-validate.R                # Data integrity checks
│   └── utils/
│       ├── ine-mappings.R           # Indicator → INE table mapping
│       └── json-schemas.R           # JSON structure definitions
│
├── data/
│   ├── v1/
│   │   ├── municipalities/          # 308 individual JSON files
│   │   │   ├── index.json          # List of all municipalities
│   │   │   ├── 0101.json           # Águeda
│   │   │   ├── 1106.json           # Lisboa
│   │   │   └── ...
│   │   ├── metadata/
│   │   │   ├── indicators.json     # Full indicator metadata
│   │   │   ├── hierarchy.json      # Dimension structure
│   │   │   └── sources.json        # INE sources and timestamps
│   │   └── bulk/
│   │       └── all-municipalities.json  # Single file with all data
│   └── LAST_UPDATE.json             # Global update timestamp
│
├── docs/
│   ├── index.html                   # API documentation site
│   ├── assets/
│   │   └── style.css
│   └── examples/
│       ├── javascript.md
│       ├── r.md
│       └── python.md
│
├── tests/
│   ├── test-json-structure.R       # Validate JSON schema
│   ├── test-data-integrity.R       # Check ranges, missing values
│   └── test-ine-fetch.R             # Mock INE fetches
│
├── CLAUDE.md                        # This file
├── README.md                        # Public documentation
├── CHANGELOG.md                     # Version history
└── .gitignore
```

---

## Data Architecture

### Hierarchical Structure
```
Dimension (2 total)
├─ Coesão Territorial
│  ├─ Sub-dimension
│  │  ├─ Dinâmicas Sociais
│  │     │  ├─ Desigualdade
│  │     │  └─ Acesso ao Mercado
│  │     │        ├─ Beneficiários RSI
│  │     │        └─ Taxa de esforço
│
└─ Sustentabilidade Ambiental
   ├─ Sub-dimension
   │  ├─ Eficiência Energética
   │  └─ Catástrofes Naturais
   │        └─ Indicator
```

### Data Flow Pipeline
```
INE API/Tables
    ↓ (01-fetch-data.R)
Raw Values (RDS)
    ↓ (02-normalize.R)
Normalized Values (RDS)
    ↓ (03-generate-json.R)
JSON Files (with hierarchy)
    ↓ (GitHub commit)
GitHub Pages (CDN)
    ↓
Svelte Frontend
    ↓
User defines weights → Calculates scores in browser
```

---

## JSON Structure Standards

### Municipality Endpoint
**URL**: `/v1/municipalities/{dico}.json`

```json
{
  "metadata": {
    "dico": "1106",
    "name": "Lisboa",
    "last_updated": "2025-10-25T10:30:00Z",
    "api_version": "1.0.0"
  },
  "dimensions": {
    "coesao_territorial": {
      "sub_dimensions": {
        "dinamicas_sociais": {
          "gavetas": {
            "desigualdade": {
              "indicators": {
                "beneficiarios_rsi": {
                  "normalized": 6.97,
                  "raw": 15.0,
                  "unit": "%"
                },
                "disparidade_ganho": {
                  "normalized": 27.0,
                  "raw": 10.5,
                  "unit": "%"
                }
              }
            },
            "isolamento": {
              "indicators": {
                "agregados_unipessoais": {
                  "normalized": 85.2,
                  "raw": 45.3,
                  "unit": "%"
                }
              }
            }
          }
        },
        "dinamicas_habitacao": {
          "gavetas": {
            "acesso_mercado": {
              "indicators": { }
            }
          }
        }
      }
    },
    "sustentabilidade_ambiental": {
      "sub_dimensions": { }
    }
  }
}
```

**IMPORTANT**: This structure maintains the hierarchy (Dimension → Sub-dimension → Gaveta → Indicators) but **does NOT include pre-calculated scores**. Scores for gavetas, sub-dimensions, and dimensions are calculated in the frontend (Svelte) based on user-defined weights. The API only exposes normalized and raw indicator values.

### Metadata Endpoint
**URL**: `/v1/metadata/indicators.json`

```json
{
  "version": "1.0.0",
  "last_updated": "2025-10-25T10:30:00Z",
  "indicators": [
    {
      "id": "beneficiarios_rsi",
      "name": "Beneficiários do RSI",
      "description": "Proporção da população beneficiária do Rendimento Social de Inserção",
      "dimension": "coesao_territorial",
      "sub_dimension": "dinamicas_sociais",
      "gaveta": "desigualdade",
      "unit": "%",
      "direction": "lower_is_better",
      "normalization": {
        "method": "min-max",
        "range": [0, 100],
        "inverted": true
      },
      "source": {
        "name": "INE",
        "year": 2023,
        "table_code": "XXXX",
        "url": "https://www.ine.pt/...",
        "fetch_date": "2025-10-25"
      }
    }
  ]
}
```

### Index Endpoint
**URL**: `/v1/municipalities/index.json`

```json
{
  "total": 308,
  "municipalities": [
    {
      "dico": "0101",
      "name": "Águeda",
      "url": "/v1/municipalities/0101.json"
    }
  ]
}
```

---

## R Development Guidelines

### Code Style
```r
# Use tidyverse conventions
library(tidyverse)

# Function naming: verb_noun
fetch_ine_table <- function(table_code) { }
normalize_indicator <- function(values, method = "min-max") { }

# Pipe for readability
data %>%
  filter(!is.na(value)) %>%
  mutate(normalized = normalize_indicator(value))

# Explicit arguments, no magic values
normalize_indicator(
  values = raw_values,
  method = "min-max",
  range = c(0, 100),
  invert = TRUE
)
```

### Error Handling
```r
# Fail fast with context
fetch_ine_indicator <- function(indicator_id, table_code) {
  if (is.null(table_code)) {
    stop(glue("Missing INE table code for indicator: {indicator_id}"))
  }

  result <- tryCatch(
    fetch_ine_table(table_code),
    error = function(e) {
      stop(glue("Failed to fetch {indicator_id} from table {table_code}: {e$message}"))
    }
  )

  return(result)
}
```

### Testing
```r
# Use testthat for validation
library(testthat)

test_that("Normalization produces 0-100 range", {
  raw <- c(10, 50, 90)
  norm <- normalize_indicator(raw, method = "min-max", range = c(0, 100))

  expect_true(all(norm >= 0 & norm <= 100))
  expect_equal(min(norm), 0)
  expect_equal(max(norm), 100)
})
```

### Caching & Performance
```r
# Cache INE fetches to avoid repeated calls
library(memoise)

fetch_ine_table_cached <- memoise(
  fetch_ine_table,
  cache = cache_filesystem(".cache/ine")
)

# Use arrow/parquet for intermediate storage (faster than RDS)
library(arrow)

write_parquet(indicators_data, "data-cache/indicators.parquet")
indicators_data <- read_parquet("data-cache/indicators.parquet")
```

---

## GitHub Actions Workflow

### Triggers
- **Manual**: Workflow dispatch (for testing)
- **Scheduled**: Monthly on the 1st (INE update cycle)
- **On push**: When scripts change (for CI testing)

### Environment
- R version: 4.3+
- Required packages: `tidyverse`, `jsonlite`, `glue`, `lubridate`, `httr`, `rvest`
- Caching: Cache R packages and INE fetches between runs

### Workflow Logic
```yaml
1. Setup R environment
2. Install dependencies (with caching)
3. Run data pipeline:
   - Fetch from INE
   - Normalize
   - Generate JSON
4. Run validation tests
5. If tests pass:
   - Commit JSON files
   - Push to main
   - GitHub Pages auto-deploys
6. If tests fail:
   - Stop workflow
   - Create issue with error log
```

---

## Data Quality Checks

### Pre-commit Validation
**Script**: `04-validate.R`

```r
validate_api_data <- function() {
  checks <- list()

  # 1. All municipalities present
  files <- list.files("data/v1/municipalities", pattern = "*.json")
  checks$municipalities <- length(files) == 308

  # 2. Valid JSON structure
  checks$json_valid <- all(
    map_lgl(files, ~jsonlite::validate(read_file(.x)))
  )

  # 3. Normalized values in range
  checks$ranges <- all_indicators %>%
    filter(normalized < 0 | normalized > 100) %>%
    nrow() == 0

  # 4. No missing critical values (check first indicator exists)
  checks$missing <- all_municipalities %>%
    filter(length(dimensions) == 0) %>%
    nrow() == 0

  # 5. Metadata completeness
  checks$metadata <- all(
    !is.na(metadata$indicators$source$url)
  )

  # Report
  if (!all(unlist(checks))) {
    failed <- names(checks)[!unlist(checks)]
    stop(glue("Validation failed: {paste(failed, collapse=', ')}"))
  }

  message("✓ All validation checks passed")
}
```

---

## INE Data Fetching Strategy

### Indicator Mapping
**File**: `utils/ine-mappings.R`

```r
# Master mapping of indicators to INE sources
ine_mappings <- tribble(
  ~indicator_id,           ~ine_table,  ~ine_variable,       ~year,
  "beneficiarios_rsi",     "0010245",   "Taxa (%)",          2023,
  "taxa_desemprego",       "0011234",   "Taxa desemprego",   2023,
  # ... 44 more indicators
)

# Function to fetch all indicators
fetch_all_indicators <- function(mappings) {
  mappings %>%
    pmap_dfr(~fetch_ine_indicator(
      indicator_id = ..1,
      table = ..2,
      variable = ..3,
      year = ..4
    ))
}
```

### Graceful Degradation
```r
# If INE fetch fails, use cached data with warning
fetch_with_fallback <- function(indicator_id, cache_path) {
  tryCatch(
    fetch_ine_indicator(indicator_id),
    error = function(e) {
      warning(glue("INE fetch failed for {indicator_id}, using cache"))
      read_rds(glue("{cache_path}/{indicator_id}.rds"))
    }
  )
}
```

---

## Versioning & Migration Strategy

### When to Bump Version

**v1.x → v1.y (Minor)**
- New endpoints added (backwards compatible)
- New fields in JSON (optional)
- Performance improvements
- Bug fixes

**v1.x → v2.0 (Major - Breaking)**
- JSON structure changes
- Endpoint URL changes
- Required fields removed
- Normalization methodology changes

### Migration Path
1. Develop v2 in parallel (`/v2/` folder)
2. Update docs with migration guide
3. Add deprecation warnings to v1 (6 months notice)
4. Maintain both versions during transition
5. Archive v1 after deprecation period

---

## Documentation Requirements

### README.md
- Quick start example
- Installation instructions
- Link to full docs
- Changelog link

### docs/index.html
- Interactive API explorer
- All endpoints documented
- Code examples (JS, R, Python)
- Data dictionary (46 indicators explained)
- Visual hierarchy diagram

### CHANGELOG.md
```markdown
# Changelog

## [1.0.0] - 2025-10-25
### Added
- Initial release
- 308 municipality endpoints
- 46 indicators across 2 dimensions
- Metadata endpoints (indicators, hierarchy, sources)
- Bulk endpoint (all municipalities in one file)
```

---

## Testing Strategy

### Unit Tests
- Normalization functions
- JSON structure generation
- INE data parsing

### Integration Tests
- Full pipeline execution
- GitHub Actions workflow (mock)

### Validation Tests
- JSON schema compliance
- Data integrity (ranges, missing values)
- Municipality count (308)
- Indicator count (46)

---

## Common Tasks

### Add New Indicator
1. Add to `ine-mappings.R`
2. Update metadata JSON schema
3. Re-run pipeline
4. Update documentation
5. Bump version to v1.x+1

### Update Data from INE
```bash
# Manual trigger
gh workflow run update-data.yml

# Check status
gh run list --workflow=update-data.yml
```

### Local Development
```r
# Run full pipeline locally
source("scripts/01-fetch-data.R")
source("scripts/02-normalize.R")
source("scripts/03-generate-json.R")
source("scripts/04-validate.R")

# Serve locally for testing
servr::httd("data")
# Visit: http://localhost:4321/v1/municipalities/1106.json
```

---

## Decision Log

### Why Static API?
- Simpler than dynamic (Plumber)
- Zero server costs (GitHub Pages free)
- Ultra-fast (CDN)
- No scaling issues
- Data updates monthly (not real-time)

### Why JSON over CSV?
- Hierarchical structure (dimensions → gavetas → indicators)
- Metadata embedded
- Better for web consumption
- Type safety

### Why R over Python?
- Team familiarity
- Better INE data access packages
- Existing normalization code
- Tidyverse for clean pipelines

### Why GitHub Pages over Netlify/Vercel?
- Already using GitHub
- Free forever (public repos)
- Simple workflow integration
- No vendor lock-in

---

## Future Enhancements (Post v1.0)

### v1.1
- [ ] GeoJSON endpoints for mapping
- [ ] Comparison endpoint: `/compare?municipalities=lisboa,porto`

### v1.2
- [ ] Time series data (historical)
- [ ] Percentile rankings
- [ ] Regional aggregations (NUTS2, NUTS3)

### v2.0
- [ ] GraphQL layer (if needed)
- [ ] Real-time INE webhook updates

---

## Contact & Maintenance

**Primary Maintainer**: Rui Barros (DataH)
**Organization**: DataH - Dynamic Analysis for Territorial Approaches to Housing
**Repository**: `github.com/dataHpt/data`
**Website**: https://www.datah.pt/
**Issues**: GitHub Issues
**Updates**: Monthly (aligned with INE releases)

---

## Notes for Future Developers

- **Don't over-engineer**: v1.0 serves one use case (simulator). Build for that.
- **INE is flaky**: Always cache, always have fallbacks
- **Validate everything**: Bad data in production = broken simulators
- **Document changes**: Future you will thank present you
- **Keep it fast**: Each municipality JSON should be <50KB

This is a **data product**, not a web service. Treat it like a publication: accuracy > speed, clarity > cleverness.
