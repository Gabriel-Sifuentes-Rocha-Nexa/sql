---
name: Reference — V1 Metadata: Token, Titulo Publico (NTN-I), CDB, SPV Series
description: JSONB metadata structure and V2 mapping for token, titulo_publico, CDB, and spv_series asset types
type: reference
tags: [tipo/referência, conceito/migração, team/engine, produto/token, produto/ntni]
resumo: "Estrutura JSONB e mapeamento V1→V2 para token, titulo_publico (NTN-I), CDB e spv_series"
---

## token → V2 `tokens`

`securities.type = 'token'` — 338 records.

```
metadata = {
  -- Campos de registro / estáticos
  "issuer":                      string  -- nome do emissor → tokens.issuer_id (entity lookup)
  "issuer_code":                 string  -- código 2-char → tokens.issuer_code
  "strategy":                    string  -- "CO"|"CDB"|... → tokens.strategy_id (FK token_strategies)
  "serie":                       string  -- contagem de emissão → tokens.issuance_count (smallint)
  "issuanceAmount":              number  -- montante autorizado de emissão → tokens.issuance_amount
  "minimumIssuanceAmount":       string  -- montante mínimo de emissão
  "issuancePrice":               number  -- preço unitário de emissão → tokens.issuance_price
  "quantity_issued":             number  -- quantidade total efetivamente emitida
  "last_maturity_date":          string  -- data de vencimento final → tokens.maturity_date
  "token_duration":              string  -- duração em anos → tokens.duration_months (×12)
  "offeringDuration":            string  -- período de oferta em dias → tokens.offering_duration
  "referral_fee":                number  -- taxa de indicação → tokens.referral_fee
  "distributor":                 string  -- nome do distribuidor → tokens.distributor

  -- Campos de yield/retorno (na emissão)
  "tokenYieldIndexer":           string  -- índice de yield "CDI"|"IPCA" → tokens.indexer_id
  "tokenYieldRate":              number  -- taxa de yield na emissão (ex: 100 para 100% CDI)
  "tokenYieldType":              string  -- "pos" (pós-fixado) | "pre" → interpretação do yield
  "estimatedMOIC":               string  -- MOIC estimado → tokens.estimated_moic
  "estimatedSpreadOverCDI":      string  -- spread estimado sobre CDI → tokens.estimated_spread_over_cdi
  "estimatedSpreadOverInflation": string -- spread estimado sobre inflação → tokens.estimated_spread_over_inflation
  "returnPercentageCDI":         string  -- retorno como % do CDI → tokens.return_percentage_cdi
  "returnYieldEstimated":        string  -- TIR estimada → tokens.internal_rate_of_return

  -- Mark-to-market corrente (última valuação)
  "token_adjusted_price":        number  -- preço mark-to-market corrente → valuations.clean_price
  "token_true_yield":            number  -- true yield corrente → valuations
  "token_displayed_yield":       number  -- yield exibido corrente → valuations.spread_over_cdi

  -- Cash flow
  "expected_cashflow_value":     number  -- total de cash flows esperados → tabela expected_cash_flows

  -- Composição (ativos subjacentes)
  "composition":                 array   -- breakdown de ativos subjacentes → tokens_underlyings
                                         -- cada item: {amount, from_aux_id, asset_aux_id,
                                         --   pass_along_cash_in, pass_along_cash_out, ...}

  -- Campos V1-only (blockchain)
  "fundingTokenAddress":         string  -- endereço blockchain (V1-only, não armazenado em V2)
  "spenderTokenAddress":         string  -- endereço spender (V1-only, não armazenado em V2)
  "projectOwner":                string  -- project owner (V1-only, não armazenado em V2)
}
```

### Mapeamentos-chave

| Chave V1 | Destino V2 | notas |
|---|---|---|
| `issuer` | `tokens.issuer_id` | entity lookup por nome |
| `issuer_code` | `tokens.issuer_code` | char(2) |
| `strategy` | `tokens.strategy_id` | FK token_strategies |
| `serie` | `tokens.issuance_count` | cast smallint |
| `issuanceAmount` | `tokens.issuance_amount` | cast decimal |
| `issuancePrice` | `tokens.issuance_price` | cast decimal |
| `minimumIssuanceAmount` | `tokens.minimum_issuance_amount` | cast decimal |
| `estimatedMOIC` | `tokens.estimated_moic` | cast decimal |
| `estimatedSpreadOverCDI` | `tokens.estimated_spread_over_cdi` | cast decimal |
| `estimatedSpreadOverInflation` | `tokens.estimated_spread_over_inflation` | cast decimal |
| `offeringDuration` | `tokens.offering_duration` | cast smallint |
| `returnPercentageCDI` | `tokens.return_percentage_cdi` | cast decimal |
| `returnYieldEstimated` | `tokens.internal_rate_of_return` | cast decimal |
| `referral_fee` | `tokens.referral_fee` | decimal |
| `token_duration` | `tokens.duration_months` | cast decimal |
| `last_maturity_date` | `tokens.maturity_date` | date |
| `tokenYieldIndexer` | `tokens.indexer_id` | FK indexers |
| `tokenYieldRate` | `tokens.indexer_percentage` ou `spread_over_indexer` | depende de `tokenYieldType` |
| `tokenYieldType` | determina mapeamento de `tokenYieldRate` | "pos"=% do índice; "pre"=spread fixo |
| `token_adjusted_price` | `valuations.clean_price` | |
| `token_true_yield` / `token_displayed_yield` | `valuations.spread_over_cdi` | |
| `fundingTokenAddress`, `spenderTokenAddress`, `projectOwner` | não armazenados | V1-only |

**`tokens.structure_id`** — NÃO derivado do metadata V1. Deve ser passado explicitamente como `token_structure` (nome string), resolvido via lookup em `token_structures`. Definido durante criação do token via API, não migrado.

**`composition` → tabela `tokens_underlyings`**: tabela **ainda não existe no DDL V2** (comentada). O modelo ORM existe mas pode estar à frente do schema. Quando criada, cada item do array mapeia para uma row com `token_id`, `amount`, `asset_id` (resolvido do UUID).

---

## spv_series / spv entities → V2 securitizations

### Arquitetura (crítico)

- **V1 `securities` type `spv_series`** (101 records, um por série) → **V2 `securitization_series`**
- **V1 `entities` type `spv`** (27 entities) → **V2 `securitizations`** (deal pai) + row em **V2 `entities`**

`securitizations` é o deal SPV pai. `securitization_series` armazena as tranches individuais.

### Metadata da security `spv_series`

```
metadata = {
  "spv_aux_id":                      string -- UUID do SPV pai → securitization_series.issuer_id (lookup)
  "isin_code":                        string -- código ISIN (NÃO presente no metadata do SPV entity)
  "series_number":                    number → securitization_series.series_number
  "series_type":                      string -- "senior"|"subordinated"|"mezzanine_a"|"mezzanine_b"|"single" → seniority_id
  "series_seniority":                 number -- nível de senioridade (1=senior, etc.)
  "series_index":                     string -- "CDI"|"Prefixado" → indexer_id
  "series_abs_spread_over_index":     number → securitization_series.spread_over_indexer
  "series_relative_spread_over_index": number → securitization_series.indexer_percentage
  "series_fixed_rate":                number -- taxa fixa (0 se floating)
  "series_issuance_date":             string → securitization_series.issuance_date
  "series_maturity_date":             string → securitization_series.maturity_date
  "series_issuance_amount":           string -- montante total (BRL) → derivar securitization_series.quantity
  "series_issuance_unit_price":       number → securitization_series.initial_price
  "payment_schedule":                 array  → securitization_payment_schedules
    -- cada item: {payment_date, interest_payment (bool), amortization_fraction}
}
```

**Diferença-chave**: securities `spv_series` têm `isin_code` (ausente no metadata do SPV entity), mas NÃO têm `series_code` (presente em `spv.metadata.series[]`). Ambas as fontes são necessárias para uma migração completa.

### spv entity → row `securitizations`

| Fonte V1 | Coluna V2 | notas |
|---|---|---|
| `spv.metadata.issuer_aux_id` | `issuer_id` | UUID→integer lookup |
| `spv.metadata.trustee_aux_id` | `trustee_id` | UUID→integer lookup |
| `spv.metadata.spv_underlyings` | `underlying_asset_id` | FK securitization_underlying_assets |
| `spv.metadata.issuance_number` | `issuance_number` | cast integer |
| `spv.metadata.issuance_date` | `issuance_date` | date |
| CNPJ do documento da entidade SPV | `document` | varchar(14) |

### spv expenses → `securitization_expenses`

Cada item em `spv.metadata.expenses` → uma row com `securitization_id`, `name_id`, `type_id`, `value`, `frequency_id`, `billing_frequency_id`, `provisioning_frequency_id`.

### spv payment schedule → `securitization_payment_schedules`

Cada item em `spv.metadata.payment_schedule` → uma row com `securitization_id`, `date`, `amortization_fraction`, `interest_payment`.

---

## titulo_publico → V2 `ntnis` + `valuations` + `exchange_rates`

`securities.type = 'titulo_publico'` — 122 records. Mapeia para tabela `ntnis` (mínima) + precificação em `valuations` e `exchange_rates`.

```
metadata = {
  "cedente":                    string -- nome do fundo cedente (entity lookup)
  "cessionario":                string -- nome do cessionário (entity lookup)
  "intermediario":              string -- nome do broker/intermediário (entity lookup)
  "dt_vencimento":              string -- data de vencimento original → ntnis.maturity_date
  "maturity_date":              string -- data de referência de settlement (pode diferir de dt_vencimento)
  "settlement_date":            string -- data de settlement da operação
  "ntni_base_pricing_price":    number -- preço base USD (face value NTN-I) → ntnis.face_value_usd
  "ptax_d1":                    number -- taxa BRL/USD (PTAX D+1) → tabela exchange_rates
  "negotiated_spread":          number -- spread na negociação → valuations
  "negotiated_total_yield":     number -- yield total na negociação → valuations
  "negotiated_yield_curve":     number -- curva de yield base na negociação → valuations
  "negotiated_days_to_maturity": number -- dias úteis até vencimento na negociação (computado, não armazenado)
  "correct_total_yield":        number -- yield total correto/atual → valuations
  "correct_days_to_maturity":   number -- dias corretos até vencimento (computado, não armazenado)
}
```

### Mapeamento V1 → V2

| Chave V1 | Destino V2 | notas |
|---|---|---|
| `dt_vencimento` | `ntnis.maturity_date` | date |
| `ntni_base_pricing_price` | `ntnis.face_value_usd` | decimal |
| `ptax_d1` | tabela `exchange_rates` | taxa BRL/USD para a data da operação |
| `negotiated_spread` | `valuations` | na negociação |
| `negotiated_total_yield` | `valuations` | na negociação |
| `negotiated_yield_curve` | `valuations` | curva de yield base |
| `correct_total_yield` | `valuations` | yield correto/atual |
| `cedente`, `cessionario`, `intermediario` | entity lookups | |
| `settlement_date` | data de posição/transação | não em ntnis diretamente |
| `negotiated_days_to_maturity`, `correct_days_to_maturity` | não armazenados | computados |

---

## CDB → V2 `cdbs`

`securities.type = 'CDB'` — apenas 2 records.

```
metadata = {
  "issuer":             string -- nome do emissor → issuer_id entity lookup
  "issuerDocument":     string -- CNPJ do emissor → issuer_id entity lookup
  "issuanceDate":       string → issuance_date
  "maturityDate":       string → maturity_date
  "faceValue":          number → face_value
  "guarantee":          string -- tipo de garantia ("FGC") → fgc_guarantee
  "yieldIndexer":       string -- índice de yield → indexer_id
  "yieldRate":          number → spread_over_indexer ou indexer_percentage (depende de yieldType)
  "yieldType":          string -- "pre" ou "pos"
  -- campos V1-only sem equivalente V2 confirmado:
  "incomeTax":          string -- regime de imposto de renda
  "interestFrequency":  string -- frequência de pagamento
  "liquidity":          string -- tipo de liquidez
}
```

---

## fund.metadata.series → V2 (não definido)

**Status: NÃO DEFINIDO no schema V2.** Séries de fundos FIDC (estrutura de capital) não têm tabela V2 confirmada.

Opções em análise:
1. Reutilizar `securitization_series` se os fundos FIDC emitem securitizações
2. Nova tabela `fund_series` (ainda não criada)

A estrutura de `fund.metadata.series` é idêntica à de séries SPV. Podem ser carregadas em `securitization_series` usando a entidade fund como emissor.
