---
name: Reference — Financial Accounts, Token→Série e Expected Cash Flow (V2)
description: Como financial_accounts ligam entidades por NOME (sem FK de owner), como resolver token→securitization_series e token→mãe, e como reconstruir o expected cash flow (CR vs Não CR) a partir das posições
type: reference
tags: [tipo/referência, conceito/cash-flow, conceito/colateral, team/engine]
resumo: "O modelo de contas contábeis V2 (RESERVATION / collateral / investments), a resolução de série via conta de colateral, e a fórmula de cash flow CR vs Não CR — com a armadilha do NULL na tradução literal do V1"
---

## financial_accounts ligam por NOME, não por FK

`financial_accounts` (`id`, `name UNIQUE`, `classification debit|credit`, `parent_id`) **não tem coluna de owner/entity**. O vínculo com a entidade dona vive na *convenção de nome*. Padrões observados:

| Padrão de nome | Conteúdo (via `positions.financial_account_id`) | Holder típico |
|---|---|---|
| `assets pledged as collateral - <token>` | colateral do token: 1 posição apontando para a **série** (ISSUANCE) **ou** para os ativos individuais (TOKENIZATION) | — |
| `RESERVATION-<issuer>` | cotas/parcelas **reservadas** para aquele CR (issuer) | o FIDC do fundo (ex: `FIDC NXCO`) |
| `investments` | conta **global** (todas as entidades); ativos detidos — filtrar por `holder_id` | a entidade detentora |
| `integralized tokens`, `token investments`, `cash and equivalents` | contas globais auxiliares | vários |

Implicações:
- Para achar a conta de um CR/token, **concatene o nome**: `fa.name = 'RESERVATION-' || issuer.name`, `fa.name = 'assets pledged as collateral - ' || token.name`. Há índice único em `name`, então a igualdade é barata.
- `investments` é **global**: SEMPRE filtre `positions.holder_id = <entidade>`. Sem o filtro você varre posições de todas as entidades.

## transaction_types no colateral

A posição dentro de `assets pledged as collateral - <token>` revela a estrutura do token:
- **`ISSUANCE`** → o subjacente é uma `securitization_series` (token securitizado).
- **`TOKENIZATION`** → o subjacente são ativos individuais (cota de consórcio, parcela FGTS, vértice NTN-I) — tokenização direta, **sem** securitização no meio.

## Token → mãe (CR) e Token → securitization_series

Dois conceitos distintos, fonte distinta:

- **Mãe (CR)** = `tokens.issuer_id` → `entities` (a securitization `CR-CONSORTIUMS-N` / `CR-FGTS-N`). Em tokenização direta, o issuer é o **FIDC**, não um CR.
- **Série específica** (`securitization_series`) = **NÃO** sai de `issuer_id`. `securitization_series.issuer_id` aponta para a mãe, então um CR fracionado tem **dezenas de séries** (ex: `CR-FGTS-30` tem ~60 séries `...-NN-SENIOR`). A série de UM token vem da **conta de colateral**:

```sql
-- série específica do token (NULL se for tokenização direta)
SELECT ss.id, series_e.name
FROM tokens tk
JOIN entities token_e          ON token_e.id = tk.id
JOIN financial_accounts fa     ON fa.name = 'assets pledged as collateral - ' || token_e.name
JOIN positions pos             ON pos.financial_account_id = fa.id
JOIN securitization_series ss  ON ss.id = pos.asset_id      -- só séries; descarta TOKENIZATION
JOIN entities series_e         ON series_e.id = ss.id
WHERE token_e.name = :ticker
GROUP BY ss.id, series_e.name;
```

Nomes de série seguem `<CR>-<NN>-<SENIORIDADE>` — ex: `CR-CONSORTIUMS-26-01-SINGLE` (não fracionado, "SINGLE"), `CR-FGTS-30-59-SENIOR` (fracionado).

## Expected Cash Flow: CR vs Não CR

Ambos somam um **valor de face** agrupado pelo **mês de vencimento** do ativo subjacente. A diferença é *de quem* são as posições:

| | Não CR (composição teórica) | CR (posições reais reservadas) |
|---|---|---|
| Fonte das posições | conta `assets pledged as collateral - <token>` (TOKENIZATION) | `RESERVATION-<issuer>` **+** `investments` (holder = issuer) |
| Valor | `SUM(face_value)` — **sem** multiplicar por quantidade | `SUM(face_value * total_quantity)` — multiplica pela quantidade detida |
| Dimensão de data | `expected_maturity_date` (consórcio) / `maturity_date` (FGTS) | idem |

`face_value` é o valor de resgate no vencimento (corrigido por curva/FRA — ver `v2_computed_fields.md`), **não** `credit_value`.

### A armadilha do NULL (tradução literal do V1 quebra)

O V1 fazia: posições onde `holder = issuer OR event_related = issuer.name`, com `DISTINCT ON` da última, e `JOIN` no ativo. A tradução literal em V2:

```sql
JOIN positions pos ON (pos.holder_id = issuer.id OR pos.event_code = issuer.name)
JOIN consortiums c ON c.id = pos.asset_id   -- ZERA TUDO
```

…retorna **NULL**, porque as posições do issuer apontam para o **próprio token** e para a **securitization_series "-SINGLE"** — nunca para linhas de `consortiums`/`fgts`. O `JOIN` no ativo individual elimina todas as linhas → `SUM` sobre conjunto vazio → NULL.

A correção é buscar as cotas/parcelas onde elas realmente estão: nas contas `RESERVATION-<issuer>` e `investments`.

### Fórmula CR (validada)

```sql
WITH cr AS (
    SELECT issuer_e.id AS issuer_id, issuer_e.name AS issuer_name
    FROM tokens tk
    JOIN entities token_e  ON token_e.id = tk.id
    JOIN entities issuer_e ON issuer_e.id = tk.issuer_id
    WHERE token_e.name = :ticker
),
held AS (
    -- reservadas pro CR (qualquer holder; a conta já é específica do CR pelo nome)
    SELECT pos.asset_id, pos.total_quantity
    FROM cr
    JOIN financial_accounts fa ON fa.name = 'RESERVATION-' || cr.issuer_name
    JOIN positions pos ON pos.financial_account_id = fa.id AND pos.last_position_flag
    UNION ALL
    -- na conta investments do próprio CR (conta global → filtra holder)
    SELECT pos.asset_id, pos.total_quantity
    FROM cr
    JOIN financial_accounts fa ON fa.name = 'investments'
    JOIN positions pos ON pos.financial_account_id = fa.id
                      AND pos.holder_id = cr.issuer_id AND pos.last_position_flag
)
SELECT SUM(asset.face_value * held.total_quantity) AS expected_cash_flow_values,
       TO_CHAR(asset.<maturity_col>, 'YYYY-MM')     AS month_year_maturity
FROM held JOIN <consortiums|fgts> asset ON asset.id = held.asset_id
WHERE asset.<maturity_col> IS NOT NULL
GROUP BY month_year_maturity ORDER BY month_year_maturity;
```

- `last_position_flag = TRUE` é o equivalente V2 do `DISTINCT ON ... ORDER BY date DESC` do V1 (saldo corrente por posição). Mantido por trigger — não confundir com `SUM(variation)` (que dá o mesmo líquido, mas o flag é o idiomático).
- `<maturity_col>`: `expected_maturity_date` (consórcio), `maturity_date` (FGTS e NTN-I).
- `face_value`: consórcio/FGTS = `face_value`; NTN-I = `face_value_usd` (único campo de preço da tabela `ntnis`; mapeia o `ntni_base_pricing_price` do V1).
- Buckets que netam a zero (reservado e depois liberado) aparecem com valor 0 — correto.

### O ativo entra por ASSIGNMENT (comum aos 3 CRs)

Nas contas `RESERVATION-<issuer>` + `investments`, as posições do ATIVO subjacente (cota/parcela/vértice) têm tx_type **`ASSIGNMENT`** em consórcio, FGTS **e** NTN-I (com tx secundários ocasionais — `LOCK` em consórcio, `REDEMPTION` em FGTS — irrelevantes). **Não filtre por tx_type** na query CR: o `JOIN` na tabela do ativo já discrimina. `ISSUANCE`/`TOKENIZATION` são de **outra camada** (o colateral do token: série securitizada vs tokenização direta) — filtrar por eles zera o CR.

### NTN-I: o que realmente difere

A fórmula CR é **idêntica** à de consórcio/FGTS. As únicas diferenças do NTN-I:
- **Não há linha em `expected_cash_flows`** para o CR de NTN-I (consórcio e FGTS têm) → **sem oráculo** do engine; validar pela composição das posições. Esta é a diferença que importa.
- Valor = `ntnis.face_value_usd` (USD); maturity = `ntnis.maturity_date`.
- NTN-I cria **1 entity por data de vencimento** (ver `../conventions/gotchas.md`) → tende a poucos buckets.
- Como nas outras classes, há **dois tokens** por safra: tokenização **direta** (issuer = NEXA, ex. `NXNII27-1` → caminho Não CR, TOKENIZATION na colateral) e **securitizado** (issuer = `CR-NTNI-N`, ex. `NXNII27-2` → caminho CR). Isto não é específico do NTN-I.

### Performance: `UNION ALL` em vez de `OR`

Não junte as duas contas com `... ON pos.fa_id = fa.id AND (fa.name <> 'investments' OR pos.holder_id = issuer)`. O `OR` impede o planner de empurrar `holder_id = issuer` para dentro do scan da conta **global** `investments` → ele varre a conta inteira e filtra depois. Separar em dois branches `UNION ALL` torna cada predicado uma **igualdade** que o índice cobre. (Contas FGTS `RESERVATION-*` têm centenas de milhares de posições — isso importa.)

> Índice de `positions`: o único documentado é `unique(date, holder_id, asset_id, financial_account_id)`. Ele **lidera por `date`**, então lookup só por `financial_account_id` (4ª coluna) não é coberto. Estruture os predicados para casar com colunas-líder ou conte com bitmap/partial indexes do banco.

## expected_cash_flows: a tabela precomputada

O engine V2 materializa o fluxo em `expected_cash_flows` (`entity_id`, `date`, `value`, `currency_id`). Keyed pelo **issuer** (= a mãe/CR). Diferenças vs. a reconstrução crua das posições:
- usa a **data de pagamento real** (~2 semanas após o vencimento contratual), não o `maturity_date`;
- aplica ajuste de valor presente/curva (o valor pode divergir um pouco da soma crua de `face_value * qty`).

Quando o objetivo é o número *oficial* do engine, leia `expected_cash_flows` direto (join `entity_id = tk.issuer_id`). A reconstrução por posições reproduz a composição, mas não os ajustes de data/curva.
(Lembrete de `gotchas.md`: `expected_cash_flows.currency_id` → `entities.id`, não `currencies.id`.)
