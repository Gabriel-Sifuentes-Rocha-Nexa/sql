-- ============================================================================
-- corrige_accrued_0608_FGTS25_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- FGTS-25: amort 06-08 OK no principal (clean caiu 2.78504091 = extraordinary V1),
--   MAS o V2 over-accruou +0.06137105 no dia do amort. Bug "double-accrual no amort":
--   06-05/06/07 (sex+fds) accrued=3.73957915; o V2 accruou a 2a-feira 06-08 ->
--   3.80095020 ANTES de amortizar. O V1 NAO accrua o dia do amort apos fds: usou o
--   valor de sexta (last_value 98.47336701 = dirty de 06-05) -> 98.47336701-2.78504091
--   = 95.68832610. Resultado: V2 fica +0.0614 alto e PROPAGA forward (constante).
--   (Mesmo bug do resido CDI do CONS-29 em 06-03.)
--
-- Fix: forcar accrued de 06-08 (daily 03:00 + event 12:00) de 3.80095020 -> 3.73957915
--   (= valor de sexta 06-05), e apagar 06-09+ p/ o usuario re-accruar do accrued correto.
--   Apos re-accrual: 06-09 = 3.73957915 + 1 du PREFIXADO no clean reduzido ~= V1.
--
-- Serie 1057328 (CR-FGTS-25-01-SINGLE) + token 1057329 (NXFGTSC31-1). qty 30800.
-- Conferido: clean 06-08 (91.94874708) ja' bate V1; so' o accrued estava alto.
-- UPDATE de accrued NAO dispara trigger last_valuation_flag; DELETE dispara (recompoe).
-- AUDITORIA: linha antiga -> histories (update/delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: 06-05..06-09 + acao
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest, (v.clean_price+v.accrued_interest) AS dirty,
       CASE WHEN v.date::date = DATE '2026-06-08' THEN 'UPDATE accrued -> 3.73957915'
            WHEN v.date >= timestamptz '2026-06-09 00:00:00-03' THEN '-> DELETE'
            ELSE '(mantem)' END AS acao
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1057328,1057329)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date >= timestamptz '2026-06-05 00:00:00-03' AND v.date < timestamptz '2026-06-10 00:00:00-03'
ORDER BY a.name, v.date;

-- (1) histories — rows que vao mudar (06-08 update) + apagar (06-09+ delete)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v),
       (CASE WHEN v.date::date = DATE '2026-06-08' THEN 'update' ELSE 'delete' END)::operations_enum,
       'FGTS-25 corrige over-accrual no amort 06-08: accrued 3.80095020 -> 3.73957915 (valor de sexta 06-05) e apaga 06-09+ p/ re-accruar'
FROM valuations v
WHERE v.asset_id IN (1057328,1057329)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND ( (v.date::date = DATE '2026-06-08' AND v.accrued_interest <> 3.73957915)
        OR v.date >= timestamptz '2026-06-09 00:00:00-03' );

-- (2) UPDATE accrued 06-08 (daily 03:00 + event 12:00) -> 3.73957915
UPDATE valuations SET accrued_interest = 3.73957915
WHERE asset_id IN (1057328,1057329)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date::date = DATE '2026-06-08';

-- (3) DELETE 06-09+ (mantem o seed corrigido de 06-08)
DELETE FROM valuations
WHERE asset_id IN (1057328,1057329)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date >= timestamptz '2026-06-09 00:00:00-03';

-- (4) GUARDA: 06-08 accrued=3.73957915 (4 rows); event 06-08 dirty ~= V1 95.68832601; nada >=06-09
DO $$
DECLARE bad int; nupd int; ev numeric;
BEGIN
  SELECT count(*) INTO nupd FROM valuations
   WHERE asset_id IN (1057328,1057329)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date::date = DATE '2026-06-08' AND accrued_interest = 3.73957915;
  IF nupd <> 4 THEN RAISE EXCEPTION '06-08 accrued corrigido em % linhas (esperado 4)', nupd; END IF;
  SELECT (clean_price+accrued_interest) INTO ev FROM valuations
   WHERE asset_id=1057328 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date = timestamptz '2026-06-08 12:00:00+00';
  IF abs(ev - 95.68832601) > 0.00001 THEN RAISE EXCEPTION 'event 06-08 dirty=% (esperado ~95.68832601)', ev; END IF;
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id IN (1057328,1057329)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date >= timestamptz '2026-06-09 00:00:00-03';
  IF bad <> 0 THEN RAISE EXCEPTION 'ainda ha % linhas >=06-09', bad; END IF;
  RAISE NOTICE 'OK: 06-08 accrued=3.73957915, event dirty=% (=V1), 06-09+ apagado', ev;
END $$;

-- (5) POST-CHECK
SELECT a.name AS ativo, max(v.date) AS ultima, count(*) AS n
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1057328,1057329)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
GROUP BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
