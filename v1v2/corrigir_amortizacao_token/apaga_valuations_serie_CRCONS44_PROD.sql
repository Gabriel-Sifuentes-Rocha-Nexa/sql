-- ============================================================================
-- apaga_valuations_serie_CRCONS44_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Serie CR-CONSORTIUMS-44-01-SINGLE (id 1412933), espelhada pelo token NXCOC29-7
--   (id 1412934). Mesmo caso do token: as diarias 06-12..06-16 nasceram ANTES da
--   integralizacao -> spread=0, accrued=0, clean=100 (nao acruou). O token ja' teve
--   essas linhas apagadas (apaga_valuations_NXCOC29-7_PROD.sql, COMMIT 06-16); falta
--   apagar as da SERIE p/ o par re-accruar junto e ficar igual.
--
-- Acao: apagar valuations stale da serie a partir de 06-12 (mantem SEED de emissao
--   06-11: clean 100, accrued 0, spread 0.1895). Re-accrual deve bater o V1:
--   06-12=0, 06-15=0.06888603 (1 du @ 18.95%), 06-16=0.13781952 (2 du).
-- DELETE dispara trigger last_valuation_flag (recompoe p/ a emissao).
-- AUDITORIA: linha antiga -> histories (delete) ANTES do DELETE.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW
SELECT a.name AS ativo, v.date, v.methodology_id, v.clean_price, v.accrued_interest,
       v.spread_over_indexer, v.last_valuation_flag,
       CASE WHEN v.date >= timestamptz '2026-06-12 00:00:00-03' THEN '-> DELETE'
            ELSE '(mantem SEED)' END AS acao
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE v.asset_id = 1412933
ORDER BY v.date, v.methodology_id;

-- (1) histories — linhas que vao ser apagadas (>= 06-12)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete'::operations_enum,
       'CR-CONSORTIUMS-44-01-SINGLE: apaga diarias stale 06-12+ (pre-integralizacao, spread=0/accrued=0) p/ re-accruar junto com o token NXCOC29-7'
FROM valuations v
WHERE v.asset_id = 1412933
  AND v.date >= timestamptz '2026-06-12 00:00:00-03';

-- (2) DELETE 06-12+ (mantem o seed de emissao 06-11)
DELETE FROM valuations
WHERE asset_id = 1412933
  AND date >= timestamptz '2026-06-12 00:00:00-03';

-- (3) GUARDA: nada >= 06-12; seed 06-11 vira last_valuation_flag=TRUE
DO $$
DECLARE bad int; seed int;
BEGIN
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id = 1412933 AND date >= timestamptz '2026-06-12 00:00:00-03';
  IF bad <> 0 THEN RAISE EXCEPTION 'ainda ha % linhas >= 06-12', bad; END IF;
  SELECT count(*) INTO seed FROM valuations
   WHERE asset_id = 1412933 AND date::date = DATE '2026-06-11' AND last_valuation_flag = TRUE;
  IF seed < 1 THEN RAISE EXCEPTION 'seed 06-11 nao ficou como last_valuation_flag=TRUE'; END IF;
  RAISE NOTICE 'OK: 06-12+ apagado; seed 06-11 vigente (last_valuation_flag=TRUE)';
END $$;

-- (4) POST-CHECK
SELECT v.date, v.clean_price, v.accrued_interest, v.spread_over_indexer, v.last_valuation_flag
FROM valuations v
WHERE v.asset_id = 1412933
ORDER BY v.date, v.methodology_id;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar. (APLICADO via COMMIT em 2026-06-16.)
