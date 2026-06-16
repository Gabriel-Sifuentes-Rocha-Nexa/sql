-- ============================================================================
-- corrige_taxa_FGTS23_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- FGTS-23: a taxa de accrual no V2 esta ERRADA. O V2 ingeriu series_fixed_rate=0.16
-- (16.00%) do array series[] da MAE (entities spv CR-FGTS-23), mas o V1 PRECIFICA com
-- a taxa da SERIE = 0.1645 (16.45%, securities spv_series 3722276 series_fixed_rate).
-- Prova: accrued/dia em 100 -> V2 0.05891417 = exatamente 16.00% (252 du); V1 0.06045 = 16.45%.
-- Fix: securitization_series.spread_over_indexer 0.16 -> 0.1645 (serie 1057325).
-- (PREFIXADO: rate efetiva = spread_over_indexer; indexer_percentage=1, indexer=0.)
-- Token (1057326) NAO tem taxa propria (espelha a serie); tabela fgts nao tem row. 1 UPDATE so.
-- Depois: re-delete valuations > 03-02 (rate antiga) e re-accruar com 0.1645.
--
-- AUDITORIA: linha antiga -> `histories` (operation='update', created_by gabriel_sifuentes) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: antes
SELECT id, indexer_id, indexer_percentage, spread_over_indexer AS spread_atual,
       0.1645::numeric AS spread_novo
FROM securitization_series WHERE id=1057325;

-- (1) histories antes do UPDATE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'securitization_series', to_jsonb(ss), 'update',
       'FGTS-23: corrige taxa accrual spread_over_indexer 0.16 (da MAE, errada) -> 0.1645 (da SERIE, = a que o V1 usa p/ precificar)'
FROM securitization_series ss WHERE ss.id=1057325;

-- (2) UPDATE
UPDATE securitization_series SET spread_over_indexer = 0.1645 WHERE id=1057325;

-- (3) GUARDA: exatamente 1 row, spread agora = 0.1645
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM securitization_series WHERE id=1057325 AND spread_over_indexer=0.1645;
  IF n <> 1 THEN RAISE EXCEPTION 'esperava 1 row com spread_over_indexer=0.1645, achei %', n; END IF;
  RAISE NOTICE 'OK: spread_over_indexer da serie 1057325 = 0.1645';
END $$;

-- (4) POST-CHECK
SELECT id, indexer_id, indexer_percentage, spread_over_indexer, initial_price FROM securitization_series WHERE id=1057325;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
