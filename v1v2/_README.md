# Shared Memory — Engine V1↔V2 Migration Reference

Documentação cross-team sobre os schemas V1 (Supabase) e V2 (AWS PostgreSQL) e o mapeamento entre eles. Sem referências a repositórios, paths de código, ou tooling interno — só conhecimento de domínio.

## Quando usar cada arquivo

### Queries
- **[queries/engine_queries_v1.txt](queries/engine_queries_v1.txt)** — Queries V1 originais (Public Offer, NXCO, NXNI, Cash Flow, etc.) que precisam ser portadas pro V2.
- **[queries/v2/](queries/v2/)** — Queries V2 equivalentes (uma por arquivo, numeradas 01-11). Cada arquivo traz a V1 comentada + a V2 funcional.

### Schemas (DDL)
- **[schemas/v1_schema.md](schemas/v1_schema.md)** — DDL V1 Supabase. Padrão `securities + metadata JSONB`, bridge `aux_ids`, regras V1→V2.
- **[schemas/v2_schema.md](schemas/v2_schema.md)** — DDL V2 AWS Postgres. Tabelas tipadas, triggers (`total_quantity`, `last_*_flag`), enums, FKs incomuns. **Ler antes de qualquer SQL contra V2.**
- **[schemas/db_diagram_v2.txt](schemas/db_diagram_v2.txt)** — DBML V2 completo com triggers e procedures em comentários.
- **[schemas/engine_db.dbml](schemas/engine_db.dbml)** — DBML V2 enxuto (sem triggers/procedures).

### Convenções
- **[conventions/naming_conventions.md](conventions/naming_conventions.md)** — Como CRs, holders e ativos são nomeados em V1 vs V2; quando precisa de conversão.
- **[conventions/gotchas.md](conventions/gotchas.md)** — Armadilhas conhecidas: sufixos inesperados, normalização de strings, FKs incomuns, defaults silenciosos, triggers, conceitos V1 sem equivalente V2.

### Auditoria de mapping
- **[v2_reference/v2_computed_fields.md](v2_reference/v2_computed_fields.md)** — Catálogo de colunas V2 que **não** vêm de V1: derivadas (FRA/IRR/ETTJ/dia útil), mantidas por trigger, ou geradas pelo ETL. **Primeira parada quando uma coluna V2 está NULL ou estranha.**

### Mapeamento de metadata por asset class
- **[v1_metadata/v1_metadata_consortium.md](v1_metadata/v1_metadata_consortium.md)** — JSONB de consórcio (3 strategies, mesma estrutura) → V2 `consortiums`.
- **[v1_metadata/v1_metadata_fgts.md](v1_metadata/v1_metadata_fgts.md)** — JSONB de parcela_fgts → V2 `fgts`. Inclui campos vindos do arquivo de elegibilidade e cálculos derivados (IRR, ETTJ).
- **[v1_metadata/v1_metadata_other_assets.md](v1_metadata/v1_metadata_other_assets.md)** — Token, NTN-I (`titulo_publico`), CDB, e `spv_series` → tabelas V2 correspondentes.
- **[v1_metadata/v1_metadata_entities.md](v1_metadata/v1_metadata_entities.md)** — Estrutura JSONB por tipo de entidade V1 (issuer, corporate, individual, fund, spv).
- **[v1_metadata/v1_metadata_positions_valuations_transactions.md](v1_metadata/v1_metadata_positions_valuations_transactions.md)** — Metadata V1 quase vazia; campos novos do V2 vêm de lógica de aplicação, não migração.

## Fluxo típico de uso

1. **Portando uma query V1 pro V2** → começar pelo [CLAUDE.md](CLAUDE.md) (passo a passo); abrir a query em `queries/engine_queries_v1.txt`, identificar asset class, e ler o `v1_metadata/v1_metadata_<asset>.md` + `schemas/v2_schema.md` + `conventions/naming_conventions.md`.
2. **Escrevendo SQL contra V2** → ler `schemas/v2_schema.md` (atenção aos quirks de trigger e FK) + `v2_reference/v2_computed_fields.md`.
3. **Migrando um asset class** → abrir o `v1_metadata/v1_metadata_<asset>.md` correspondente + `schemas/v1_schema.md` + `conventions/naming_conventions.md`.
4. **Comparando dados V1↔V2** → `conventions/naming_conventions.md` é obrigatório (sufixos, normalização de nomes).
5. **Adicionando novo asset class** → seguir o template dos arquivos `v1_metadata/v1_metadata_*.md` (estrutura JSONB → tabela V2 → mapping table).

## Convenções de manutenção

- Frontmatter unificado (name, description, type, tags, resumo) em todos os arquivos.
- Mudanças de DDL V2 → atualizar `schemas/v2_schema.md` imediatamente; nunca confiar em memória.
- Stale facts de migração → marcar como tal (ex: "ainda não adicionada"); remover quando resolvido.
- Sem referências a paths de código, nomes de função, ou repos específicos. Conhecimento aqui é de domínio.
