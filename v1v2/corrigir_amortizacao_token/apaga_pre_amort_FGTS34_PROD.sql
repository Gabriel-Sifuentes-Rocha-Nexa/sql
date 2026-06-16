-- ============================================================================
-- apaga_pre_amort_FGTS34_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- FGTS-34: amort 06-10 FALTANDO. V1 extraordinary_repayment=4.77925691/un
--   (last_value 101.60929598 -> 96.83003907). V2 nunca amortizou (clean travado em 100;
--   accrua certo, taxa 0.1825 = V1, bate exato ate 06-09).
-- A daily V2 de 06-10 00:00 (clean=100, accrued=1.609296 -> dirty 101.609296) == V1 last_value
--   -> e' a referencia PRE-amort correta. Manter ela; apagar so' o que vem depois (06-11+).
-- Fix: apagar valuations > 06-10 00:00 (mantem o seed pre-amort 06-10), usuario BOOKA amort
--   06-10 (4.77925691 x 141800 = 677698.63), re-accrua 06-11 -> current.
--
-- Serie 1350808 (CR-FGTS-34-01-SINGLE) + token 1350809 (NXFGTSB31-3). qty 141800.
-- AUDITORIA: linha antiga -> histories (delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: seed pre-amort (06-10 00:00) mantido + o que sera apagado (06-11+)
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price+v.accrued_interest) AS dirty,
       CASE WHEN v.date > timestamptz '2026-06-10 00:00:00-03' THEN '-> DELETE' ELSE '(mantem pre-amort)' END AS acao
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1350808,1350809)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date >= timestamptz '2026-06-09 00:00:00-03' ORDER BY a.name, v.date;

-- (1) histories — valuations a apagar (>06-10 00:00)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'FGTS-34 apaga dailies forward (>06-10 00:00) p/ bookar amort 06-10 faltante (4.77925691/un) e re-accruar'
FROM valuations v
WHERE v.asset_id IN (1350808,1350809)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date > timestamptz '2026-06-10 00:00:00-03';

-- (2) DELETE > 06-10 00:00 (mantem o seed pre-amort de 06-10)
DELETE FROM valuations
WHERE asset_id IN (1350808,1350809)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date > timestamptz '2026-06-10 00:00:00-03';

-- (3) GUARDA: seed 06-10 00:00 presente (clean=100); nada >06-10 00:00
DO $$
DECLARE bad int; seed int;
BEGIN
  SELECT count(*) INTO seed FROM valuations
   WHERE asset_id IN (1350808,1350809)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date = timestamptz '2026-06-10 00:00:00-03' AND clean_price=100;
  IF seed <> 2 THEN RAISE EXCEPTION 'seed pre-amort 06-10 00:00 ausente (% de 2)', seed; END IF;
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id IN (1350808,1350809)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date > timestamptz '2026-06-10 00:00:00-03';
  IF bad <> 0 THEN RAISE EXCEPTION 'ainda ha % linhas >06-10 00:00', bad; END IF;
  RAISE NOTICE 'OK: seed pre-amort 06-10 mantido, forward apagado';
END $$;

-- (4) POST-CHECK
SELECT a.name AS ativo, max(v.date) AS ultima, count(*) AS n
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1350808,1350809)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
GROUP BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
