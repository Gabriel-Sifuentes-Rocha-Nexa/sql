# CLAUDE.md — Projeto Engine V1 → V2 Query Migration

## Objetivo

Portar as queries SQL do **engine V1 (Supabase, padrão `securities + metadata JSONB`)** para o **engine V2 (AWS PostgreSQL, tabelas tipadas por asset class)**, mantendo o resultado equivalente. Não é migração de dados — é migração de queries.

**Fonte das queries V1**: [queries/engine_queries_v1.txt](queries/engine_queries_v1.txt)
**Destino das queries V2**: [queries/v2/](queries/v2/) (um arquivo `.sql` por query, numerados 01-11)

---

## Estrutura de pastas

```
v1v2/
├── CLAUDE.md                ← este arquivo (guia de trabalho)
├── _README.md               ← índice cross-team da documentação
├── queries/
│   ├── engine_queries_v1.txt        ← queries V1 originais (input)
│   └── v2/                          ← queries V2 portadas (output, uma por arquivo)
│       ├── 01_public_offer_metadata.sql
│       ├── 02_nxco_metadata.sql
│       ├── 03_nxni_metadata.sql
│       ├── 04_underlying.sql
│       ├── 05_fractional.sql
│       ├── 06_nxco_cr_cash_flow.sql
│       ├── 07_nxco_nao_cr_cash_flow.sql
│       ├── 08_fgts_cr_cash_flow.sql
│       ├── 09_fgts_nao_cr_cash_flow.sql
│       ├── 10_ntni_cr_cash_flow.sql
│       └── 11_ntni_nao_cr_cash_flow.sql
├── schemas/
│   ├── v1_schema.md                 ← DDL V1 (Supabase)
│   ├── v2_schema.md                 ← DDL V2 (AWS Postgres) — autoritativa
│   ├── db_diagram_v2.txt            ← DBML V2 completo (com triggers/procedures)
│   └── engine_db.dbml               ← DBML V2 enxuto
├── v1_metadata/
│   ├── v1_metadata_consortium.md            ← JSONB consórcio (NXCO)
│   ├── v1_metadata_entities.md              ← JSONB entidades (issuer/corporate/spv/fund)
│   ├── v1_metadata_fgts.md                  ← JSONB FGTS
│   ├── v1_metadata_other_assets.md          ← JSONB token / NTN-I / CDB / spv_series
│   └── v1_metadata_positions_valuations_transactions.md
├── v2_reference/
│   └── v2_computed_fields.md        ← colunas V2 derivadas / não migradas
└── conventions/
    ├── naming_conventions.md        ← nomenclatura V1 vs V2 (CRs, holders, ativos)
    └── gotchas.md                   ← armadilhas (triggers, sufixos, FKs estranhas)
```

---

## Inventário de queries V1 ↔ V2

Cada query V1 (bloco em `queries/engine_queries_v1.txt`) corresponde a um arquivo `.sql` em `queries/v2/`:

| # | Query V1 | Arquivo V2 | Asset class | Tabelas V2 alvo |
|---|---|---|---|---|
| 1 | **Public Offer — Obter metadados do Asset** | [01_public_offer_metadata.sql](queries/v2/01_public_offer_metadata.sql) | securitization_series (`spv_series`) | `securitization_series`, `entities` |
| 2 | **NXCO — Obter metadados do Asset** | [02_nxco_metadata.sql](queries/v2/02_nxco_metadata.sql) | consórcio | `consortiums`, `entities` |
| 3 | **NXNI — Obter metadados do Asset** | [03_nxni_metadata.sql](queries/v2/03_nxni_metadata.sql) | NTN-I (`titulo_publico`) | `ntnis`, `valuations`, `entities` |
| 4 | **Obter underlying (token)** | [04_underlying.sql](queries/v2/04_underlying.sql) | token | `tokens`, `entities` |
| 5 | **Verificar se é fracionado** | [05_fractional.sql](queries/v2/05_fractional.sql) | securitization series count | `securitization_series` |
| 6 | **NXCO CR — Cash Flow** | [06_nxco_cr_cash_flow.sql](queries/v2/06_nxco_cr_cash_flow.sql) | consórcio (CR) | `consortiums`, `positions`, `expected_cash_flows` |
| 7 | **NXCO Não CR — Cash Flow** | [07_nxco_nao_cr_cash_flow.sql](queries/v2/07_nxco_nao_cr_cash_flow.sql) | consórcio (não CR) | `consortiums`, `expected_cash_flows` |
| 8 | **FGTS CR — Cash Flow** | [08_fgts_cr_cash_flow.sql](queries/v2/08_fgts_cr_cash_flow.sql) | FGTS (CR) | `fgts`, `positions`, `expected_cash_flows` |
| 9 | **FGTS Não CR — Cash Flow** | [09_fgts_nao_cr_cash_flow.sql](queries/v2/09_fgts_nao_cr_cash_flow.sql) | FGTS (não CR) | `fgts`, `expected_cash_flows` |
| 10 | **NTNI CR — Cash Flow** | [10_ntni_cr_cash_flow.sql](queries/v2/10_ntni_cr_cash_flow.sql) | NTN-I (CR) | `ntnis`, `positions`, `expected_cash_flows` |
| 11 | **NTNI Não CR — Cash Flow** | [11_ntni_nao_cr_cash_flow.sql](queries/v2/11_ntni_nao_cr_cash_flow.sql) | NTN-I (não CR) | `ntnis`, `expected_cash_flows` |

**Padrão de input**: `${ticker}` (nome do CR/token — ex: `CR-FGTS-1`, `CR-CONSORTIUMS-1`, `CR-NTNI-1`). Em V1 era `CR-Consorcio-N` — usar `naming_conventions.md` para tradução.

**Padrão CR vs Não CR**: queries "CR" agregam **posições reais** (via `positions`, filtrando pelo holder = issuer do CR ou pelo `event_code`); queries "Não CR" agregam **composição teórica** do CR (via `metadata->composition` em V1).

---

## Transformações V1 → V2 essenciais

### Padrão estrutural
| V1 | V2 |
|---|---|
| `securities` + `metadata JSONB` para todos os ativos | tabela tipada por asset class (`consortiums`, `fgts`, `ntnis`, `tokens`, `cdbs`, `securitizations`, `securitization_series`) |
| `aux_id UUID` em todo lugar (bridge `aux_ids`) | `id integer` direto (FK para `entities.id`) |
| `entities.aux_id UUID` | `entities.id SERIAL` |
| `positions.holder_aux_id` + `asset_aux_id` | `positions.holder_id` + `asset_id` (FK `entities`) |
| `positions.metadata->>'event_related'` | `positions.event_code` (text) |
| `transactions.asset_aux_id` | `transactions` migrou para `positions` em V2 (com `transaction_type_id` FK) |
| `securities.code` / `name` / `full_name` | `entities.name` (único) + tabela específica do ativo |
| `metadata->>'composition'` array | depende do asset class (ver abaixo) |

### Composição V1 (`securities.metadata->'composition'`)
Em V1, um CR (security pai) tem `metadata->'composition'` listando `{asset_aux_id, amount, ...}` dos ativos subjacentes. Em V2:
- **Consórcio/FGTS**: composição vira holdings reais via `positions` (CR é uma entity, posições mostram quais cotas/parcelas ele detém).
- **NTN-I**: idem (CR holding NTN-I vertices).
- **Token**: `metadata->'composition'` → tabela `tokens_underlyings` (**ainda não criada no schema V2** — verificar antes de usar).

### Joins via UUID
Toda query V1 que faz `JOIN ... ON s2.aux_id = (composition->>'asset_aux_id')::uuid` precisa, em V2, virar **JOIN por integer FK** via `positions.asset_id` ou `entities.id` direto. **`aux_ids` não existe em V2.**

### Indexers
| V1 (string em metadata) | V2 (FK `indexers.id`) |
|---|---|
| `"FIPE"` | `IPC-FIPE` |
| `"CDI"` | `CDI` |
| `"IPCA"` | `IPCA` |
| FGTS sempre prefixado | `PREFIXADO` (FGTS sempre tem `indexer_percentage = 0`) |

### Amount semântica
**`amount` no domínio Engine V1/V2 = quantidade**, NUNCA valor financeiro.
- V1 `composition[].amount` / `i.amount` → V2 `positions.total_quantity`.
- V1 `series_issuance_amount` → V2 `securitization_series.quantity` (mapeamento direto).
- Para obter **valor financeiro**: multiplicar quantidade × preço unitário (`face_value`, `credit_value`, `initial_price`, etc.).

---

## Quirks críticos do V2 (não esquecer)

Detalhe completo em `conventions/gotchas.md` e `schemas/v2_schema.md`. Resumo do que mais bate:

1. **`positions.total_quantity` e `last_position_flag` são mantidos por trigger** — não SELECT na soma de `variation`; use `total_quantity` direto. Para "posição atual", filtrar `WHERE last_position_flag = TRUE`.
2. **`valuations.last_valuation_flag` é trigger** — para "última valuação", filtrar `WHERE last_valuation_flag = TRUE`.
3. **`expected_cash_flows.currency_id` aponta pra `entities.id`**, não `currencies.id` (quirk legado).
4. **`securitization_series.id` é FK para `entities.id`** (não auto-incremento próprio). Inserção exige entity antes.
5. **Tabelas de ativos têm `id = entities.id`** — `consortiums.id`, `fgts.id`, `ntnis.id`, `tokens.id`, `cdbs.id`, `securitizations.id` **todos** são FKs pro entity correspondente. Para juntar entity ↔ asset: `JOIN entities e ON e.id = <asset_table>.id`.
6. **Holder Nexa**: V1 = `Nexa Digital Assets SA`, V2 = `NEXA DIGITAL ASSETS SA` (uppercase).
7. **CR de consórcio**: V1 = `CR-Consorcio-{N}`, V2 = `CR-CONSORTIUMS-{N}` (uppercase + plural inglês). FGTS e NTN-I são idênticos em V1/V2.
8. **Contrato FGTS V2 tem 3 dígitos a mais** que V1.
9. **Unique key de positions**: `(date, holder_id, asset_id, financial_account_id)` — `lot_id` NÃO está na unique. `last_position_flag` é particionado por `(holder, asset, lot, financial_account)`. Se mesmo `(holder, asset)` aparece em múltiplos `financial_account_id` ou `lot_id`, JOIN simples por `last_position_flag` pode trazer múltiplas linhas — considerar `GROUP BY` defensivo se isso for um problema.

---

## Fluxo recomendado para portar uma query V1

1. **Identificar o asset class** da query V1 (consórcio / FGTS / NTN-I / token / public offer / SPV series).
2. **Abrir o `v1_metadata/v1_metadata_<asset>.md` correspondente** — tem o mapeamento campo a campo.
3. **Listar todos os caminhos JSONB que a query V1 acessa** (`metadata->'linhas'->0->'recebivel'->'valor_compra'`, etc.) e ver onde cada um foi parar em V2 (coluna direta na tabela tipada, derivado por ETL, ou em outra tabela).
4. **Ler `schemas/v2_schema.md` E `schemas/db_diagram_v2.txt`** pra confirmar nomes exatos de colunas, FKs, e quirks de triggers. Não confiar só no `v2_schema.md` resumido — DBMLs têm DDL completo.
5. **Checar `conventions/naming_conventions.md`** se a query filtra por `${ticker}` ou nome de holder — pode precisar adaptar o nome.
6. **Conferir `v2_reference/v2_computed_fields.md`** se a query depende de algum campo que **não migrou** (`maturity_date`, `face_value`, `spread_over_indexer` FGTS, etc.) — esses têm fórmulas/triggers próprias em V2.
7. **Criar um arquivo `queries/v2/NN_<nome_descritivo>.sql`** com a query, mantendo a estrutura (CTE / parâmetros `${ticker}` / GROUP BY) o mais próximo possível da original.
8. **Header de cada arquivo** deve incluir: número/nome, `V1 source`, mapping V1→V2, e a query V1 original comentada (para comparação lado a lado).

---

## Padrão de saída esperado em cada arquivo de `queries/v2/`

```sql
-- ============================================================
-- N. Nome da Query — descrição curta
-- V1 source: ../engine_queries_v1.txt, section "..."
-- Convenções gerais: ver ../../CLAUDE.md
--
-- Mapping V1 → V2:
--   <caminho JSONB V1>  → <coluna V2>
--   ...
-- ------------------------------------------------------------
-- V1 ORIGINAL (Supabase, securities + metadata JSONB):
-- ------------------------------------------------------------
-- <query V1 comentada linha a linha>
-- ============================================================
<query V2 funcional>
```

Cabeçalho explícito + V1 comentado + V2 funcional. Não inventar abstrações nem helpers — manter cada query autocontida.

---

## Coisas que **não** estão neste projeto

- Não há código de ETL aqui (a migração de dados V1→V2 é tema de outro projeto). Este projeto é só **queries de leitura**.
- Não há credenciais ou conexão de banco. Queries devem ser revisadas/testadas pelo usuário no ambiente apropriado.
- Não modificar schemas (V1 ou V2) — eles são apenas referência aqui.
