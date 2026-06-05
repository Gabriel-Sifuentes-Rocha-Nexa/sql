# CLAUDE.md — Projeto "corrigir amortização de token" (Engine V2)

> **LEIA ISTO ANTES DE QUALQUER QUERY OU EDIÇÃO.** Pular esta etapa já custou tempo
> (conectei no banco errado e investiguei sem entender o schema). A ordem abaixo não é opcional.

## Objetivo

Investigar e corrigir uma **amortização processada errada no Engine V2** que deixou o
**preço do ativo (`valuations.clean_price`) negativo**, **comparando com o V1**. Trabalho de
leitura/diagnóstico e, com OK do usuário, correção **apenas na cópia LOCAL** do V2.

## Artefato principal: [`investigacao.ipynb`](investigacao.ipynb)

Notebook Jupyter que conecta no **V2 (local)** e no **V1 (Supabase prod)** e roda a investigação
(Fase 1 = identificar ativos+data; Fase 2 = evento+valores; seção V1 = comparação). Ambiente:
venv em `.venv/` (criar com `py -m venv .venv`; deps: pandas, sqlalchemy, psycopg2-binary, matplotlib, ipykernel, nbconvert).

**Guardrails (read-only, NUNCA escrever — V1 é prod):** (1) toda conexão abre com
`default_transaction_read_only=on`; (2) `assert_select_only()` só deixa passar 1 `SELECT`/`WITH`
e bloqueia DDL/DML (até `WITH ... DELETE`); (3) toda query termina em `ROLLBACK`. Nunca remover
essas camadas. URLs no [`.env`](.env): `DATABASE_URL` (V2) e `V1_DATABASE_URL` (V1, papel read-only).

## 0. Documentação a ler PRIMEIRO (nesta ordem)

1. [`../schemas/v2_schema.md`](../schemas/v2_schema.md) — schema autoritativo do V2 (tabelas, FKs, quirks, metodologias). A base `engine` segue ESTE schema (plural, com `securitization_series` / `securitization_payment_schedules`).
2. [`../conventions/gotchas.md`](../conventions/gotchas.md) — armadilhas: triggers (`total_quantity`, `last_*_flag`), FKs incomuns, normalização de nomes, campos derivados.
3. [`../v2_reference/financial_accounts_and_cash_flow.md`](../v2_reference/financial_accounts_and_cash_flow.md) — contas contábeis (RESERVATION / colateral / investments), token→série, cash flow.
4. [`../v2_reference/v2_computed_fields.md`](../v2_reference/v2_computed_fields.md) — colunas calculadas/trigger/derivadas (não vêm de cópia direta).
5. [`../schemas/db_diagram_v2.txt`](../schemas/db_diagram_v2.txt) — DBML completo (triggers/procedures) quando precisar do DDL exato.
6. [`../CLAUDE.md`](../CLAUDE.md) — guia geral do projeto de migração V1→V2 (contexto e convenções).

Confira nomes de coluna/tabela contra o schema **antes** de escrever a query — não confie só na memória.

## 1. Ambiente — restrição CRÍTICA e ARMADILHA da porta 5432

- **NUNCA tocar o banco V1 nem o V2 de PROD.** Toda alteração para testar/validar vai **só** na cópia LOCAL.
- **A cópia LOCAL do V2 = PostgreSQL 17 NATIVO do Windows** (serviço `postgresql-x64-17`), database **`engine`** (~6.9 GB, ~16,3 M valuations). O db `postgres` dessa instância é VAZIO — não é ele.
- **ARMADILHA:** a porta 5432 tem DOIS postgres — o nativo (IPv4 `0.0.0.0`) **e** um container Docker `postgres` (IPv6 `::`, via `com.docker.backend`). `docker exec postgres psql` entra no CONTAINER, que é uma base DIFERENTE e reduzida (schema singular, só 26 valuations, `tokens` vazio) — **NÃO é a cópia do V2**.
- **SEMPRE conectar via TCP `-h 127.0.0.1` no db `engine`. NUNCA via `docker exec`.**
- Credenciais em [`.env`](.env) (gitignored): `postgres:postgres@127.0.0.1:5432/engine`.

```powershell
$env:PGPASSWORD="postgres"
& "C:\Program Files\PostgreSQL\17\bin\psql.exe" -h 127.0.0.1 -p 5432 -U postgres -d engine -c "SELECT count(*) FROM valuations;"
# sanidade: deve retornar ~16.328.680 (não 26). Se vier 26, você está no container errado.
```

## 2. Convenções de query

- **Sempre trocar id por NOME** na saída (JOIN em `entities`, `transaction_types`,
  `valuation_methodologies`, `financial_accounts`, `seniorities`) — o usuário lê por nome.
- Preço do ativo = `valuations.clean_price` (+ `accrued_interest`), por metodologia (`amortized_cost` é o padrão).
- Cuidado com **subquery correlacionada acidental**: `securitization_series` NÃO tem coluna
  `securitization_id`; a série liga na securitização-mãe por **`securitization_series.issuer_id = securitizations.id`**.
- `positions.total_quantity` e os `last_*_flag` são **mantidos por trigger** — não escrever direto.
- **Queries no V1 (Supabase):** ancorar o token por `securities.full_name` (ÚNICO); derivar a **série (CR filho)** do `metadata->'composition'` do token (campo `asset_aux_id`) — sem `ILIKE` nem nome chumbado. Em `transactions`/`valuations`, asset/from/to passam pela bridge `aux_ids` (uuid→ref+source); na amortização a perna **`from`** é o ativo amortizado (o `asset` é o caixa/BRL).
- **Notebook:** NÃO misturar `print()` + `display()` na mesma célula (o Jupyter agrupa stdout e rich output separados, descasando rótulo↔tabela) — gere UMA tabela como última expressão da célula.

## 3. Estado da investigação

- **Ativos afetados:** token `NXFSE26-1` + série `CR-FGTS-30-01-SENIOR` (mãe `CR-FGTS-30`); vencimento 2026-05-15.
- **Sintoma (original):** `clean_price = -1.42183` constante, 15/05 → 01/06 (18 valuations cada), token espelhando a série.
- **Causa-raiz (provada, [`investigacao.ipynb`](investigacao.ipynb) §2.3 e §3, comparada com V1):** no vencimento o V2 fez `clean_price = face − resgate_total = 100 − 101.42183 = −1.42183` — subtraiu do principal o **resgate TOTAL** (principal 100 + cupom 1.42183) em vez de só o principal. **V1 fez certo:** amortização em caixa de 101.42183/unid e PU → ~0. ⇒ bug é da lógica de vencimento do **ETL/engine V2**, não dos dados de origem. Depois o batch diário propagou o negativo 18 dias.
- **Booking de caixa também incompleto no V2:** a `AMORTIZATION` de 15/05 era uma posição **órfã** (única por `block_id` E `doc_id`): só a perna de caixa (BRL −1058,58), sem baixa de token/série nem caixa pros holders. Dos 1160 tokens, só 56 com terceiros (CR-FGTS-30 retém 1104+56).
- **AÇÃO APLICADA (2026-06-02):** rodado [`reset_amortizacao_local.py`](reset_amortizacao_local.py) com `COMMIT=True` no V2 local → apagadas 36 valuations `clean_price<0` (série+token) + a `AMORTIZATION` órfã. Trigger recompôs: valuation vigente voltou a `clean_price=100` (15/05). A diária normal de 15/05 foi MANTIDA.
- **Pendente:** o usuário re-lança a amortização pela API dele contra o V2 local; re-investigar se vem correta (`clean_price→0`, cupom em caixa, com baixa de token/série) ou se revela outro erro. Se for corrigir no engine: achar a rotina de vencimento.

## 4. Script de reset — [`reset_amortizacao_local.py`](reset_amortizacao_local.py)

Apaga os artefatos do bug **SÓ no V2 local**. Segurança: trava aborta se `DATABASE_URL` não for `127.0.0.1:5432/engine` (nunca V1/prod); **dry-run por padrão** (`COMMIT=False` → mostra preview e dá ROLLBACK); `COMMIT=True` aplica. Não mexe em `last_valuation_flag`/`total_quantity` (triggers recompõem). Rodar:
```powershell
cd "...\v1v2\corrigir_amortizacao_token"
.\.venv\Scripts\python.exe reset_amortizacao_local.py    # dry-run; depois editar COMMIT=True p/ aplicar
```
