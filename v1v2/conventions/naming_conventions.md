---
name: Reference — Naming Conventions V1 ↔ V2
description: How entity/holder/asset names differ between Engine V1 (Supabase) and V2 (AWS Postgres) — and when translation is required
type: reference
tags: [tipo/referência, conceito/migração, team/engine]
resumo: "Nomes de CRs, holders e ativos em V1 vs V2: onde são idênticos e onde precisam de conversão"
---

## CRs (SPVs de securitização)

| Asset class | V1 (Supabase) | V2 (AWS) | Conversão necessária? |
|---|---|---|---|
| FGTS | `CR-FGTS-{N}` | `CR-FGTS-{N}` | Não (idêntico) |
| Consórcio | `CR-Consorcio-{N}` (mixed case, palavra única) | `CR-CONSORTIUMS-{N}` (uppercase, plural inglês) | **Sim** |
| NTN-I | `CR-NTNI-{N}` (sem hífen no NTNI) | `CR-NTNI-{N}` | Não (idêntico) |

**Onde o nome V1 é usado em queries**:
- `entities.name` filter quando `entities.type = 'spv'` (queries de reserva e data-específicas)
- `positions.metadata->>'event_related'` filter (queries do tipo `nexa_reserved`)

## Holder Nexa (entidade operacional)

| Contexto | Nome |
|---|---|
| V1 `entities.name` | `Nexa Digital Assets SA` |
| V2 `entities.name` | `NEXA DIGITAL ASSETS SA` |

Qualquer query que filtre pelo holder Nexa precisa usar o nome correto para o banco alvo.

## Nomes de ativos (parcelas / cotas / vértices NTN-I)

### Parcelas FGTS

- Formato: `PARCELA_FGTS/{contrato}/{cpf_part}/YYYY-MM-01` (uppercase)
- V2 tem um **sufixo de 3 dígitos a mais no contrato** (ex: `PARCELA_FGTS/123456001/...`)
- Para comparar nomes entre V1 e V2: remover o sufixo de 3 dígitos do nome V2 antes de comparar

### Cotas de Consórcio

- Formato (idêntico em V1 e V2): `COTA-CONSORCIO-{admin}-{grupo}-{cota}-{contrato}` (uppercase)
- Nenhuma normalização necessária para comparação cross-version

### Vértices NTN-I

- Formato: `NTN-I/YYYY-MM-DD` (um entity por data de vencimento, não por título individual)
- Quantidade total rastreada via `positions`

## Contas contábeis (financial_accounts)

`financial_accounts` não tem FK de owner — o vínculo com a entidade está no **nome**, por concatenação:
- `RESERVATION-<issuer.name>` — cotas/parcelas reservadas para o CR.
- `assets pledged as collateral - <token.name>` — colateral do token (revela a série).
- `investments` — conta **global** (filtrar por `holder_id`).

Detalhe completo (resolução token→série, cash flow CR vs Não CR) em `v2_reference/financial_accounts_and_cash_flow.md`.

## Extensão para novos asset classes

Ao adicionar um novo asset class, definir explicitamente:
1. O padrão de nome do CR em V1 e V2 (idêntico ou com conversão)
2. O padrão de nome do ativo (parcela/cota/unidade) em V1 e V2
3. A lógica de normalização para comparação cross-version

Nunca hardcode regex ou nomes de tabela de asset fora do ponto central de conversão.
