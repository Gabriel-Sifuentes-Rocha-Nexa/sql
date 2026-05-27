---
name: Reference — Gotchas e Anomalias V1↔V2
description: Armadilhas conhecidas do schema, normalização de strings, suffixes inesperados, FKs incomuns, defaults silenciosos
type: reference
tags: [tipo/referência, conceito/migração, team/engine]
resumo: "Catálogo de gotchas: sufixos no contrato FGTS, normalização de nomes, FKs estranhas, triggers, defaults — tudo que já queimou alguém"
---

## Schema / FKs incomuns

- **`expected_cash_flows.currency_id` → `entities.id`** (não `currencies.id`). Quirk legado. Ao filtrar currency, usar entity, não a tabela `currencies`.
- **`securitization_series` não tem `currency_id`**. Currency só existe em `valuations.currency_id` e `expected_cash_flows.currency_id`. Para criar série em USD (NTN-I), passar `series_currency: "USD"` no payload — a API resolve para `currency_id` na primeira valuation. Runs subsequentes propagam da valuation anterior.
- **Tabelas de ativos têm `id` que é FK para `entities.id`**. Não auto-incremento próprio. Inserção exige criar entity antes.
- **`positions.unique(date, holder_id, asset_id, financial_account_id)`** — `lot_id` NÃO faz parte da chave única, apesar de fazer parte da partição do trigger. Implicação: dois lots no mesmo (date, holder, asset, fa) violam unique.

## Triggers — não escrever direto

- **`positions.total_quantity`** é mantido por trigger (cumsum de `variation`, particionado por `holder/asset/lot/financial_account`). Update direto será sobrescrito.
- **`positions.last_position_flag`** e **`valuations.last_valuation_flag`** mantidos por trigger AFTER INSERT/UPDATE/DELETE.
- Triggers recalculam o **grupo antigo E novo** em UPDATE (ex: mudou `holder_id`, recalcula ambos os grupos). DELETE também dispara recálculo do grupo afetado.

## Normalização de strings

- **Holder Nexa**: V1 = `Nexa Digital Assets SA`, V2 = `NEXA DIGITAL ASSETS SA`. Queries cross-version precisam normalizar.
- **CR de consórcio**: V1 = `CR-Consorcio-{N}` (mixed case), V2 = `CR-CONSORTIUMS-{N}` (uppercase + plural inglês). FGTS e NTN-I são idênticos em ambos.
- **Cedente / originador / administradora** (consórcio): normalizar com `trim + uppercase + remover pontos` antes do entity lookup.
- **`tipo_bem`**: `"auto"` → `"AUTOMOTOR"`, qualquer outro → `"OUTRO"` (consortium underlying asset).
- **`indice_reajuste`**: `"FIPE"` → `"IPC-FIPE"` (lookup indexers).

## Sufixos inesperados

- **Contrato FGTS V2 tem 3 dígitos a mais** que V1 (ex: V1 `123456` → V2 `123456001`). Para comparação cross-version: remover os 3 últimos dígitos do V2.
- **Strategy de consórcio quitado** recebe sufixo `_quitada` (ex: `contemplacao_quitada`). Lookup precisa contemplar isso.
- **Campos `_antigo` em metadata V1** (consórcio): `valor_credito_antigo`, `valor_devedor_antigo`, `vccsle_yield_correction_antigo`, `tx_fra_ann_antigo`, `dt_contemplacao_prev_antigo`, `valor_lance_embutido_antigo`, `valor_devedor_presente_antigo`, `valor_devedor_atualizado_antigo`. **`_antigo` tem precedência** sobre o sem sufixo: `coalesce(_antigo, base)`.

## Campos que parecem migrados mas são derivados

(detalhe completo em nexa_ai_prompts/engine-team/schemas/v2_computed_fields.md)

- **FGTS `spread_over_indexer`**: NÃO vem de `tx_cessao`. É calculado via `IRR(dc, acquisition_value, face_value, period=360)`.
- **FGTS `spread_over_cdi`**: derivado de `spread_over_indexer` via curva ETTJ — não é cópia direta do `spread_over_cdi` do metadata V1.
- **FGTS `indexer_percentage`**: sempre `0` (PREFIXADO) — **na tabela `fgts` (parcela)**. Não confundir com `securitization_series.indexer_percentage`, que é `1.0` mesmo em séries PREFIXADO (a taxa fixa fica em `spread_over_indexer`).
- **Consórcio `face_value`**: corrigido via FRA — não é o `face_value_original`.
- **Consórcio `maturity_date`**: `maturity_date_original` + 1 dia útil — não é cópia direta.
- **Consórcio `contemplation_value`**: `vccsle_calcs.vc - vccsle_calcs.vle` (cálculo).

## Defaults silenciosos

- **`wallet_fidc`**: default `"1"` se ausente em V1.
- **`positions.metadata.currency`**: V1 sempre `"BRL"`, exceto NTN-I onde precisa ser `"USD"`. ETL pode silenciosamente assumir BRL.
- **`valuation_methodologies` default**: `amortized_cost` para todos asset classes. Consórcio tem outras (`amortized_cost_original`, `face_value`, `zero_spread`).
- **`cession_id` (FGTS)**: contador sequencial de batch ETL — não há tabela `cessions` nem fonte V1. Records do mesmo batch compartilham o id.
- **NTN-I cria 1 entity por data de vencimento** (`NTN-I/YYYY-MM-DD`), não por título individual.

## V1 vs V2: conceitos sem equivalente

- **`aux_ids` (UUID bridge)**: V2 usa integer FKs em todo lugar; UUIDs V1 viram lookups durante ETL.
- **`API_event_ingest`**: V1-only (queue de ingestão), sem equivalente V2.
- **`ownership` table**: V1-only, sem equivalente V2.
- **`ratings` table**: virou `risks` em V2 (estrutura diferente, não cópia direta).
- **`logs.details JSONB`**: dropado em V2.
- **Token blockchain fields** (`fundingTokenAddress`, `spenderTokenAddress`, `projectOwner`): V1-only, não armazenados em V2.

## Casos com fonte fora do JSONB V1

- **FGTS `obligor_*`** (bank, uf, city, neighbourhood, street, zip_code, gender, birthday): vêm do **arquivo de elegibilidade CEF**, não do metadata V1. Idem `cef_uuid`, `cef_protocol`, `contract_min/max_maturity_date`.
- **Token `structure_id`**: passado explicitamente via API como `token_structure` (string), resolvido via lookup em `token_structures`. Não vive no metadata V1.

## Validações úteis ao migrar / debugar

- Após inserir em `positions`: checar se `total_quantity` está consistente com a soma de `variation` do grupo (trigger deve ter rodado).
- Após inserir em `valuations`: checar se exatamente UM record do grupo `(asset_id, lot_id, methodology_id)` tem `last_valuation_flag = TRUE`.
- FGTS migrado: contagem de `fgts` em V2 deve bater com contratos V1 que passaram nos gates de elegibilidade — divergência geralmente é janela de vencimento (`maturity > hoje + 15 dias`).
- Consórcio: verificar se `quota_outstanding_balance` usou `_antigo` quando presente (erro comum: ignorar precedência).
