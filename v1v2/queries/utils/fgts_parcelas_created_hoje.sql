-- ============================================================
-- V1 — Parcelas de FGTS criadas hoje
-- ------------------------------------------------------------
-- V1 (Supabase): todo ativo vive em `securities` + `metadata JSONB`.
-- Parcela de FGTS = securities.type = 'parcela_fgts'.
-- "created_at = data de hoje" = porção de data de created_at == hoje.
-- Range sargável (>= hoje AND < amanhã) em vez de created_at::date.
--
-- ATENÇÃO: o DDL de referência em schemas/v1_schema.md NÃO lista created_at
-- (só id, aux_id, name, full_name, code, type, metadata). É um DDL abreviado;
-- tabelas Supabase normalmente têm created_at timestamptz default now().
-- Confirme a coluna na conexão antes de confiar no resultado.
--
-- Filtro de originador = Topline: metadata->>'originator' = 'Topline_Fgts'
-- (grafia exata confirmada no V1/Supabase em 2026-06-09; é a única variante
-- que casa com 'topline' — 1288 parcelas no total).
-- ============================================================
SELECT *
FROM securities
WHERE type = 'parcela_fgts'
  AND metadata->>'originator' = 'Topline_Fgts'
  AND created_at >= CURRENT_DATE
  AND created_at <  CURRENT_DATE + INTERVAL '1 day'
ORDER BY created_at;
