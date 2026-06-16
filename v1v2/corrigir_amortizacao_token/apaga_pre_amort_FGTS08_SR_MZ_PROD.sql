-- ============================================================================
-- apaga_pre_amort_FGTS08_SR_MZ_PROD.sql            (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- CR-FGTS-08 SENIOR (08-01) + MEZZANINE (08-02): reconstrucao.
-- V2 NAO lancou a amort de 03-16 (7,5% princ.+juros; V1 -> clean 92,50) e depois
-- transformou a REDENCAO de 04-17 em amort parcial bugada (cash_flow=-clean, deixou
-- residuo 5,72/5,59 e accruou 2 meses). 1a divergencia = 03-16.
-- Mantem a daily PRE-amort de 03-15 03:00 (clean=100, accrued senior 5.96473125 /
--   mezz 6.53100134 = V1) como ancora; apaga 03-16 .. 06-16 (serie+token).
-- Depois o usuario: (1) booka amort 03-16 -> clean 92,50; (2) accrua ate 04-16;
--   (3) booka REDENCAO 04-17 (zera clean+accrued+positions; cash_flow/un = 94.2175
--   senior / 94.3371 mezz, derivado do delta V1). Sub (08-03) NAO MEXER.
--
-- Series/tokens: SR serie 1058788 / token 1058789 (NXFGTSSRL31-8.1)
--                MZ serie 1058786 / token 1058787 (NXFGTSMZL31-8.2)
-- AUDITORIA: linha antiga -> histories (delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: ancora 03-15 mantida + amostra do que apaga (03-16..03-18 e cauda)
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest, v.cash_flow,
       CASE WHEN v.date > timestamptz '2026-03-15 00:00:00-03' THEN '-> DELETE' ELSE '(mantem ancora pre-amort)' END AS acao
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058788,1058789,1058786,1058787)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND (v.date BETWEEN timestamptz '2026-03-14 00:00:00-03' AND timestamptz '2026-03-18 23:59:00-03'
       OR v.date >= timestamptz '2026-06-15 00:00:00-03')
ORDER BY a.name, v.date;

-- (1) histories — tudo > 03-15
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'FGTS-08 SR/MZ reconstrucao: apaga > 03-15 (amort 03-16 nao lancada + redencao 04-17 bugada + accrual indevido) p/ re-bookar'
FROM valuations v
WHERE v.asset_id IN (1058788,1058789,1058786,1058787)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date > timestamptz '2026-03-15 00:00:00-03';

-- (2) DELETE > 03-15 (mantem a daily pre-amort 03-15 03:00)
DELETE FROM valuations
WHERE asset_id IN (1058788,1058789,1058786,1058787)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date > timestamptz '2026-03-15 00:00:00-03';

-- (3) GUARDA: ancora 03-15 presente (4 linhas, clean=100); nada > 03-15
DO $$
DECLARE seedok int; bad int;
BEGIN
  SELECT count(*) INTO seedok FROM valuations
   WHERE asset_id IN (1058788,1058789,1058786,1058787)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date = timestamptz '2026-03-15 00:00:00-03' AND clean_price=100;
  IF seedok <> 4 THEN RAISE EXCEPTION 'ancora 03-15 clean=100 ausente (% de 4)', seedok; END IF;
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id IN (1058788,1058789,1058786,1058787)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date > timestamptz '2026-03-15 00:00:00-03';
  IF bad <> 0 THEN RAISE EXCEPTION 'ainda ha % linhas > 03-15', bad; END IF;
  RAISE NOTICE 'OK: ancora 03-15 mantida (4 linhas clean=100), forward apagado';
END $$;

-- (4) POST-CHECK
SELECT a.name AS ativo, max(v.date) AS ultima, count(*) AS n
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058788,1058789,1058786,1058787)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
GROUP BY a.name ORDER BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
