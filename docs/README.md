# DataH API Documentation

This directory contains complete API documentation and developer guides.

## 📚 Documentation Structure

### Public API Documentation
- **[index.html](index.html)** - Interactive API documentation website
  - Quick start guide
  - Complete endpoint reference
  - Data structure examples
  - Code examples in JavaScript, Python, and R

### Technical Guides

#### Core Implementation
- **[INE_API_IMPLEMENTATION.md](INE_API_IMPLEMENTATION.md)** - INE API v2 integration details
  - API authentication and endpoints
  - Dimension filtering (dim3, dim4)
  - NUTS 2024 mapping strategy
  - Error handling and retry logic

- **[MULTI_SOURCE_ARCHITECTURE.md](MULTI_SOURCE_ARCHITECTURE.md)** - Multi-source data architecture
  - INE API integration (17 indicators)
  - DGT Observatório integration (2 indicators)
  - Static CSV integration (22 indicators)
  - Data flow and integration strategy

#### Developer Guides
- **[EDITING_INE_MAPPINGS.md](EDITING_INE_MAPPINGS.md)** - How to edit indicator mappings
  - CSV structure and columns
  - Adding new indicators
  - Dimension filter syntax
  - Validation and testing

- **[HOW_TO_FIND_INE_CODES.md](HOW_TO_FIND_INE_CODES.md)** - Finding INE indicator codes
  - Navigating INE Base de Dados
  - Extracting 7-digit codes
  - Verifying data availability
  - Common pitfalls

#### Data Strategy
- **[DATA_FRESHNESS_STRATEGY.md](DATA_FRESHNESS_STRATEGY.md)** - Data update strategy
  - INE release schedule
  - Automated update workflows
  - Cache invalidation
  - Version management

### Code Examples
Located in `examples/`:
- **[javascript.md](examples/javascript.md)** - JavaScript/TypeScript examples
- **[python.md](examples/python.md)** - Python examples
- **[r.md](examples/r.md)** - R examples

### Assets
- **[assets/style.css](assets/style.css)** - Styling for index.html

## 🚀 Quick Links

### For API Users
Start with **[index.html](index.html)** - Complete API reference with interactive examples

### For Developers
1. **Understanding the architecture**: [MULTI_SOURCE_ARCHITECTURE.md](MULTI_SOURCE_ARCHITECTURE.md)
2. **Adding indicators**: [EDITING_INE_MAPPINGS.md](EDITING_INE_MAPPINGS.md)
3. **Finding INE codes**: [HOW_TO_FIND_INE_CODES.md](HOW_TO_FIND_INE_CODES.md)
4. **Technical implementation**: [INE_API_IMPLEMENTATION.md](INE_API_IMPLEMENTATION.md)

## 📊 API Endpoints Reference

### Individual Municipality Data
```
GET /v1/municipalities/{dico}.json
```
Example: `/v1/municipalities/1106.json` (Lisboa)

### Bulk Download
```
GET /v1/bulk/all-municipalities.json
```
All 308 municipalities in one file (2 MB)

### CSV Downloads
```
GET /v1/downloads/raw-data.csv              # Long format, raw values
GET /v1/downloads/normalized-data.csv       # Long format, normalized values
GET /v1/downloads/raw-data-wide.csv         # Wide format, raw values
GET /v1/downloads/normalized-data-wide.csv  # Wide format, normalized values
```

### Metadata
```
GET /v1/municipalities/index.json   # List of all municipalities
GET /v1/metadata/indicators.json    # Indicator metadata
GET /v1/metadata/hierarchy.json     # Dimension structure
GET /v1/metadata/sources.json       # Data sources
GET /LAST_UPDATE.json               # Global update timestamp
```

## 🔧 Contributing

To update documentation:

1. **API Documentation (index.html)**:
   - Edit [index.html](index.html)
   - Update endpoint examples
   - Add new sections as needed

2. **Technical Guides**:
   - Create new markdown files in this directory
   - Link from this README
   - Follow existing structure

3. **Code Examples**:
   - Add to `examples/` directory
   - Include working code with comments
   - Cover common use cases

## 📝 Documentation Standards

### Markdown Files
- Use clear headings (H2 for main sections, H3 for subsections)
- Include code examples with syntax highlighting
- Add links to related documents
- Keep examples practical and tested

### Code Examples
- Must be working, tested code
- Include comments explaining key concepts
- Show error handling
- Demonstrate best practices

### HTML Documentation
- Responsive design
- Accessible (WCAG AA)
- Clear navigation
- Interactive examples where possible

## 🌐 Deployment

The `index.html` file is automatically deployed to GitHub Pages and served at:
```
https://<username>.github.io/datah-api/docs/
```

Documentation updates are live immediately after pushing to `main` branch.

## 📧 Questions?

For API usage questions, see the interactive documentation at [index.html](index.html)

For technical implementation questions, check the relevant guide above or consult [CLAUDE.md](../CLAUDE.md) in the project root.
