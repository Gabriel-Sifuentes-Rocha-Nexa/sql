# Índice de Queries

Catálogo de tudo em `queries/`. **Antes de criar uma query nova, procure aqui** se já existe algo equivalente (ou um util que resolve parte do problema).

Status: ✅ validada no banco · 🟡 feita, ainda não validada · 🔧 precisa de rework.

Como rodar (read-only): `& "../.venv/Scripts/python.exe" run_query.py <arquivo.sql> --ticker <valor>`
(o `${ticker}` é substituído pelo `--ticker`; entrada varia por query — ver coluna "Entrada").

⚠️ Vários arquivos têm o ticker **hardcoded como literal** (ex. Q6/Q8/Q10) em vez de `${ticker}` — nesses, o `--ticker` é **ignorado**; edite o valor no `WHERE`. A bônus (12) usa `${ticker}`.

---

## `v2/` — porte das 11 queries do Engine V1

Cada arquivo: header + V1 original comentada + V2 funcional + linha de exemplo. Entrada padrão = **nome do token** (`token_entity.name`), salvo indicação.

| # | Arquivo | O que retorna | Entrada | Status |
|---|---|---|---|---|
| 1 | [v2/01_public_offer_metadata.sql](v2/01_public_offer_metadata.sql) | Metadados do asset para oferta pública (série, emissão, preços, spread) | token | ✅ |
| 2 | [v2/02_nxco_metadata.sql](v2/02_nxco_metadata.sql) | Metadados do asset NXCO (consórcio) | token | ✅ |
| 3 | [v2/03_nxni_metadata.sql](v2/03_nxni_metadata.sql) | Metadados do asset NXNI (NTN-I) | token | ✅ |
| 4 | [v2/04_underlying.sql](v2/04_underlying.sql) | Underlying do token (`spv_underlyings`) + dados da securitização | token | ✅ |
| 5 | [v2/05_fractional.sql](v2/05_fractional.sql) | Se o token é fracionado (retorna linha só se >1 série) | token | ✅ |
| 6 | [v2/06_nxco_cr_cash_flow.sql](v2/06_nxco_cr_cash_flow.sql) | Cash flow **CR** consórcio: cotas reservadas/detidas pelo CR (`RESERVATION` + `investments`) | token | ✅ |
| 7 | [v2/07_nxco_nao_cr_cash_flow.sql](v2/07_nxco_nao_cr_cash_flow.sql) | Cash flow **Não CR** consórcio: composição teórica (colateral, TOKENIZATION) | token | ✅ |
| 8 | [v2/08_fgts_cr_cash_flow.sql](v2/08_fgts_cr_cash_flow.sql) | Cash flow **CR** FGTS (mesmo padrão da Q6) | token | ✅ |
| 9 | [v2/09_fgts_nao_cr_cash_flow.sql](v2/09_fgts_nao_cr_cash_flow.sql) | Cash flow **Não CR** FGTS | token | ✅ |
| 10 | [v2/10_ntni_cr_cash_flow.sql](v2/10_ntni_cr_cash_flow.sql) | Cash flow **CR** NTN-I (RESERVATION+investments; vértices via ASSIGNMENT) | token | 🟡 reescrita (padrão Q6/Q8), roda p/ NXNTNII27-1 (US$206.844,43); **sem oráculo** em `expected_cash_flows` |
| 11 | [v2/11_ntni_nao_cr_cash_flow.sql](v2/11_ntni_nao_cr_cash_flow.sql) | Cash flow **Não CR** NTN-I (vértices via colateral) | token | ✅ (usa `total_quantity` por vértice) |
| 12★ | [v2/12_cr_cash_flow_unified.sql](v2/12_cr_cash_flow_unified.sql) | **BÔNUS** (fora do porte): **CR** cash flow **unificada** consórcio+FGTS+NTN-I via `reference_table_id`; expõe `asset_class` e `currency` | token | ✅ bate com Q6/Q8/Q10 |
| 13★ | [v2/13_nao_cr_cash_flow_unified.sql](v2/13_nao_cr_cash_flow_unified.sql) | **BÔNUS** (fora do porte): **Não CR** cash flow **unificada** (colateral+TOKENIZATION) via `reference_table_id`; expõe `asset_class` e `currency` | token | ✅ bate com Q7/Q9/Q11 |

CR vs Não CR e a armadilha do NULL: ver `../v2_reference/financial_accounts_and_cash_flow.md`.
★ Bônus — fora das 11 do porte 1:1. **12** consolida as CR (Q6/Q8/Q10, contas `RESERVATION`+`investments`); **13** consolida as Não CR (Q7/Q9/Q11, colateral+TOKENIZATION). Em ambas, `face_value * total_quantity` serve às 3 classes (em consórcio/FGTS a qty é 1); só mudam as colunas de face_value/vencimento, dirigidas por `reference_table_id`.

---

## `utils/` — queries auxiliares (fora das 11)

| Arquivo | O que retorna | Entrada | Status |
|---|---|---|---|
| [utils/token_to_cr_series.sql](utils/token_to_cr_series.sql) | Token → `securitization_series` específica (via conta de colateral) + a mãe (CR) | nome do **token** | ✅ |
| [utils/cr_series_rentability.sql](utils/cr_series_rentability.sql) | Rentabilidade cadastrada das séries de um CR (indexer, %, spread, seniority, datas) | nome da **mãe** (ex. `CR-FGTS-30`) | ✅ |
| [utils/cr_series_issuance_date.sql](utils/cr_series_issuance_date.sql) | Data de emissão (e vencimento) de uma CR series | nome da **série** (ex. `CR-FGTS-30-59-SENIOR`) | ✅ |
| [utils/fgts_token_name_audit_v2.sql](utils/fgts_token_name_audit_v2.sql) | Auditoria do nome: token FGTS → série V2 + mãe + maturity/seniority/sufixo | lista fixa de tokens | ✅ |
| [utils/fgts_token_name_audit_v1.sql](utils/fgts_token_name_audit_v1.sql) | Auditoria no **V1 (Supabase)**: série + nome do token no V1, por mãe CR-FGTS | nº dos CRs | ✅ |

**Correção de nomes (scripts WRITE, não read-only):** rename dos 6 tokens FGTS (CR-01..06) p/ espelhar o V1 + log em `histories`. Doc: [utils/fgts_token_rename.md](utils/fgts_token_rename.md). Scripts: `fgts_token_rename_v2.py`/`.sql` (local) e `fgts_token_rename_PROD.py` (prod; dry-run por padrão, `COMMIT=True` aplica). **Aplicado em prod 2026-06-09.**

---

## Infra

| Arquivo | Função |
|---|---|
| [run_query.py](run_query.py) | Executor read-only (sessão READ ONLY + guardrail só-SELECT). Lê `.env` (DATABASE_URL) sozinho — **não abrir o `.env`**. |
| [_sanity_check.sql](_sanity_check.sql) | Testa conexão (database/user/now), sem depender de tabela do schema. |

---

## Tickers de teste já usados

Cada query tem um ticker apropriado que **só o usuário sabe**. Usados até agora:
Q1/Q4 = `NXFGTSB31-3` · Q2/Q7 = `NXCOC26-1` · Q3 = `NXNIC26-2` · Q5 = `NXFSC31-1` · Q6 = `NXCOL26-4` · Q8 (smoke) = `NXFGTSB31-1` · Q10 = `NXNTNII27-1` (CR-NTNI-24).

> NTN-I tem dois tokens: `NXNII27-1` (issuer NEXA — tokenização **direta**, p/ Não CR) e `NXNTNII27-1` (issuer CR-NTNI-24 — securitizado, p/ CR). Não existe `NXNII27-2`.
