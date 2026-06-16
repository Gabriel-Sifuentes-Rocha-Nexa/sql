-- ============================================================================
-- corrige_amort_0316_FGTS08_SR_MZ_PROD.sql            (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- A amort 03-16 foi bookada pela API em 03-15 12:00 com clean 100->92,50 (certo) e
-- cash_flow +7,50, MAS:
--   (1) accrued NAO zerou (ficou 5.96473125 senior / 6.53100134 mezz) -> dirty 98,46/99,03
--       vs V1 92,50 (V1 paga os juros na amort: accrued=0). A API rejeita interest_payment=true.
--   (2) evento caiu em 03-15 (domingo, data do schedule); V1 efetiva em 03-16 (segunda) com
--       accrued=0 e so' accrua a partir de 03-17. Manter em 03-15 gera shift de 1 du.
-- FIX cirurgico no row do evento (4 assets): mover date -> 2026-03-16 12:00, accrued -> 0,
--   cash_flow -> 7,5 + juros pagos (= delta V1: senior 13.46473125 / mezz 14.03100134).
--   clean fica 92,50. Depois o usuario accrua ate 04-16 (deve bater V1: senior 93,775 / mezz 93,895).
--
-- SR serie 1058788 / token 1058789 ; MZ serie 1058786 / token 1058787.
-- Juros pagos = accrued de 03-15 (= du de sexta carregado): SR 5.96473125 ; MZ 6.53100134.
-- AUDITORIA: linha antiga -> histories (update) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: estado atual do evento 03-15 12:00
SELECT a.name, v.id, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price+v.accrued_interest) dirty, v.cash_flow
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058788,1058789,1058786,1058787)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date = timestamptz '2026-03-15 12:00:00+00'
ORDER BY a.name;

-- (1) histories — linha antiga (update) ANTES
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'update',
       'FGTS-08 SR/MZ amort 03-16: zera accrued (juros pagos), cash_flow=7,5+juros, move evento 03-15->03-16'
FROM valuations v
WHERE v.asset_id IN (1058788,1058789,1058786,1058787)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date = timestamptz '2026-03-15 12:00:00+00';

-- (2) UPDATE: move p/ 03-16, zera accrued, ajusta cash_flow
UPDATE valuations v SET
  date = timestamptz '2026-03-16 12:00:00+00',
  accrued_interest = 0,
  cash_flow = CASE WHEN v.asset_id IN (1058788,1058789) THEN 13.46473125
                   WHEN v.asset_id IN (1058786,1058787) THEN 14.03100134 END
WHERE v.asset_id IN (1058788,1058789,1058786,1058787)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date = timestamptz '2026-03-15 12:00:00+00'
  AND v.clean_price = 92.50;

-- (3) GUARDA: 4 rows movidos, clean 92,50, accrued 0, dirty 92,50, vigente
DO $$
DECLARE n int; bad int;
BEGIN
  SELECT count(*) INTO n FROM valuations
   WHERE asset_id IN (1058788,1058789,1058786,1058787)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date = timestamptz '2026-03-16 12:00:00+00'
     AND clean_price=92.50 AND accrued_interest=0;
  IF n <> 4 THEN RAISE EXCEPTION 'esperado 4 rows 03-16 clean=92,50 accrued=0, achei %', n; END IF;
  -- nada deve sobrar em 03-15 12:00
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id IN (1058788,1058789,1058786,1058787)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date = timestamptz '2026-03-15 12:00:00+00';
  IF bad <> 0 THEN RAISE EXCEPTION 'ainda ha % rows em 03-15 12:00', bad; END IF;
  RAISE NOTICE 'OK: amort movida p/ 03-16, accrued=0, dirty=92,50';
END $$;

-- (4) POST-CHECK: rows 03-15/03-16 + vigente
SELECT a.name, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price+v.accrued_interest) dirty, v.cash_flow, v.last_valuation_flag vig
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058788,1058789,1058786,1058787)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date >= timestamptz '2026-03-15 00:00:00-03'
ORDER BY a.name, v.date;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
