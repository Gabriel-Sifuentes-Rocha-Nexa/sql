---
name: Reference — V1 Entities Metadata Structure
description: Full JSONB metadata structure for each entity type in V1, including SPV and fund series data — critical for V1→V2 migration
type: reference
tags: [tipo/referência, conceito/migração, team/engine]
resumo: "Estrutura JSONB de metadata por tipo de entidade em V1: issuer, corporate, individual, fund, spv — com mapeamento para V2"
---

## Distribuição por tipo (snapshot de migração)

| type | count | descrição |
|---|---|---|
| `issuer` | 35 | Administradoras de consórcio |
| `spv` | 27 | Veículos de securitização (SPVs/FIDCs) |
| `fund` | 18 | Fundos FIDC (com séries/tranches) |
| `individual` | 16 | Investidores pessoas físicas |
| `corporate` | 11 | Entidades corporativas (empresas, contrapartes) |

---

## Tipo `issuer` (administradoras de consórcio)

```
metadata = {
  "document":     string -- CNPJ da administradora
  "documentType": string -- sempre "cnpj"
  "issuerType":   string -- sempre "administradora"
}
```

V2: → row em `entities`. O `document` alimenta `contact_infos` ou identificação da entidade.

---

## Tipo `corporate`

```
metadata = {
  "document":      string -- CNPJ (formatado ou raw)
  "documentType":  string -- "cnpj"
  "cnpj":          string -- CNPJ (14 dígitos raw)
  "company":       string -- nome da empresa
  "address":       string -- logradouro
  "number":        string -- número do endereço
  "complement":    string -- complemento
  "neighborhood":  string -- bairro
  "city":          string -- cidade
  "state":         string -- estado (ex: "SP")
  "zip":           string -- CEP
  "contact":       string -- email de contato
  "email":         string -- email (às vezes distinto de contact)
  "website":       string -- URL do site
  "issuer_code":   string -- código de 2 chars (ex: "NX", "TT") — presente para emissores de token
  "classification": string -- "nexa" | "familyOffice" | ""
  -- campos legados V1 sem equivalente em V2:
  "last_accrual_date":  string -- data do último accrual (operacional)
  "last_struck_date":   string -- data do último struck/settlement
}
```

V2: identidade → row `entities`; `document` → `entities.doc_id`; endereço → tabela `contact_infos`; `issuer_code` → matching com `tokens.issuer_code`.

---

## Tipo `individual`

```
metadata = {
  "document":       string -- CPF (11 dígitos)
  "document_type":  string -- "cpf"
  "company":        string -- sempre "Nexa Finance" (usuário interno)
  "contact":        string -- email
  "classification": string -- "nexa" | outro
  -- campos legados V1 sem equivalente em V2:
  "last_accrual_date":  string
  "last_struck_date":   string
}
```

V2: → row `entities`; CPF → `contact_infos.document` com `document_type = 'cpf'`.

---

## Tipo `fund` (FIDCs)

Fundos de investimento FIDC que detêm ativos de consórcio/FGTS e emitem séries de cotas.

```
metadata = {
  "document":      string -- CNPJ
  "document_type": string -- "cnpj"
  "company":       string -- nome do fundo
  "contact":       string -- email de contato
  "classification": string -- "nexa" | "familyOffice"
  "issuer_code":   string -- código 2-char (sparse)
  "series": array  -- séries de capital do FIDC, cada item:
    {
      "series_code":                    string -- ex: "FIDC-Consorcio-01-01-senior-01"
      "series_type":                    string -- "senior"|"mezzanine_a"|"mezzanine_b"|"subordinated"
      "series_index":                   string -- "CDI"|"Prefixado"
      "series_number":                  number
      "issuance_number":                number
      "series_seniority":               number -- 1=senior, 2=mezz_a, etc.
      "series_fixed_rate":              number -- 0 se floating
      "series_issuance_date":           string
      "series_maturity_date":           string|null
      "series_issuance_amount":         number -- BRL
      "series_issuance_unit_price":     number -- ex: 1000
      "series_monetary_adjustment":     string -- "cdi"|null
      "series_abs_spread_over_index":   number
      "series_relative_spread_over_index": number -- 1.0 = 100%
      "payment_schedules": array -- [{ payment_date, interest_payment (bool), amortization_fraction }]
    }
}
```

V2: fund → row `entities`. O array `series` mapeia para `securitizations` ou mecanismo de fund series separado (não totalmente definido em V2). `payment_schedules` → tabela `expected_cash_flows`.

---

## Tipo `spv` (veículos de securitização)

Cada entidade SPV é pai de múltiplos securities `spv_series` (101 records, derivados dos 27 SPVs).

**Relacionamento-chave**: cada `spv_series` security tem `metadata.spv_aux_id` apontando para o `entities.aux_id` do SPV pai. O SPV armazena a estrutura completa de séries em `metadata.series`.

```
metadata = {
  "issuance_number":  string -- sequência de emissão ("01","02","03")
  "issuance_date":    string -- data de emissão do SPV
  "issuer_aux_id":    string -- UUID do emissor → securitizations.issuer_id
  "trustee_aux_id":   string -- UUID do trustee → securitizations.trustee_id
  "spv_type":         string -- "CR" (Crédito Recebíveis)
  "spv_underlyings":  string -- tipo de ativo subjacente ("FGTS") → securitization_underlying_assets FK
  "yield":            number -- yield corrente do SPV
  "series": array     -- todas as séries do SPV (mesma estrutura de spv_series securities)
  "payment_schedule": array -- schedule de amortização do SPV:
    [{ payment_date, amortization_pct, interest_payment }]
    → tabela expected_cash_flows
  "expenses": array   -- despesas operacionais do SPV:
    [{
      expense_name, expense_type ("percentage"|"value"),
      expense_value, expense_frequency, expense_value_base,
      expense_payment_frequency, expense_provisioning_frequency
    }]
    → tabela securitization_expenses
  "asset_amount_reserved": array -- sem equivalente em V2
    [{ amount, aux_id (UUID do ativo reservado) }]
}
```

### Mapeamento spv V1 → V2

| Fonte V1 | Destino V2 | notas |
|---|---|---|
| `entities` type `spv` | row `entities` | o veículo SPV como entidade nomeada |
| `metadata.issuer_aux_id` | `securitizations.issuer_id` | lookup UUID→integer |
| `metadata.trustee_aux_id` | `securitizations.trustee_id` | lookup UUID→integer |
| `metadata.spv_underlyings` | `securitizations.underlying_asset_id` | FK securitization_underlying_assets |
| `metadata.issuance_number` | `securitizations.issuance_number` | cast integer |
| `metadata.issuance_date` | `securitizations.issuance_date` | date |
| `metadata.series[]` | um row `securitization_series` por série | cada série → tranche |
| `series.series_abs_spread_over_index` | `securitizations.assignment_yield` | no row pai |
| `metadata.payment_schedule` | tabela `securitization_payment_schedules` | |
| `metadata.expenses` | tabela `securitization_expenses` | name_id, type_id, value, frequency_id FKs |
| `metadata.asset_amount_reserved` | sem equivalente V2 | v1-only |
| `metadata.yield` | `valuations`? | yield corrente, não dado de registro |

### Relacionamento: spv entities ↔ spv_series securities

- 27 entities `spv` × N séries cada = 101 securities `spv_series`
- Cada `spv_series` tem `metadata.spv_aux_id` → `entities.aux_id` do SPV pai
- Em V2: SPV entity → row `entities` + row `securitizations` (deal pai); cada série → row `securitization_series` com `issuer_id` = SPV entity
