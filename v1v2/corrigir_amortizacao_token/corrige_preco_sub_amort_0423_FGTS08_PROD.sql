-- ============================================================================
-- corrige_preco_sub_amort_0423_FGTS08_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- CR-FGTS-08-03-SUBORDINATED (08-03): so' fazer o PRECO bater com o V1 no DIA DA AMORT.
-- V1 sub = 2 pontos: 100 (10-17) e 10 (04-23). Unico dia de amort = 04-23, preco 10.
-- V2 04-23 evento 12:00: clean 10 (certo), MAS accrued 6.75743166 -> dirty 16.757 (devia 10).
-- Fix: zerar accrued no evento 04-23 12:00 (serie 1058784 + token 1058785) -> dirty 10 = V1.
-- cash_flow +90 fica (= 100->10 distribuido). Accruals diarios NAO sao tocados (pedido do user;
--   a sub fica residual 10, sem reconstruir a serie temporal).
-- AUDITORIA: linha antiga -> histories (update) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: evento 04-23 atual
SELECT a.name, v.id, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price+v.accrued_interest) dirty, v.cash_flow
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058784,1058785)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date = timestamptz '2026-04-23 12:00:00+00'
ORDER BY a.name;

-- (1) histories — linha antiga (update) ANTES
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'update',
       'FGTS-08 sub amort 04-23: zera accrued (6.757) p/ dirty=10 = V1 (so o preco do dia da amort)'
FROM valuations v
WHERE v.asset_id IN (1058784,1058785)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date = timestamptz '2026-04-23 12:00:00+00';

-- (2) UPDATE: zera accrued no evento 04-23 (clean 10 e cash_flow 90 ficam)
UPDATE valuations SET accrued_interest = 0
WHERE asset_id IN (1058784,1058785)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date = timestamptz '2026-04-23 12:00:00+00'
  AND clean_price = 10 AND accrued_interest <> 0;

-- (3) GUARDA: 2 rows, clean 10, accrued 0, dirty 10
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM valuations
   WHERE asset_id IN (1058784,1058785)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date = timestamptz '2026-04-23 12:00:00+00'
     AND clean_price=10 AND accrued_interest=0;
  IF n <> 2 THEN RAISE EXCEPTION 'esperado 2 rows 04-23 clean=10 accrued=0, achei %', n; END IF;
  RAISE NOTICE 'OK: sub 04-23 dirty=10 = V1 (serie+token)';
END $$;

-- (4) POST-CHECK
SELECT a.name, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price+v.accrued_interest) dirty, v.cash_flow
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058784,1058785)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date >= timestamptz '2026-04-23 00:00:00-03' AND v.date <= timestamptz '2026-04-24 23:59:00-03'
ORDER BY a.name, v.date;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
