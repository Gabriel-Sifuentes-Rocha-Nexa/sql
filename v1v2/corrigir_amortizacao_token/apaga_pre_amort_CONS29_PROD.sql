-- ============================================================================
-- apaga_pre_amort_CONS29_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- CONS-29: amort 06-12 FALTANDO. V1 extraordinary_repayment=10.160054/un
--   (last_value 11.37612671 -> 1.21607271). V2 nunca bookou (sem cash_flow em 06-12).
--   Bate com V1 ate 06-11 (resido fixo ~+0.016 desde 06-03 — secundario, NAO tratado aqui).
-- A daily V2 de 06-12 00:00 (clean=10.173710, accrued=1.218735) e' a referencia PRE-amort.
--   Manter; apagar so' o que vem depois (06-13).
-- Fix: apagar valuations > 06-12 00:00, usuario BOOKA amort 06-12 (10.160054 x 20551 =
--   208799.27), re-accrua 06-13 -> current.
--
-- Serie 1058821 (CR-CONSORTIUMS-29-01-SINGLE) + token 1058822 (NXCOF26-3). qty 20551.
-- NB: CONS-29 e' CDI (indexer CDI, spread 0.0435) — o re-accrual usa a curva CDI.
-- AUDITORIA: linha antiga -> histories (delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: seed pre-amort (06-12 00:00) mantido + o que sera apagado (>06-12 00:00)
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price+v.accrued_interest) AS dirty,
       CASE WHEN v.date > timestamptz '2026-06-12 00:00:00-03' THEN '-> DELETE' ELSE '(mantem pre-amort)' END AS acao
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058821,1058822)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date >= timestamptz '2026-06-11 00:00:00-03' ORDER BY a.name, v.date;

-- (1) histories — valuations a apagar (>06-12 00:00)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'CONS-29 apaga dailies forward (>06-12 00:00) p/ bookar amort 06-12 faltante (10.160054/un) e re-accruar'
FROM valuations v
WHERE v.asset_id IN (1058821,1058822)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date > timestamptz '2026-06-12 00:00:00-03';

-- (2) DELETE > 06-12 00:00 (mantem o seed pre-amort de 06-12)
DELETE FROM valuations
WHERE asset_id IN (1058821,1058822)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date > timestamptz '2026-06-12 00:00:00-03';

-- (3) GUARDA: seed 06-12 00:00 presente; nada >06-12 00:00
DO $$
DECLARE bad int; seed int;
BEGIN
  SELECT count(*) INTO seed FROM valuations
   WHERE asset_id IN (1058821,1058822)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date = timestamptz '2026-06-12 00:00:00-03';
  IF seed <> 2 THEN RAISE EXCEPTION 'seed pre-amort 06-12 00:00 ausente (% de 2)', seed; END IF;
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id IN (1058821,1058822)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date > timestamptz '2026-06-12 00:00:00-03';
  IF bad <> 0 THEN RAISE EXCEPTION 'ainda ha % linhas >06-12 00:00', bad; END IF;
  RAISE NOTICE 'OK: seed pre-amort 06-12 mantido, forward apagado';
END $$;

-- (4) POST-CHECK
SELECT a.name AS ativo, max(v.date) AS ultima, count(*) AS n
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058821,1058822)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
GROUP BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
