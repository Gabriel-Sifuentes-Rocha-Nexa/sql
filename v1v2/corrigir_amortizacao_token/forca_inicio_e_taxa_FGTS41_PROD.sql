-- ============================================================================
-- forca_inicio_e_taxa_FGTS41_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- FGTS-41: mesmos 2 bugs do FGTS-23 (ver reference_fgts_rate_and_startday_bug):
--   (1) TAXA: V2 spread_over_indexer=0.1824 (da MAE) em vez de 0.1825 (da SERIE, = V1).
--   (2) SHIFT inicio: V2 larga accrual 06-05; V1 so' 06-08 (06-04 Corpus Christi, 06-06/07 fds).
--       V2 accruou 1 du cedo (06-05=0.06650872) e carregou no fds.
-- FGTS-41 e' novo (emissao 06-03), sem amort nem freeze -> so' rate + forcar inicio.
-- Fix: UPDATE rate 0.1824->0.1825; forcar 06-05/06/07 accrued->0 (V1 nao accrua ainda);
--      apagar 06-08+; o usuario re-accrua -> engine preenche 06-08 do 06-07(=0) na taxa 0.1825
--      -> deve dar 0.0665423 (= V1). Verificacao apos re-accrual.
--
-- Serie 1400751 (CR-FGTS-41-01-SINGLE) + token 1400752 (NXFGTSF31-1). qty 50000.
-- UPDATE de accrued NAO dispara trigger de last_valuation_flag; DELETE dispara (recompoe).
-- AUDITORIA: linha antiga -> `histories` (update/delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: taxa atual + curva inicio
SELECT id, spread_over_indexer AS taxa_atual, 0.1825::numeric AS taxa_nova FROM securitization_series WHERE id=1400751;
SELECT a.name AS ativo, v.date::date d, v.clean_price, v.accrued_interest,
       CASE WHEN v.date::date IN (DATE '2026-06-05',DATE '2026-06-06',DATE '2026-06-07') THEN '-> 0 (forcar)'
            WHEN v.date > timestamptz '2026-06-07 00:00:00-03' THEN '-> DELETE' ELSE '' END AS acao
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1400751,1400752)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date>=timestamptz '2026-06-03 00:00:00-03' ORDER BY a.name, v.date;

-- (1) histories — taxa (securitization_series)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'securitization_series', to_jsonb(ss), 'update',
       'FGTS-41: corrige taxa spread_over_indexer 0.1824 (mae) -> 0.1825 (serie = V1)'
FROM securitization_series ss WHERE ss.id=1400751;

-- (2) histories — valuations (06-05/06/07 update->0 ; 06-08+ delete)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v),
       (CASE WHEN v.date > timestamptz '2026-06-07 00:00:00-03' THEN 'delete' ELSE 'update' END)::operations_enum,
       'FGTS-41 forca inicio: zera accrued 06-05/06/07 (V1 so accrua 06-08) e apaga 06-08+ p/ engine refazer na taxa 0.1825'
FROM valuations v
WHERE v.asset_id IN (1400751,1400752)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND (v.date::date IN (DATE '2026-06-05',DATE '2026-06-06',DATE '2026-06-07')
       OR v.date > timestamptz '2026-06-07 00:00:00-03');

-- (3) UPDATE taxa
UPDATE securitization_series SET spread_over_indexer = 0.1825 WHERE id=1400751;

-- (4) forcar 06-05/06/07 accrued -> 0
UPDATE valuations SET accrued_interest = 0
WHERE asset_id IN (1400751,1400752)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date::date IN (DATE '2026-06-05',DATE '2026-06-06',DATE '2026-06-07');

-- (5) DELETE 06-08+
DELETE FROM valuations
WHERE asset_id IN (1400751,1400752)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date > timestamptz '2026-06-07 00:00:00-03';

-- (6) GUARDA: taxa 0.1825; 06-05/06/07 accrued=0/clean=100; nada >06-07; max=06-07
DO $$
DECLARE r numeric; bad int; ms timestamptz; mt timestamptz;
BEGIN
  SELECT spread_over_indexer INTO r FROM securitization_series WHERE id=1400751;
  IF r <> 0.1825 THEN RAISE EXCEPTION 'taxa != 0.1825 (%)', r; END IF;
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id IN (1400751,1400752)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND ( (date::date IN (DATE '2026-06-05',DATE '2026-06-06',DATE '2026-06-07') AND (accrued_interest<>0 OR clean_price<>100))
        OR (date > timestamptz '2026-06-07 00:00:00-03') );
  IF bad <> 0 THEN RAISE EXCEPTION 'estado pos-fix inesperado (% linhas)', bad; END IF;
  SELECT max(date) INTO ms FROM valuations WHERE asset_id=1400751 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost');
  SELECT max(date) INTO mt FROM valuations WHERE asset_id=1400752 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost');
  IF ms<>timestamptz '2026-06-07 00:00:00-03' OR mt<>timestamptz '2026-06-07 00:00:00-03'
     THEN RAISE EXCEPTION 'max(date) != 06-07 (serie=%, token=%)', ms, mt; END IF;
  RAISE NOTICE 'OK: taxa 0.1825, 06-05/06/07 zerados, 06-08+ apagado, max=06-07';
END $$;

-- (7) POST-CHECK
SELECT a.name AS ativo, v.date::date d, v.clean_price, v.accrued_interest,
       (v.clean_price+v.accrued_interest) AS dirty, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1400751,1400752)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date>=timestamptz '2026-06-03 00:00:00-03' ORDER BY a.name, v.date;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
