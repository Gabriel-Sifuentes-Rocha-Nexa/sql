-- ============================================================================
-- apaga_valuations_desde_0616_NXCOA27-10_PROD.sql        (PROD via tunel :5003, sslmode=require)
-- ----------------------------------------------------------------------------
-- Token NXCOA27-10 (1412931) + serie CR-CONSORTIUMS-43-01-SINGLE (1412930) = PAR.
-- Bug: accrual comecou 1 dia util ATRASADO no V2. Integralizacao 1a parcela = 2026-06-15;
-- o V1 liga o accrual em 06-16 (= 1a position do CR-mae), mas o V2 so' ligou em 06-17.
-- Acao: apagar valuations do PAR (serie+token) de 2026-06-16 em diante p/ RE-ACCRUAR.
-- Apos o delete a vigente de cada um volta p/ 06-15 (dirty 100, accrued 0). O usuario
-- re-accrua (engine); espera-se que passe a comecar em 06-16 (= V1):
--   06-16 -> accrued 0.06126221 (dirty 100.06126221) ; 06-17 -> 0.12256195 (dirty 100.12256195)
-- NAO mexe em positions (a integralizacao 06-15/06-16 esta' correta).
-- AUDITORIA: histories (delete) ANTES. DRY-RUN: BEGIN..ROLLBACK; trocar por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — o que sai (>=06-16) e o que fica (<=06-15) no par
SELECT a.name AS ativo, v.id, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price+COALESCE(v.accrued_interest,0)) AS dirty, v.last_valuation_flag AS vig,
       CASE WHEN v.date >= timestamptz '2026-06-16 00:00:00-03' THEN 'APAGA' ELSE 'mantem' END AS acao
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1412930,1412931) AND v.date::date BETWEEN '2026-06-14' AND '2026-06-18'
ORDER BY a.name, v.date;

-- (1) histories — valuations a apagar (par serie+token, >=06-16)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'delete',
       'NXCOA27-10/serie: apaga valuations >=2026-06-16 p/ re-accruar (accrual comecou 1d atrasado; integralizacao 06-15, V1 liga accrual em 06-16)'
FROM valuations v WHERE v.asset_id IN (1412930,1412931) AND v.date >= timestamptz '2026-06-16 00:00:00-03';

-- (2) DELETE
DELETE FROM valuations WHERE asset_id IN (1412930,1412931) AND date >= timestamptz '2026-06-16 00:00:00-03';

-- (3) GUARDA
DO $$
DECLARE n_after int; ns int; nt int; sd timestamptz; td timestamptz; sdir numeric; tdir numeric;
BEGIN
  SELECT count(*) INTO n_after FROM valuations WHERE asset_id IN (1412930,1412931) AND date >= timestamptz '2026-06-16 00:00:00-03';
  IF n_after <> 0 THEN RAISE EXCEPTION 'restaram % valuations >=06-16 no par', n_after; END IF;
  SELECT count(*) INTO ns FROM valuations WHERE asset_id=1412930;
  SELECT count(*) INTO nt FROM valuations WHERE asset_id=1412931;
  IF ns <> nt THEN RAISE EXCEPTION 'serie (%) e token (%) dessincronizados', ns, nt; END IF;
  -- vigente de cada um volta p/ 06-15, dirty 100
  SELECT date, clean_price+COALESCE(accrued_interest,0) INTO sd, sdir FROM valuations WHERE asset_id=1412930 AND last_valuation_flag;
  SELECT date, clean_price+COALESCE(accrued_interest,0) INTO td, tdir FROM valuations WHERE asset_id=1412931 AND last_valuation_flag;
  IF sd::date <> DATE '2026-06-15' OR td::date <> DATE '2026-06-15' THEN RAISE EXCEPTION 'vigente nao voltou p/ 06-15 (serie=%, token=%)', sd, td; END IF;
  IF sdir <> 100 OR tdir <> 100 THEN RAISE EXCEPTION 'dirty vigente != 100 (serie=%, token=%)', sdir, tdir; END IF;
  RAISE NOTICE 'OK: par serie+token sem valuations >=06-16; vigente=06-15 dirty 100 (% linhas cada). Pronto p/ re-accruar.', ns;
END $$;

-- (4) POST-CHECK
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest,
       (v.clean_price+COALESCE(v.accrued_interest,0)) AS dirty, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1412930,1412931) AND v.date::date BETWEEN '2026-06-14' AND '2026-06-18'
ORDER BY a.name, v.date;
SELECT operation, table_name, count(*) FROM histories WHERE created_by='gabriel_sifuentes' AND description LIKE 'NXCOA27-10/serie:%' GROUP BY operation, table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
