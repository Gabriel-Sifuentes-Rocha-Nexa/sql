-- ============================================================================
-- corrige_spread_NXFGTSF31-1_PROD.sql               (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Par CR-FGTS-41-01-SINGLE (serie, asset 1400751) + NXFGTSF31-1 (token, asset 1400752),
-- mae CR-FGTS-41 (issuer 1400750).
--
-- BUG: spread_over_indexer contratual deveria ser SEMPRE 0.1824, mas:
--   (a) securitization_series.spread_over_indexer (id 1400751) esta 0.1825  <-- FONTE
--   (b) as valuations que ACRUEM (06-08 -> 06-17, 10 por asset = 20) sairam com 0.1825,
--       porque o engine le a taxa da serie (a mae). accrued foi calculado a 0.1825.
--   (c) anomalia isolada: valuation da serie em 06-04 (id 28826094) esta com spread 0.0.
--   As linhas-semente 06-03..06-07 (accrued=0) ja estao 0.1824 (exceto a 06-04 acima).
--
-- CORRECAO (caminho "apagar e re-accruar", confirmado pelo Gabriel):
--   1. UPDATE serie spread_over_indexer 0.1825 -> 0.1824  (corrige a FONTE; senao o batch
--      diario re-emite 0.1825).
--   2. UPDATE valuation 06-04 (28826094) spread 0.0 -> 0.1824 (linha pre-accrual, accrued=0;
--      o re-accrual NAO a recria, entao corrige-se in place p/ nao abrir buraco na serie).
--   3. DELETE as 20 valuations de 06-08 -> 06-17 (as 0.1825 que acruem) do PAR serie+token.
--      Mantem a baseline 06-07 (accrued=0, price=100, ja 0.1824) p/ o re-accrual continuar dali.
--   4. >>> DEPOIS deste script (com COMMIT), o Gabriel RE-ACCRUA o PAR serie+token de 06-08
--          ate hoje pelo engine -> recalcula accrued exato a 0.1824. <<<
--
-- Mecanica: flags (last_valuation_flag) sao recompostas por trigger no DELETE/UPDATE.
-- AUDITORIA: cada linha -> histories (update/delete) ANTES da operacao.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — estado atual (serie-mae + timeline das valuations do par)
SELECT 'SERIE antes' AS t, s.id, NULL::text AS dt, s.spread_over_indexer::text AS spread, NULL::text AS accrued
FROM securitization_series s WHERE s.id = 1400751
UNION ALL
SELECT 'VAL antes', v.id, v.date::text, v.spread_over_indexer::text, v.accrued_interest::text
FROM valuations v WHERE v.asset_id IN (1400751,1400752)
ORDER BY 1, 3, 2;

-- (1) histories — serie (FONTE) a ATUALIZAR
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','securitization_series', to_jsonb(s),'update',
       'NXFGTSF31-1 spread_over_indexer da serie CR-FGTS-41-01-SINGLE 0.1825->0.1824 (fonte do accrual)'
FROM securitization_series s WHERE s.id = 1400751;

-- (2) histories — valuation 06-04 (anomalia 0.0) a ATUALIZAR
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'update',
       'NXFGTSF31-1 spread valuation 06-04 da serie 0.0->0.1824 (linha pre-accrual, accrued=0)'
FROM valuations v WHERE v.id = 28826094;

-- (3) histories — valuations 06-08->06-17 (0.1825 que acruem) a APAGAR
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'delete',
       'NXFGTSF31-1 apaga valuation acruada a 0.1825 (06-08->06-17) p/ re-accruar a 0.1824 (par serie+token)'
FROM valuations v
WHERE v.id IN (
  -- serie 1400751 (06-08..06-17)
  30675303,30675319,30675335,30675351,30675452,30692546,30703023,30713371,30728334,30772204,
  -- token 1400752 (06-08..06-17)
  30675311,30675327,30675343,30675359,30675551,30692648,30703125,30713473,30728438,30772308
);

-- (4) UPDATE serie (FONTE) -> 0.1824
UPDATE securitization_series SET spread_over_indexer = 0.1824 WHERE id = 1400751;

-- (5) UPDATE valuation 06-04 -> 0.1824
UPDATE valuations SET spread_over_indexer = 0.1824 WHERE id = 28826094;

-- (6) DELETE valuations 0.1825 que acruem (06-08->06-17, par serie+token)
DELETE FROM valuations
WHERE id IN (
  30675303,30675319,30675335,30675351,30675452,30692546,30703023,30713371,30728334,30772204,
  30675311,30675327,30675343,30675359,30675551,30692648,30703125,30713473,30728438,30772308
);

-- (7) GUARDA
DO $$
DECLARE s_spread numeric; v0604 numeric; n_lixo int; n_ruim int; n_serie int; n_token int;
BEGIN
  -- fonte corrigida
  SELECT spread_over_indexer INTO s_spread FROM securitization_series WHERE id = 1400751;
  IF round(s_spread,8) <> 0.18240000 THEN RAISE EXCEPTION 'serie spread=% (esperado 0.1824)', s_spread; END IF;

  -- anomalia 06-04 corrigida
  SELECT spread_over_indexer INTO v0604 FROM valuations WHERE id = 28826094;
  IF round(v0604,8) <> 0.18240000 THEN RAISE EXCEPTION 'val 06-04 spread=% (esperado 0.1824)', v0604; END IF;

  -- as 20 apagadas nao existem mais
  SELECT count(*) INTO n_lixo FROM valuations WHERE id IN (
    30675303,30675319,30675335,30675351,30675452,30692546,30703023,30713371,30728334,30772204,
    30675311,30675327,30675343,30675359,30675551,30692648,30703125,30713473,30728438,30772308);
  IF n_lixo <> 0 THEN RAISE EXCEPTION 'restaram % valuations a apagar', n_lixo; END IF;

  -- nenhuma valuation remanescente do par com spread <> 0.1824
  SELECT count(*) INTO n_ruim FROM valuations
   WHERE asset_id IN (1400751,1400752) AND round(spread_over_indexer,8) <> 0.18240000;
  IF n_ruim <> 0 THEN RAISE EXCEPTION '% valuations remanescentes com spread<>0.1824', n_ruim; END IF;

  -- baseline 06-03..06-07 preservada (5 linhas por asset)
  SELECT count(*) INTO n_serie FROM valuations WHERE asset_id=1400751;
  SELECT count(*) INTO n_token FROM valuations WHERE asset_id=1400752;
  IF n_serie <> 5 OR n_token <> 5 THEN
    RAISE EXCEPTION 'baseline inesperada: serie=% token=% (esperado 5/5 = 06-03..06-07)', n_serie, n_token;
  END IF;

  RAISE NOTICE 'OK NXFGTSF31-1: serie+valuations a 0.1824; 20 acruadas apagadas; baseline 06-07 mantida. Falta o Gabriel RE-ACCRUAR 06-08->hoje.';
END $$;

-- (8) POST-CHECK
SELECT s.id AS serie_id, s.spread_over_indexer FROM securitization_series s WHERE s.id = 1400751;
SELECT a.name AS ativo, v.date, v.spread_over_indexer, v.accrued_interest, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE v.asset_id IN (1400751,1400752) ORDER BY v.asset_id, v.date;
SELECT operation, table_name, count(*) FROM histories
WHERE created_by='gabriel_sifuentes' AND description LIKE 'NXFGTSF31-1 %' GROUP BY operation, table_name ORDER BY 2,1;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar (e depois RE-ACCRUE 06-08->hoje pelo engine).
