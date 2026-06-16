-- ============================================================================
-- apaga_valuations_CONS29_desde_0603_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- CONS-29: reconstruir desde 06-03 p/ matar o residuo +0.016 (double-accrual do
-- booking antigo do amort 06-03: a daily 03:00 tinha accrued 1.13365111 = certo, mas o
-- event 12:00 accruou +0.016249 a mais). Bate exato com V1 ate 06-02.
-- Mantem a daily PRE-amort de 06-03 03:00 (clean 21.97797920, accrued 1.13365111,
--   dirty 23.11163031 = V1 last_value EXATO) como anchor; apaga o event 12:00 (amort bugado)
--   e tudo forward (06-04 .. 06-15), serie+token.
-- Depois o usuario re-booka 06-03/06-09/06-12 (engine fixo carrega a ultima daily no amort,
--   nao accrua o dia -> deve dar V1) e re-accrua. 06-15 (vencimento) = redemption, a' parte.
--
-- Serie 1058821 (CR-CONSORTIUMS-29-01-SINGLE) + token 1058822 (NXCOF26-3). qty 20551. CDI.
-- AUDITORIA: linha antiga -> histories (delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: seed 06-03 03:00 mantido + amostra do que apaga
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price+v.accrued_interest) AS dirty, v.cash_flow,
       CASE WHEN v.date > timestamptz '2026-06-03 00:00:00-03' THEN '-> DELETE' ELSE '(mantem seed pre-amort)' END AS acao
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058821,1058822)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date >= timestamptz '2026-06-02 00:00:00-03' AND v.date <= timestamptz '2026-06-04 00:00:00-03'
ORDER BY a.name, v.date;

-- (1) histories — tudo > 06-03 00:00
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'CONS-29 reconstrucao desde 06-03: apaga event amort bugado (double-accrual +0.016) e forward p/ re-bookar limpo'
FROM valuations v
WHERE v.asset_id IN (1058821,1058822)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date > timestamptz '2026-06-03 00:00:00-03';

-- (2) DELETE > 06-03 00:00 (mantem a daily pre-amort 06-03 03:00)
DELETE FROM valuations
WHERE asset_id IN (1058821,1058822)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date > timestamptz '2026-06-03 00:00:00-03';

-- (3) GUARDA: seed 06-03 03:00 presente (2 linhas, dirty 23.11163031); nada > 06-03 00:00
DO $$
DECLARE seedok int; bad int; dty numeric;
BEGIN
  SELECT count(*) INTO seedok FROM valuations
   WHERE asset_id IN (1058821,1058822)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date = timestamptz '2026-06-03 00:00:00-03';
  IF seedok <> 2 THEN RAISE EXCEPTION 'seed 06-03 03:00 ausente (% de 2)', seedok; END IF;
  SELECT (clean_price+accrued_interest) INTO dty FROM valuations
   WHERE asset_id=1058821 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date = timestamptz '2026-06-03 00:00:00-03';
  IF abs(dty - 23.11163031) > 0.00001 THEN RAISE EXCEPTION 'seed dirty=% (esperado 23.11163031)', dty; END IF;
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id IN (1058821,1058822)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date > timestamptz '2026-06-03 00:00:00-03';
  IF bad <> 0 THEN RAISE EXCEPTION 'ainda ha % linhas > 06-03 00:00', bad; END IF;
  RAISE NOTICE 'OK: seed 06-03 mantido (dirty=%), forward apagado', dty;
END $$;

-- (4) POST-CHECK
SELECT a.name AS ativo, max(v.date) AS ultima, count(*) AS n
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058821,1058822)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
GROUP BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
