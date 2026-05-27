---
name: Reference — V1 Positions/Valuations/Transactions Metadata
description: JSONB metadata content for positions, valuations, and transactions tables in V1 — all nearly empty, just currency
type: reference
tags: [tipo/referência, conceito/migração, team/engine]
resumo: "Metadata V1 de positions/valuations/transactions é quase vazia (só currency BRL) — colunas novas do V2 vêm de lógica de aplicação, não migração"
---

## Achado-chave: metadata V1 dessas tabelas é quase vazia

As tabelas `positions`, `valuations` e `transactions` do V1 armazenam apenas uma chave em `metadata JSONB`: **`currency: "BRL"`**.

Isso significa que as muitas colunas novas do V2 em `positions` (`lot_id`, `block_id`, `financial_account_id`, `transaction_type_id`, `last_position_flag`, `variation`, `total_quantity`, etc.) e em `valuations` (`lot_id`, `methodology_id`, `clean_price`, `accrued_interest`, `indexer_id`, `spread_over_indexer`, `spread_over_cdi`, `cash_flow`, `last_valuation_flag`) **não vêm de migração de dados V1** — são computadas ou atribuídas pela lógica de aplicação durante o ETL.

---

## positions.metadata

```
metadata = {
  "currency": string  -- sempre "BRL" → usado para inferir currency_id em V2
}
```

V1 `positions` também armazena `amount` e `available` como colunas top-level (fora do metadata). Em V2 esses viram `variation` e `total_quantity`, mas a semântica pode diferir.

---

## valuations.metadata

Único tipo observado: `type = 'pu'`.

```
metadata = {
  "currency": string  -- sempre "BRL" → valuations.currency_id (FK currencies)
}
```

A coluna `value` em V1 é um único número. Em V2 expande para `clean_price` + `accrued_interest` (componentes separados), calculados durante o ETL.

---

## transactions.metadata

Três tipos de transação observados, todos com metadata idêntico:

| V1 `transactions.type` | Equivalente V2 |
|---|---|
| `purchase` | transaction_types lookup |
| `real_cash` | transaction_types lookup |
| `managerial_cash` | transaction_types lookup |

```
metadata = {
  "currency": string  -- sempre "BRL"
}
```

V1 `transactions` usa `from_aux_id`, `to_aux_id`, `asset_aux_id` (UUIDs) → V2 usa integer FKs para `entities`.
