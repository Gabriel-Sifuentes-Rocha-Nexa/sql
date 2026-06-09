# Correção dos nomes de tokens FGTS no Engine V2 (espelhar V1 / B2C)

## Problema
6 tokens de CR-FGTS no Engine V2 estavam com **nome divergente** do nome canônico
(o que existe no V1 e no B2C). Todo o resto do namespace batia — no pareamento
completo V1↔V2 (todas as classes, ~330 tokens) **só esses 6 divergiram**.

Eram dois tipos de divergência, que juntas formam uma **permutação fechada** no
"balde" de mesmo vencimento (I35 = Set/2035, L34 = Dez/2034):
- **letra do mês** em CR-01/02/03 (V2 usava L/I; o canônico V1 usa J/H);
- **sufixo** em CR-03..06 (numeração diferente dentro do balde).

Além disso havia a entidade **órfã `NXFGTSI35-2`** (id 262653) — um *token stub*
(sem linha em `tokens`, sem positions; só 9 valuations + 1 entity_type) que
ocupava o nome `-2` necessário ao CR-05.

## Decisão
Espelhar o **V1 exatamente** (V1 = nomes oficiais/registrados, usados pelo B2C).

| CR | Token V2 (antigo) | → nome final (V1) | id da entidade |
|---|---|---|---|
| CR-FGTS-01 (SINGLE)        | NXFGTSL34-1     | **NXFGTSJ34-1** | 20451 |
| CR-FGTS-02 (SINGLE)        | NXFGTSI35-1     | **NXFGTSH35-1** | 159526 |
| CR-FGTS-03 (SINGLE)        | NXFGTSI35-3     | **NXFGTSH35-2** | 1035060 |
| CR-FGTS-04 (SINGLE)        | NXFGTSI35-4     | **NXFGTSI35-1** | 1047752 |
| CR-FGTS-05 (SINGLE)        | NXFGTSI35-5     | **NXFGTSI35-2** | 1052807 |
| CR-FGTS-06 (SINGLE)        | NXFGTSI35-6     | **NXFGTSI35-3** | 1057260 |
| CR-FGTS-08 (SUBORDINATED)  | NXFGTSJRL40-8.3 | (não mudou — já = V1) | 1058785 |

Órfã `NXFGTSI35-2` (262653): **arquivada** (`ARCHIVED-…`) — reversível. O
hard-delete em cascata (9 valuations + entity_type + fa **por id** 9916) fica como
passo opcional.

## O que precisou mudar
Só duas tabelas guardam o nome do token; o resto liga por `id` (FK):
1. `entities.name` (a entidade do token);
2. `financial_accounts.name` da conta de colateral (`assets pledged as collateral - <token>`).

`positions` referenciam `financial_account_id` / `asset_id` / `holder_id` por **id**
— seguem corretas sozinhas após o rename (confirmado: a única conta com nome de
token é a de colateral; `event_code`/`payment_code` não contêm o nome).

### Como (2 fases + histories)
Como os nomes formam permutação fechada (o nome final de um é o atual de outro),
o rename é feito em **2 fases** numa transação: tudo → nomes temporários
(`TMP-REN-…`) → nomes finais. Assim nunca se viola o `UNIQUE` de `entities.name`
/ `financial_accounts.name` no meio.

**Rastreabilidade:** antes de cada `UPDATE`/`DELETE`, grava-se a linha antiga em
`public.histories` (`old_value = to_jsonb(linha)`, `table_name`, `operation`,
`created_by`). Ver `../../../` memória `reference_histories_audit_pattern`.

## Scripts
| Arquivo | Uso |
|---|---|
| `fgts_token_name_audit_v2.sql` | auditoria: token FGTS → série V2 + mãe + campos do nome (read-only) |
| `fgts_token_name_audit_v1.sql` | auditoria no **V1/Supabase**: série + nome do token no V1 |
| `fgts_token_rename_v2.py` / `.sql` | **WRITE (local)**: rename dos 6 + órfã, 2 fases, pré/pós-check, dry-run |
| `fgts_token_rename_PROD.py` | **WRITE (prod)**: idem, resolve ids por **nome** em runtime, loga em `histories`, dry-run por padrão |

## Aplicação
- **Local** (cópia V2): aplicado 2026-06-08. Órfã deletada em cascata (no local).
- **Produção**: aplicado **2026-06-09** (autorizado). Conexão = `DATABASE_URL` de
  `queries/.env`. Pós-commit verificado: 6 tokens + 6 contas renomeados, órfã
  arquivada, **14 linhas em `histories`** (7 `entities` + 7 `financial_accounts`,
  `operation='update'`, `created_by='gabriel_sifuentes'`).

## Nota de pareamento V1↔V2 (lição)
O **número do CR não se preserva** entre V1 e V2, e nome/código/vencimento driftam.
Para FGTS de CR o número bate (validado por vencimento), mas para **consórcio** os
SPVs `CR-Consorcio-N` do V1 foram **reestruturados no V2 dentro do fundo `FIDC NXCO`**
(séries `FIDC-CONSORTIUM-NN`). Portanto, para parear V1↔V2 com segurança use a
**identidade estrutural do subjacente** (cota: admin+grupo+cota; parcela FGTS:
contrato), nunca o número/nome do CR.
