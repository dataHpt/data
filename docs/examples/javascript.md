# DataH API - JavaScript Examples

## Fetch Single Municipality

```javascript
async function getMunicipality(dico) {
  const baseUrl = 'https://datah.github.io/data/v1';
  const response = await fetch(`${baseUrl}/municipalities/${dico}.json`);

  if (!response.ok) {
    throw new Error(`Municipality ${dico} not found`);
  }

  return await response.json();
}

// Usage
const lisboa = await getMunicipality('1106');
console.log(lisboa.metadata.name); // "Lisboa"
```

## Get All Municipalities

```javascript
async function getAllMunicipalities() {
  const baseUrl = 'https://datah.github.io/data/v1';
  const response = await fetch(`${baseUrl}/municipalities/index.json`);
  const index = await response.json();

  return index.municipalities;
}

// Usage
const municipalities = await getAllMunicipalities();
console.log(`Total: ${municipalities.length}`); // 308
```

## Extract Specific Indicator

```javascript
function getIndicatorValue(municipalityData, indicatorId) {
  // Navigate through hierarchy to find indicator
  for (const dimension of Object.values(municipalityData.dimensions)) {
    for (const subDim of Object.values(dimension.sub_dimensions)) {
      for (const gaveta of Object.values(subDim.gavetas)) {
        if (gaveta.indicators[indicatorId]) {
          return gaveta.indicators[indicatorId];
        }
      }
    }
  }
  return null;
}

// Usage
const lisboa = await getMunicipality('1106');
const rsi = getIndicatorValue(lisboa, 'beneficiarios_rsi');
console.log(`RSI normalized: ${rsi.normalized}`);
console.log(`RSI raw: ${rsi.raw} ${rsi.unit}`);
```

## Compare Municipalities

```javascript
async function compareMunicipalities(dico1, dico2, indicatorId) {
  const [mun1, mun2] = await Promise.all([
    getMunicipality(dico1),
    getMunicipality(dico2)
  ]);

  const value1 = getIndicatorValue(mun1, indicatorId);
  const value2 = getIndicatorValue(mun2, indicatorId);

  return {
    [mun1.metadata.name]: value1,
    [mun2.metadata.name]: value2,
    difference: value1.normalized - value2.normalized
  };
}

// Usage
const comparison = await compareMunicipalities('1106', '1311', 'taxa_desemprego');
console.log(comparison);
```

## TypeScript Types

```typescript
interface Indicator {
  normalized: number;
  raw: number;
  unit: string;
}

interface Metadata {
  dico: string;
  name: string;
  last_updated: string;
  api_version: string;
}

interface MunicipalityData {
  metadata: Metadata;
  dimensions: {
    [dimensionId: string]: {
      sub_dimensions: {
        [subDimId: string]: {
          gavetas: {
            [gavetaId: string]: {
              indicators: {
                [indicatorId: string]: Indicator;
              };
            };
          };
        };
      };
    };
  };
}

// Typed function
async function getMunicipality(dico: string): Promise<MunicipalityData> {
  const baseUrl = 'https://datah.github.io/data/v1';
  const response = await fetch(`${baseUrl}/municipalities/${dico}.json`);
  return await response.json();
}
```
