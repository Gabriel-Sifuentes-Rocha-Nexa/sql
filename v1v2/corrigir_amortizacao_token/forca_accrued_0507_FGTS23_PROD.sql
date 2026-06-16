-- ============================================================================
-- forca_accrued_0507_FGTS23_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- FGTS-23: o amort 05-07 foi bookado com a accrual parada em 05-06, entao o engine
-- nao accruou o dia 05-07 antes de amortizar -> o evento ficou com accrued=2.63268868
-- (= 05-06). O V1 accrua o 05-07 (accrued=2.6947317, pre-amort dirty 102.6947317) e
-- depois amortiza. Falta ~0.062 (1 dia). Fix: UPDATE accrued do evento 05-07 -> 2.6947317.
-- clean (99.45786832) e cash_flow (0.54213168) ficam (nivel-arredondamento do amort_value
-- 5475.53, consistentes com a position -5475.53). Apos o fix, dirty 05-07 = 102.15260002 (=V1)
-- e o accrual segue daqui batendo com o V1.
--
-- Serie 1057325 + token 1057326. Evento = date::date 05-07 AND cash_flow<>0.
-- AUDITORIA: linha antiga -> `histories` (operation='update') ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest AS accrued_atual,
       2.6947317::numeric AS accrued_novo, v.cash_flow
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1057325,1057326)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date::date='2026-05-07' AND v.cash_flow<>0
ORDER BY a.name;

-- (1) histories antes
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'update',
       'FGTS-23 05-07: corrige accrued do evento 2.63268868 (05-06, faltou 1 dia) -> 2.6947317 (= V1 pre-amort)'
FROM valuations v
WHERE v.asset_id IN (1057325,1057326)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date::date='2026-05-07' AND v.cash_flow<>0;

-- (2) UPDATE
UPDATE valuations SET accrued_interest = 2.6947317
WHERE asset_id IN (1057325,1057326)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date::date='2026-05-07' AND cash_flow<>0;

-- (3) GUARDA: 2 linhas, accrued=2.6947317
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM valuations
   WHERE asset_id IN (1057325,1057326)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date::date='2026-05-07' AND cash_flow<>0 AND round(accrued_interest,7)=2.6947317;
  IF n <> 2 THEN RAISE EXCEPTION 'esperava 2 linhas accrued=2.6947317, achei %', n; END IF;
  RAISE NOTICE 'OK: accrued 05-07 = 2.6947317 (serie+token)';
END $$;

-- (4) POST-CHECK
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price+v.accrued_interest) AS dirty, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1057325,1057326)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date::date='2026-05-07' ORDER BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
