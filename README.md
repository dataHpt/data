# DataH Static API

**Dynamic Analysis for Territorial Approaches to Housing**

API estática de indicadores de sustentabilidade habitacional para municípios portugueses.

[![Website](https://img.shields.io/badge/website-datah.pt-orange)](https://www.datah.pt/)
[![API](https://img.shields.io/badge/API-v1.0.0-blue)](https://datahpt.github.io/data/)
[![Data Coverage](https://img.shields.io/badge/coverage-96.91%25-success)](https://datahpt.github.io/data/LAST_UPDATE.json)

---

## 🎯 Sobre o Projeto DataH

O **DataH** nasceu com o objetivo de contribuir para a reflexão e para a construção de soluções mais informadas, eficazes e justas nas políticas públicas de habitação em Portugal.

A partir de uma abordagem colaborativa e baseada em dados, o DataH procura apoiar a administração pública no desenho, implementação e monitorização de políticas de habitação mais alinhadas com a realidade dos territórios, com os compromissos nacionais e as grandes agendas internacionais.

**Esta API** disponibiliza dados estruturados sobre sustentabilidade habitacional para os **308 municípios portugueses**, organizados em dimensões que refletem desafios territoriais e ambientais.

---

## 🚀 Quick Start

```javascript
// Obter dados de Lisboa
fetch('https://datahpt.github.io/data/v1/municipalities/1106.json')
  .then(res => res.json())
  .then(data => {
    console.log(data.metadata.name); // "Lisboa"
    console.log(data.dimensions.coesao_territorial);
  });
```

---

## 📊 Dados Disponíveis

- **308 municípios** portugueses (cobertura total)
- **41 indicadores** operacionais (91% do planeado)
- **2 dimensões principais**:
  - **Coesão Territorial**: Dinâmicas sociais e habitacionais
  - **Sustentabilidade Ambiental**: Eficiência energética e riscos climáticos
- Valores **normalizados (0-100)** e **raw** para cada indicador
- **3 fontes de dados**: INE, DGT Observatório, dados estáticos
- Atualização **mensal** (sincronizada com releases do INE)

---

## 🔗 Endpoints da API

### 📍 Município Individual
```
GET /v1/municipalities/{dico}.json
```
**Exemplo**: [/v1/municipalities/1106.json](https://datahpt.github.io/data/v1/municipalities/1106.json) (Lisboa)

Retorna dados completos do município com estrutura hierárquica.

### 📋 Lista de Municípios
```
GET /v1/municipalities/index.json
```
Retorna lista completa com códigos DICO, nomes e URLs.

### 💾 Download Completo (Bulk)
```
GET /v1/bulk/all-municipalities.json
```
Ficheiro único com todos os 308 municípios (~2MB). Ideal para análise offline.

### 📥 Downloads CSV
```
GET /v1/downloads/raw-data.csv               # Formato longo, valores originais
GET /v1/downloads/normalized-data.csv        # Formato longo, valores 0-100
GET /v1/downloads/raw-data-wide.csv          # Formato largo, valores originais
GET /v1/downloads/normalized-data-wide.csv   # Formato largo, valores 0-100
```
Perfeito para Excel, R, Python, análise estatística.

### 📖 Metadata
```
GET /v1/metadata/indicators.json   # Detalhes completos dos 41 indicadores
GET /v1/metadata/hierarchy.json    # Estrutura: Dimensão → Sub-dimensão → Gaveta
GET /v1/metadata/sources.json      # Fontes (INE, DGT) e timestamps
GET /LAST_UPDATE.json              # Timestamp global e estatísticas
```

---

## 🏗️ Estrutura dos Dados

### Hierarquia
```
Dimensão
 └─ Sub-dimensão
     └─ Gaveta
         └─ Indicadores
             ├─ normalized (0-100)
             ├─ raw (valor original)
             └─ unit (unidade)
```

### Exemplo de Resposta (Lisboa)
```json
{
  "metadata": {
    "dico": "1106",
    "name": "Lisboa",
    "last_updated": "2025-10-25T21:00:14Z",
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
                  "normalized": 76.04,
                  "raw": 36.46,
                  "unit": "%"
                }
              }
            }
          }
        }
      }
    }
  }
}
```

---

## 📖 Documentação

### Para Utilizadores da API
👉 **[Documentação Interativa](https://datahpt.github.io/data/docs/)** (em desenvolvimento)

- Referência completa de endpoints
- Exemplos em JavaScript, R e Python
- Dicionário de indicadores
- Metodologia de normalização

---

## 🛠️ Desenvolvimento Local

### Requisitos
- R >= 4.3
- Pacotes: `tidyverse`, `jsonlite`, `glue`, `lubridate`, `httr`

### Setup Inicial
```bash
# Clonar repositório
git clone https://github.com/dataHpt/data.git
cd data

# Instalar dependências R
Rscript init_renv.R
```

### Executar Pipeline Completo
```bash
# Opção 1: Script master
Rscript run-pipeline.R

# Opção 2: Scripts individuais
Rscript scripts/02-integrate-all-data.R  # Integração (auto + static)
Rscript scripts/03-normalize.R           # Normalização (0-100)
Rscript scripts/04-generate-json.R       # Geração JSON + CSV
Rscript scripts/05-validate.R            # Validação
```

### Servir Localmente
```r
# Em R console
servr::httd("data")
# Aceder: http://localhost:4321/v1/municipalities/1106.json
```

---

## 🤝 Contribuir

Contribuições são bem-vindas! Formas de contribuir:

1. **Reportar problemas**: [GitHub Issues](https://github.com/dataHpt/data/issues)
2. **Sugerir indicadores**: Abrir issue com proposta
3. **Melhorar documentação**: Pull requests
4. **Adicionar exemplos**: Casos de uso em `docs/examples/`

### Guidelines
- Seguir estrutura existente
- Testar alterações localmente
- Documentar novos indicadores

---

## 📅 Atualizações

- **Frequência**: Mensal (dia 1 de cada mês)
- **Fonte primária**: INE (Instituto Nacional de Estatística)
- **Automatização**: GitHub Actions 

---

## 📊 Estatísticas da API

| Métrica | Valor |
|---------|-------|
| **Municípios** | 308 (100% de Portugal) |
| **Indicadores** | 41 operacionais |
| **Cobertura** | 96.91% |
| **Tamanho total** | 6.0 MB |
| **Ficheiros JSON** | 312 |
| **Ficheiros CSV** | 4 |
| **Última atualização** | 2025-10-25 |

---

## 🌐 Sobre o DataH

**DataH** - Dynamic Analysis for Territorial Approaches to Housing

O DataH é um projeto de investigação com a referência 2024.07312.IACDC/2024 e o DOI [https://doi.org/10.54499/2024.07312.IACDC](https://doi.org/10.54499/2024.07312.IACDC), apoiado pela medida RE-C05 .i08.M04 — "Apoiar o lançamento de um programa de projetos de I&D orientado para o desenvolvimento e implementação de sistemas avançados de cibersegurança, inteligência artificial e ciência de dados na administração pública", do Plano de Recuperação e Resiliência (PRR), enquadrado no contrato de financiamento celebrado entre a Estrutura de Missão Recuperar Portugal (EMRP) e a Fundação para a Ciência e Tecnologia I.P. (FCT).

**Website**: [www.datah.pt](https://www.datah.pt/)

---

## 📜 Licença

- **Dados**: Creative Commons Attribution 4.0 International (CC BY 4.0)
- **Código**: MIT License

Os dados são agregados de fontes públicas (INE, DGT). Ao utilizar esta API, cita:

```
DataH (2025). DataH Static API - Indicadores de Sustentabilidade Habitacional.
https://github.com/dataHpt/data
DOI: 10.54499/2024.07312.IACDC
```

---

## 📧 Contacto

**Equipa DataH**
- Website: [www.datah.pt](https://www.datah.pt/)
- GitHub: [@dataHpt](https://github.com/dataHpt)
- Issues: [github.com/dataHpt/data/issues](https://github.com/dataHpt/data/issues)

---

**Versão API**: `v1.0.0`
**Última atualização**: `2025-10-25`
**Status**: ✅ Production Ready
