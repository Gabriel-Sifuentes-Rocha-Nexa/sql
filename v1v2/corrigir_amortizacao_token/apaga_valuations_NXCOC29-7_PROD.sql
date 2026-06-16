-- ============================================================================
-- apaga_valuations_NXCOC29-7_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- NXCOC29-7 (token id 1412934). As diarias 06-12..06-16 nasceram ANTES da
--   integralizacao -> spread=0, accrued=0, clean=100 (nao acruou). O usuario JA
--   bookou a INTEGRALIZATION (06-12 16:18, CR-CONSORTIUMS-44: 50056 -> 3556) +
--   cessao no V2. Agora vai RE-ACCRUAR pelo engine.
--
-- Acao: apagar as valuations stale a partir de 06-12 (mantem o SEED de emissao
--   06-11: clean 100, accrued 0, spread 0.1895). O engine re-accrua dai lendo a
--   integralizacao 06-12 -> deve bater o V1: 06-12=0, 06-15=0.06888603 (1 du @
--   18.95%), 06-16=0.13781952 (2 du).
--
-- Token so' tem methodology_id=2 (amortized_cost) nessas datas (conferido: 6 linhas,
--   todas mtd 2). DELETE dispara o trigger last_valuation_flag (recompoe p/ a emissao).
-- AUDITORIA: linha antiga -> histories (delete) ANTES do DELETE.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: 06-11..06-16 + acao
SELECT a.name AS ativo, v.date, v.methodology_id, v.clean_price, v.accrued_interest,
       v.spread_over_indexer, v.last_valuation_flag,
       CASE WHEN v.date >= timestamptz '2026-06-12 00:00:00-03' THEN '-> DELETE'
            ELSE '(mantem SEED)' END AS acao
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE v.asset_id = 1412934
ORDER BY v.date, v.methodology_id;

-- (1) histories — linhas que vao ser apagadas (>= 06-12)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete'::operations_enum,
       'NXCOC29-7: apaga diarias stale 06-12+ (nasceram pre-integralizacao, spread=0/accrued=0) p/ re-accruar pelo engine apos bookar INTEGRALIZATION 06-12'
FROM valuations v
WHERE v.asset_id = 1412934
  AND v.date >= timestamptz '2026-06-12 00:00:00-03';

-- (2) DELETE 06-12+ (mantem o seed de emissao 06-11)
DELETE FROM valuations
WHERE asset_id = 1412934
  AND date >= timestamptz '2026-06-12 00:00:00-03';

-- (3) GUARDA: nada >= 06-12; sobra so' o seed 06-11 e ele vira last_valuation_flag=TRUE
DO $$
DECLARE bad int; seed int;
BEGIN
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id = 1412934 AND date >= timestamptz '2026-06-12 00:00:00-03';
  IF bad <> 0 THEN RAISE EXCEPTION 'ainda ha % linhas >= 06-12', bad; END IF;
  SELECT count(*) INTO seed FROM valuations
   WHERE asset_id = 1412934 AND date::date = DATE '2026-06-11' AND last_valuation_flag = TRUE;
  IF seed < 1 THEN RAISE EXCEPTION 'seed 06-11 nao ficou como last_valuation_flag=TRUE'; END IF;
  RAISE NOTICE 'OK: 06-12+ apagado; seed 06-11 vigente (last_valuation_flag=TRUE)';
END $$;

-- (4) POST-CHECK
SELECT v.date, v.clean_price, v.accrued_interest, v.spread_over_indexer, v.last_valuation_flag
FROM valuations v
WHERE v.asset_id = 1412934
ORDER BY v.date, v.methodology_id;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar. (APLICADO via COMMIT em 2026-06-16.)
