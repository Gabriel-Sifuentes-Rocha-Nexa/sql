---
name: Reference — V1 Consortium Metadata & V1→V2 Field Mapping
description: Exact structure of securities.metadata JSONB for consortium asset types, plus field-level V1→V2 mapping
type: reference
tags: [tipo/referência, conceito/migração, team/engine, produto/consórcio]
resumo: "Estrutura JSONB de consórcio em V1 (3 tipos, mesma metadata) e mapeamento campo a campo para tabela V2 consortiums"
---

## Tipos V1 para Consórcios

Os três tipos V1 compartilham **estrutura de metadata idêntica**. A estratégia é codificada dentro de `metadata.internal.strategy`:

| V1 `securities.type` | `internal.strategy` |
|---|---|
| `cota de consorcio - cancelada` | `"cancelada"` |
| `cota de consorcio - contemplacao` | `"contemplacao"` |
| `cota de consorcio - contemplada` | `"contemplada"` |

Todos os três mapeiam para a tabela V2 `consortiums` (+ row em `entities`).

---

## Chaves top-level do metadata

```
metadata = {
  "codigo":    string   -- código do originador/fundo (ex: "CS61"); usado para lookup do originador
  "data":      string   -- data de aquisição/emissão (ISO date)
  "fundo":     string   -- identificador do fundo cessionário (CNPJ ou código interno)
  "tipo":      string   -- sempre "consorcio", não armazenado em V2
  "internal":  object   -- todos os campos financeiros e resultados de cálculo (ver abaixo)
  "linhas":    array    -- detalhe do recebível + administradora (sempre usa index 0)
  "principal": object   -- info do fundo, cedente, pagamento, originador (ver abaixo)
  "new_yield":      number  -- OPCIONAL: yield reprecificado (~60% populado em contemplacao)
  "new_yield_date": string  -- OPCIONAL: data do evento de reprecificação
}
```

---

## Objeto `metadata.internal`

```
internal = {
  "dc":          int    -- dias corridos (computado, não armazenado em V2)
  "du":          int    -- dias úteis (computado, não armazenado em V2)
  "du_max":      int    -- máximo dias úteis (computado, não armazenado em V2)
  "status":      string -- "ativa" | "baixada" → status_id FK
  "checked":     string -- "sampling" | "directly" | null → enum checked
  "tx_ipca":     float  -- % bruto; dividir por 100 → implied_inflation_ann
  "strategy":    string -- "cancelada" | "contemplacao" | "contemplada" → strategy_id FK
                           NOTE: consórcios quitados recebem sufixo "_quitada"
  "tx_cessao":   float  -- taxa de cessão bruta; NÃO usada diretamente (usar yield_correction.tx_spread_yield_correction)
  "tx_spread":   float  -- spread bruto; NÃO usado diretamente
  "adm_aux_id":  uuid   -- UUID do administrador (V1-only, não usado na migração V2)
  "pdd_policy":  string -- string vazia na prática, não armazenado em V2
  "provisions": {
    "saldo_devedor":      float -- saldo devedor em provisões (não armazenado diretamente)
    "remuneracao_fixa":   float → commissions_payable
    "taxa_transferencia": float → transfer_fees_payable
  }
  "vl_credito":  float  -- valor de crédito (igual a linhas[0].recebivel.valor_credito)
  "tx_comissao": float  -- taxa de comissão (não mapeado diretamente)
  "vl_contrato": float  -- valor do contrato (NÃO usado para face_value_original; ver yield_correction)
  "vl_investido": float -- valor investido (NÃO mapeado; acquisition_price vem de linhas)
  "carteira_fidc": string -- "1"|"2"|"3" → wallet_fidc; default "1"
  "maturity_date": string -- → maturity_date_original
  "dt_contemplado": string|null → contemplation_date
  "aux_transferida": bool -- flag legado, não armazenado em V2
  "cota_tokenizavel": bool -- não armazenado em V2
  "settled_outstanding_balance": bool -- flag computado, não armazenado em V2
  "strategy_expected_cash_flow": array -- sempre [] na prática
  "tx_cessao_calcs": {
    "vccsle_calcs": {
      "vc":    float -- valor de crédito (bruto)
      "vle":   float → embedded_bid_value
      "vccsle": float -- valor presente (líquido de lance embutido); usado para face_value_original
      "tx_fra_ann":  float → assignment_fra (fallback: tx_fra_ann_antigo tem precedência)
      "dt_resgate_prev": string → expected_maturity_date
      "dt_contemplacao_prev": string → expected_contemplation_date (fallback: _antigo tem precedência)
    }
    "vpsdsle_calcs": {
      "sdcc":       float → quota_outstanding_balance
      "vpsdsle":    float → presentvalue_outstanding_balance
      "cdi_devedor": float → cdi_debtor
    }
  }
  "yield_correction": {
    "yield_correction":              float → yield_correction (fator escalar)
    "vccsle_yield_correction":       float → face_value_original (fallback: _antigo tem precedência)
    "tx_spread_yield_correction":    float -- % bruto; dividir por 100 → spread_over_cdi
  }
}
```

---

## Objeto `metadata.linhas[0]` (sempre usar index 0)

```
linhas[0] = {
  "recebivel": {
    "tipo_bem":          string -- "auto" → "AUTOMOTOR", senão "OUTRO" → underlying_asset_id FK
    "cota_numero":       string → quota_number
    "grupo_numero":      string → quota_group_number
    "valor_compra":      float  → acquisition_price (original)
    "grupo_termino":     string → group_end_date
    "valor_credito":     float  → credit_value (fallback: valor_credito_antigo tem precedência)
    "valor_devedor":     float  → quota_outstanding_balance (fallback: valor_devedor_antigo)
    "comissao_valor":    float  → commission_value
    "contrato_numero":   string → contract_number
    "indice_reajuste":   string → indexer FK ("FIPE"→"IPC-FIPE", outros diretos)
    "transfere_fundo":   string → transferred_to_fund (cast int→bool)
    "valor_lance_embutido":  float  → embedded_bid_value (fallback: _antigo)
    "valor_devedor_presente": float → presentvalue_outstanding_balance (fallback: _antigo)
    "valor_devedor_atualizado": float → updated_outstanding_balance (fallback: _antigo)
    "valor_taxa_transferencia": float → transfer_fee_value
  }
  "administradora": {
    "nome":      string → trustee (entity lookup; normalizar: remover pontos, uppercase)
    "documento": string -- CNPJ (usado para entity lookup)
  }
}
```

---

## Objeto `metadata.principal`

```
principal = {
  "fundo": {
    "nome":      string -- nome do fundo
    "documento": string → assignee (entity lookup por CNPJ)
  }
  "cedente": {
    "nome":      string → assignor (normalizar: trim, uppercase, remover pontos)
    "documento": string -- CNPJ do cedente (para entity lookup)
  }
  "pagamento": {
    "banco":          string → bank
    "conta":          string → account
    "agencia":        string → agency
    "conta_tipo":     string → account_type
    "conta_digito":   string → account_digit
    "agencia_digito": string → agency_digit
  }
  "originador": {
    "nome":      string → originator (entity lookup; normalizado)
    "documento": string -- CNPJ (para entity lookup)
  }
}
```

---

## Mapeamento completo V1 → V2

| Fonte V1 | Coluna V2 | transformação |
|---|---|---|
| `securities.full_name` | `consortiums.code` | direto |
| `metadata.fundo` | `consortiums.assignee_id` | entity lookup por CNPJ |
| `metadata.principal.cedente.nome` | `consortiums.assignor` | trim + uppercase + remover pontos |
| `metadata.principal.originador.nome` | `consortiums.originator_id` | entity lookup + normalizar |
| `metadata.principal.pagamento.banco` | `consortiums.bank` | direto |
| `metadata.principal.pagamento.conta` | `consortiums.account` | direto |
| `metadata.principal.pagamento.agencia` | `consortiums.agency` | direto |
| `metadata.principal.pagamento.conta_tipo` | `consortiums.account_type` | direto |
| `metadata.principal.pagamento.conta_digito` | `consortiums.account_digit` | direto |
| `metadata.principal.pagamento.agencia_digito` | `consortiums.agency_digit` | direto |
| `metadata.internal.strategy` | `consortiums.strategy_id` | lookup consortium_strategies; quitados → sufixo "_quitada" |
| `metadata.linhas[0].recebivel.tipo_bem` | `consortiums.underlying_asset_id` | "auto"→"AUTOMOTOR", senão "OUTRO" |
| `internal.tx_cessao_calcs.vpsdsle_calcs.cdi_devedor` | `consortiums.cdi_debtor` | cast float |
| `metadata.linhas[0].recebivel.cota_numero` | `consortiums.quota_number` | direto |
| `metadata.data` | `consortiums.acquisition_date` | date |
| `metadata.linhas[0].recebivel.grupo_termino` | `consortiums.group_end_date` | date |
| `metadata.linhas[0].recebivel.grupo_numero` | `consortiums.quota_group_number` | direto |
| `metadata.linhas[0].recebivel.valor_compra` | `consortiums.acquisition_price` | cast float |
| `coalesce(recebivel.valor_credito_antigo, recebivel.valor_credito)` | `consortiums.credit_value` | antigo tem precedência |
| `coalesce(recebivel.valor_devedor_antigo, recebivel.valor_devedor)` | `consortiums.quota_outstanding_balance` | antigo tem precedência |
| `metadata.linhas[0].recebivel.comissao_valor` | `consortiums.commission_value` | cast float |
| `vccsle_calcs.vc - vccsle_calcs.vle` | `consortiums.contemplation_value` | cálculo derivado |
| `coalesce(yield_correction.vccsle_yield_correction_antigo, yield_correction.vccsle_yield_correction)` | `consortiums.face_value_original` | antigo tem precedência |
| `internal.yield_correction.yield_correction` | `consortiums.yield_correction` | cast float |
| *(calculado de face_value_original via curvas FRA)* | `consortiums.face_value` | não existe em V1 |
| `metadata.linhas[0].recebivel.contrato_numero` | `consortiums.contract_number` | direto |
| `vccsle_calcs.dt_resgate_prev` | `consortiums.expected_maturity_date` | date |
| `metadata.internal.maturity_date` | `consortiums.maturity_date_original` | date |
| *(calculado de maturity_date_original com offset de dia útil)* | `consortiums.maturity_date` | não existe em V1 |
| `recebivel.indice_reajuste` | `consortiums.indexer_id` | "FIPE"→"IPC-FIPE"; lookup indexers |
| `recebivel.transfere_fundo` | `consortiums.transferred_to_fund` | int→bool |
| `coalesce(recebivel.valor_lance_embutido_antigo, recebivel.valor_lance_embutido)` | `consortiums.embedded_bid_value` | antigo tem precedência |
| `coalesce(recebivel.valor_devedor_presente_antigo, recebivel.valor_devedor_presente)` | `consortiums.presentvalue_outstanding_balance` | antigo tem precedência |
| `coalesce(recebivel.valor_devedor_atualizado_antigo, recebivel.valor_devedor_atualizado)` | `consortiums.updated_outstanding_balance` | antigo tem precedência |
| `recebivel.valor_taxa_transferencia` | `consortiums.transfer_fee_value` | cast float |
| `linhas[0].administradora.nome` | `consortiums.trustee_id` | entity lookup; normalizar string |
| `metadata.internal.status` | `consortiums.status_id` | lookup statuses |
| `metadata.internal.checked` | `consortiums.checked` | enum: not_checked/directly/sampling |
| `metadata.internal.tx_ipca / 100` | `consortiums.implied_inflation_ann` | dividir por 100 |
| `internal.yield_correction.tx_spread_yield_correction / 100` | `consortiums.spread_over_cdi` | dividir por 100 |
| `coalesce(vccsle_calcs.tx_fra_ann_antigo, vccsle_calcs.tx_fra_ann)` | `consortiums.assignment_fra` | antigo tem precedência |
| `coalesce(vccsle_calcs.dt_contemplacao_prev_antigo, vccsle_calcs.dt_contemplacao_prev)` | `consortiums.expected_contemplation_date` | antigo tem precedência |
| `metadata.internal.dt_contemplado` | `consortiums.contemplation_date` | date ou null |
| *(definido durante operação de settlement)* | `consortiums.discharge_date` | não existe em V1 metadata |
| `coalesce(metadata.internal.carteira_fidc, '1')` | `consortiums.wallet_fidc` | default "1" |
| `metadata.internal.provisions.remuneracao_fixa` | `consortiums.commissions_payable` | direto |
| `metadata.internal.provisions.taxa_transferencia` | `consortiums.transfer_fees_payable` | direto |

### Campos sem equivalente em V2
- `internal.dc`, `du`, `du_max` — valores temporais computados
- `internal.tx_cessao`, `tx_spread` — supersedidos pelas versões do yield_correction
- `internal.cota_tokenizavel`, `settled_outstanding_balance`, `aux_transferida`, `pdd_policy` — sem coluna V2
- `recebivel.cota_codigo` — UUID; V2 usa `securities.full_name` como code
- `principal.cedente` campos de endereço — não armazenados
- `principal.registradora`, `certificadora` — não armazenados
