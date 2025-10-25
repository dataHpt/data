# DataH API - Python Examples

## Setup

```python
import requests
import pandas as pd
from typing import Dict, List, Any

BASE_URL = "https://datah.github.io/data/v1"
```

## Fetch Single Municipality

```python
def get_municipality(dico: str) -> Dict[str, Any]:
    """Fetch data for a single municipality."""
    url = f"{BASE_URL}/municipalities/{dico}.json"
    response = requests.get(url)
    response.raise_for_status()
    return response.json()

# Usage
lisboa = get_municipality("1106")
print(lisboa['metadata']['name'])  # "Lisboa"
```

## Get All Municipalities

```python
def get_all_municipalities() -> List[Dict[str, str]]:
    """Fetch list of all municipalities."""
    url = f"{BASE_URL}/municipalities/index.json"
    response = requests.get(url)
    data = response.json()
    return data['municipalities']

# Usage
municipalities = get_all_municipalities()
print(f"Total: {len(municipalities)}")  # 308
```

## Extract Indicators to DataFrame

```python
def extract_indicators(municipality_data: Dict) -> pd.DataFrame:
    """Extract all indicators into a flat DataFrame."""
    rows = []

    dimensions = municipality_data['dimensions']

    for dim_name, dim in dimensions.items():
        for subdim_name, subdim in dim['sub_dimensions'].items():
            for gaveta_name, gaveta in subdim['gavetas'].items():
                for ind_name, ind in gaveta['indicators'].items():
                    rows.append({
                        'dimension': dim_name,
                        'sub_dimension': subdim_name,
                        'gaveta': gaveta_name,
                        'indicator_id': ind_name,
                        'normalized': ind['normalized'],
                        'raw': ind['raw'],
                        'unit': ind['unit']
                    })

    return pd.DataFrame(rows)

# Usage
lisboa = get_municipality("1106")
indicators_df = extract_indicators(lisboa)
print(indicators_df.head())
```

## Compare Multiple Municipalities

```python
def compare_municipalities(
    dicos: List[str],
    indicator_id: str
) -> pd.DataFrame:
    """Compare specific indicator across municipalities."""
    results = []

    for dico in dicos:
        data = get_municipality(dico)
        indicators_df = extract_indicators(data)

        indicator_row = indicators_df[
            indicators_df['indicator_id'] == indicator_id
        ].iloc[0]

        results.append({
            'dico': dico,
            'municipality': data['metadata']['name'],
            'normalized': indicator_row['normalized'],
            'raw': indicator_row['raw'],
            'unit': indicator_row['unit']
        })

    df = pd.DataFrame(results)
    return df.sort_values('normalized', ascending=False)

# Usage
comparison = compare_municipalities(
    dicos=['1106', '1311', '0101'],
    indicator_id='taxa_desemprego'
)
print(comparison)
```

## Fetch and Cache

```python
from functools import lru_cache

@lru_cache(maxsize=128)
def get_municipality_cached(dico: str) -> Dict[str, Any]:
    """Fetch municipality data with caching."""
    return get_municipality(dico)

# Usage (first call fetches, subsequent calls use cache)
lisboa = get_municipality_cached("1106")
```

## Visualization Example

```python
import matplotlib.pyplot as plt
import seaborn as sns

def plot_indicator_comparison(
    dicos: List[str],
    indicator_id: str
):
    """Plot comparison of indicator across municipalities."""
    comparison = compare_municipalities(dicos, indicator_id)

    plt.figure(figsize=(10, 6))
    sns.barplot(
        data=comparison,
        x='normalized',
        y='municipality',
        palette='viridis'
    )
    plt.xlabel('Valor Normalizado (0-100)')
    plt.ylabel('Município')
    plt.title(f'Comparação: {indicator_id}')
    plt.tight_layout()
    plt.show()

# Usage
plot_indicator_comparison(
    dicos=['1106', '1311', '0101', '1308'],
    indicator_id='beneficiarios_rsi'
)
```

## Fetch Metadata

```python
def get_indicators_metadata() -> pd.DataFrame:
    """Fetch metadata for all indicators."""
    url = f"{BASE_URL}/metadata/indicators.json"
    response = requests.get(url)
    data = response.json()

    # Convert to DataFrame
    indicators = pd.DataFrame(data['indicators'])
    return indicators

# Usage
metadata = get_indicators_metadata()
print(metadata[['id', 'name', 'direction', 'unit']])
```

## Bulk Download (All Municipalities)

```python
def get_bulk_data() -> Dict[str, Any]:
    """Download all municipalities data in single request (~2MB)."""
    url = f"{BASE_URL}/bulk/all-municipalities.json"
    print("Downloading bulk data (~2MB)...")

    response = requests.get(url)
    response.raise_for_status()

    return response.json()

# Usage
all_data = get_bulk_data()
print(f"Total municipalities: {len(all_data['municipalities'])}")
```

## Build Complete Dataset

```python
def build_complete_dataset() -> pd.DataFrame:
    """Build DataFrame with all municipalities and indicators."""
    all_muns = get_all_municipalities()
    all_rows = []

    for mun in all_muns[:10]:  # Example: first 10
        dico = mun['dico']
        data = get_municipality(dico)
        indicators_df = extract_indicators(data)

        indicators_df['dico'] = dico
        indicators_df['municipality'] = data['metadata']['name']

        all_rows.append(indicators_df)

    return pd.concat(all_rows, ignore_index=True)

# Usage
dataset = build_complete_dataset()
print(dataset.shape)
```

## Class-based Interface

```python
class DataHAPI:
    """Object-oriented interface for DataH API."""

    def __init__(self, base_url: str = BASE_URL):
        self.base_url = base_url
        self.session = requests.Session()

    def get_municipality(self, dico: str) -> Dict:
        url = f"{self.base_url}/municipalities/{dico}.json"
        response = self.session.get(url)
        response.raise_for_status()
        return response.json()

    def get_all_municipalities(self) -> List[Dict]:
        url = f"{self.base_url}/municipalities/index.json"
        response = self.session.get(url)
        data = response.json()
        return data['municipalities']

    def extract_indicators(self, municipality_data: Dict) -> pd.DataFrame:
        # Same implementation as function above
        pass

# Usage
api = DataHAPI()
lisboa = api.get_municipality("1106")
```
