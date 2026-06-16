-- ============================================================================
-- apaga_dailies_CONS40_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- CONS-40: V2 NUNCA accruou — clean=100/accrued=0 em TODAS as dailies (06-02..06-13),
--   enquanto V1 accrua desde 06-05 (descola -0.06/dia, ja' -0.37 em 06-12).
-- A taxa esta' CERTA (0.17 PREFIXADO, pct 1.0 = V1). Irmaos CONS-39/42 accruam normal.
-- Causa: accrual "so' preenche buraco, nao sobrescreve" -> as dailies carry-forward em
--   accrued=0 BLOQUEIAM o re-accrual (engine nao ve buraco).
-- Fix: apagar TODAS as dailies > emissao 06-02 (manter so' o evento de emissao 06-02,
--   clean=100), e o usuario re-accrua -> engine preenche 06-03+ na taxa 0.17.
--
-- Serie 1395535 (CR-CONSORTIUMS-40-01-SINGLE) + token 1395536 (NXCOD29-4). qty 32431.
-- (Emissoes: serie 06-02 12:00Z, token 06-02 12:01Z — mantidas; apaga so' de 06-03 em diante.)
-- RISCO: se mesmo apos delete+re-accrual continuar 0, e' config mais profunda do engine
--   (nao a teoria do buraco) -> investigar. Conferir read-only depois do re-accrual.
-- AUDITORIA: linha antiga -> histories (delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: o que sera apagado (deve ser tudo de 06-03+ , accrued=0)
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest,
       CASE WHEN v.date >= timestamptz '2026-06-03 00:00:00-03' THEN '-> DELETE' ELSE '(mantem emissao)' END AS acao
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1395535,1395536)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
ORDER BY a.name, v.date;

-- (1) histories — valuations a apagar (>= 06-03)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'CONS-40 apaga dailies carry-forward accrued=0 (>=06-03) p/ desbloquear re-accrual na taxa 0.17'
FROM valuations v
WHERE v.asset_id IN (1395535,1395536)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date >= timestamptz '2026-06-03 00:00:00-03';

-- (2) DELETE dailies >= 06-03 (mantem so' as emissoes de 06-02)
DELETE FROM valuations
WHERE asset_id IN (1395535,1395536)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date >= timestamptz '2026-06-03 00:00:00-03';

-- (3) GUARDA: so' restam as 2 emissoes de 06-02 (clean=100); nada de 06-03+
DO $$
DECLARE bad int; seed int;
BEGIN
  SELECT count(*) INTO seed FROM valuations
   WHERE asset_id IN (1395535,1395536)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date::date = DATE '2026-06-02' AND clean_price=100;
  IF seed <> 2 THEN RAISE EXCEPTION 'emissao 06-02 ausente (% de 2)', seed; END IF;
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id IN (1395535,1395536)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date >= timestamptz '2026-06-03 00:00:00-03';
  IF bad <> 0 THEN RAISE EXCEPTION 'ainda ha % linhas >=06-03', bad; END IF;
  RAISE NOTICE 'OK: somente as 2 emissoes 06-02 mantidas, dailies 06-03+ apagadas';
END $$;

-- (4) POST-CHECK
SELECT a.name AS ativo, max(v.date) AS ultima, count(*) AS n
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1395535,1395536)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
GROUP BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
