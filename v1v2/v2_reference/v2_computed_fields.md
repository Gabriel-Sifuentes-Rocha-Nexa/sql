---
name: Reference — V2 Campos Derivados / Não Migrados
description: Catálogo de colunas V2 que NÃO vêm de cópia direta de V1 — calculadas, mantidas por trigger, ou geradas durante ETL
type: reference
tags: [tipo/referência, conceito/migração, team/engine]
resumo: "Colunas V2 calculadas (FRA, IRR, ETTJ, dia útil), mantidas por trigger, ou geradas pela aplicação — não migradas de V1"
---

## Por que esse arquivo existe

Quando uma coluna V2 está NULL ou com valor inesperado, a primeira pergunta é: "isso vem de V1 ou é calculado?". Procurar em V1 só resolve metade dos casos — campos derivados/triggers/gerados não existem em V1 e devem ser auditados em outro lugar (lógica de ETL, triggers do banco, payload da API).

## Categorias

- **trigger** — mantido pelo banco V2 via trigger AFTER INSERT/UPDATE/DELETE. Não escrever diretamente.
- **derivado** — calculado em ETL a partir de outros campos (V1 ou V2) com fórmula determinística.
- **gerado** — atribuído pelo ETL ou API sem fonte direta (contadores, defaults, lookups operacionais).
- **operacional** — preenchido posteriormente por evento de aplicação (settlement, reprecificação, etc.).

---

## `consortiums` (ver nexa_ai_prompts/engine-team/v1_to_v2_migration/v1_metadata_consortium.md)

| Coluna V2 | Categoria | Origem / fórmula |
|---|---|---|
| `face_value` | derivado | `face_value_original` corrigido via curvas FRA até a data de referência |
| `maturity_date` | derivado | `maturity_date_original` + 1 dia útil (calendário B3) |
| `contemplation_value` | derivado | `vccsle_calcs.vc - vccsle_calcs.vle` |
| `discharge_date` | operacional | definido na operação de settlement do consórcio |
| `presentvalue_outstanding_balance` | operacional | atualizado por valuação periódica |
| `updated_outstanding_balance` | operacional | atualizado por valuação periódica |

---

## `fgts` (ver nexa_ai_prompts/engine-team/v1_to_v2_migration/v1_metadata_fgts.md)

| Coluna V2 | Categoria | Origem / fórmula |
|---|---|---|
| `maturity_date_original` | derivado | primeiro dia útil em ou após `data_vencimento` (n=0 mantém se já é DU) |
| `maturity_date` | derivado | `maturity_date_original` + 1 dia útil |
| `spread_over_indexer` | derivado | `IRR(days=dc, inflow=acquisition_value, outflow=face_value, period=360)` — **NÃO** `tx_cessao` |
| `spread_over_cdi` | derivado | `(1 + spread_over_indexer) / (1 + ettj) - 1` via curva ETTJ |
| `indexer_percentage` | gerado | sempre `0` para FGTS PREFIXADO |
| `cession_id` | gerado | contador sequencial de batch ETL (todos os records do mesmo batch compartilham o id) — não há tabela `cessions` |
| `obligor_*` (bank, uf, city, etc.) | gerado | vêm do **arquivo de elegibilidade** CEF, não do JSONB V1 |
| `cef_uuid`, `cef_protocol` | gerado | arquivo de elegibilidade (opcional) |
| `contract_min_maturity_date`, `contract_max_maturity_date` | gerado | arquivo de elegibilidade |

---

## `tokens` (ver nexa_ai_prompts/engine-team/v1_to_v2_migration/v1_metadata_other_assets.md)

| Coluna V2 | Categoria | Origem / fórmula |
|---|---|---|
| `structure_id` | gerado | passado explicitamente como `token_structure` (string) na criação via API; não migrado de V1 |
| `indexer_percentage` | derivado | `tokenYieldRate` se `tokenYieldType = "pos"` |
| `spread_over_indexer` | derivado | `tokenYieldRate` se `tokenYieldType = "pre"` |
| `duration_months` | derivado | `token_duration` (anos) × 12 |

---

## `securitizations` / `securitization_series` (ver nexa_ai_prompts/engine-team/v1_to_v2_migration/v1_metadata_other_assets.md e nexa_ai_prompts/engine-team/v1_to_v2_migration/v1_metadata_entities.md)

| Coluna V2 | Categoria | Origem / fórmula |
|---|---|---|
| `securitizations.assignment_yield` | derivado | `series.series_abs_spread_over_index` da série pai (não vive na entity SPV) |
| `securitization_series.quantity` | derivado | `series_issuance_amount / series_issuance_unit_price` |
| `securitization_series.issuer_id` | gerado | resolução do `spv_aux_id` UUID V1 → entity integer V2 |

---

## `positions` (ver nexa_ai_prompts/engine-team/v1_to_v2_migration/v1_metadata_positions_valuations_transactions.md)

| Coluna V2 | Categoria | Origem / fórmula |
|---|---|---|
| `total_quantity` | trigger | soma cumulativa de `variation` (date ASC, id ASC, particionada por holder/asset/lot/financial_account) |
| `last_position_flag` | trigger | TRUE no record mais recente do grupo (holder/asset/lot/financial_account) |
| `variation` | gerado | semântica nova V2; deriva de `amount`/`available` V1 + transaction_type |
| `lot_id` | gerado | atribuído pelo ETL (granularidade de lote — sem equivalente V1) |
| `block_id` | gerado | bigint atribuído pelo ETL para agrupar entries da mesma transação |
| `financial_account_id` | gerado | resolvido pelo ETL via classificação contábil da transação |
| `transaction_type_id` | gerado | FK para `transaction_types` — V1 usa `type text` |
| `holder_bank_account_id`, `counterparty_bank_account_id` | gerado | resolvido pelo ETL |
| `originator_id`, `broker_id` | gerado | resolvido pelo ETL via metadata de transação |
| `trade_date` | gerado | data de negociação (separada de `date` que é settlement); pode ser NULL |
| `transaction_unit_price` | gerado | preço da transação no momento; pode ser NULL |

---

## `valuations` (ver nexa_ai_prompts/engine-team/v1_to_v2_migration/v1_metadata_positions_valuations_transactions.md)

| Coluna V2 | Categoria | Origem / fórmula |
|---|---|---|
| `last_valuation_flag` | trigger | TRUE no record mais recente por (asset, lot, methodology) |
| `clean_price` | derivado | parte "limpa" do `value` único de V1 (sem juros acumulados) |
| `accrued_interest` | derivado | parte de juros acumulados, separada de `clean_price` |
| `cash_flow` | derivado | calculado pelo ETL a partir do schedule do ativo |
| `duration_years` | derivado | duration do fluxo de caixa em anos (numeric(8,4)) |
| `lot_id` | gerado | atribuído pelo ETL |
| `methodology_id` | gerado | FK para `valuation_methodologies` (amortized_cost por padrão) |
| `indexer_id`, `indexer_percentage`, `spread_over_indexer`, `spread_over_cdi`, `spread_over_inflation` | gerado | metadata da valuação atribuída pelo ETL |
| `currency_id` | gerado | inferido do `metadata.currency` V1 (sempre BRL) ou do `series_currency` para NTN-I |

---

## `expected_cash_flows`

| Coluna V2 | Categoria | Origem / fórmula |
|---|---|---|
| `currency_id` | quirk | FK aponta para **`entities.id`**, não `currencies.id` — quirk conhecido do schema |

---

## Bancos de dados (FK lookups)

| Coluna V2 | Categoria | Resolução |
|---|---|---|
| `entities.id` | gerado | SERIAL auto-incremento; lookup V1→V2 por `entities.name` (ou `doc_id` para CNPJ/CPF) |
| `entities.doc_id` | gerado | extraído do CNPJ/CPF do metadata V1 |
| `entities.reference_table_id` | gerado | atribuído por tipo de ativo durante migração |
| `entities.source_id` | gerado | identifica a origem do registro (FK para `sources`) |

---

## Constantes / defaults durante ETL

| Caso | Valor |
|---|---|
| FGTS `indexer_id` | sempre `PREFIXADO` |
| FGTS `indexer_percentage` | sempre `0` |
| Consórcio `wallet_fidc` | default `"1"` se ausente em V1 |
| Posições/valuações V1 metadata `currency` | sempre `"BRL"` (exceto NTN-I que é `"USD"`) |
| Valuação default `methodology` | `amortized_cost` (todos asset classes); consórcio também usa `amortized_cost_original`, `face_value`, `zero_spread` |

---

## Como auditar uma coluna V2 NULL ou suspeita

1. **Está nessa lista?** → não veio de V1; checar lógica de ETL/trigger/payload da API.
2. **Não está nessa lista?** → mapping V1↔V2 deve cobrir; abrir o `v1_metadata_<asset>.md` correspondente.
3. **É um campo `_flag` ou `total_*`?** → trigger; checar nexa_ai_prompts/engine-team/v1_to_v2_migration/v2_schema.md seção "Quirks críticos".
4. **É data calculada (`maturity_*`, `expected_*`)?** → derivado de business day calc; verificar calendário (anbima/b3) e offset.
