-- ============================================================================
-- corrige_cf_0603_CONS29_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- CONSORTIUMS-29, evento de amort 2026-06-03: clean caiu CERTO (21.97797920 ->
-- 20.09398120 = drop 1.883998 = juros_V1) e accrued foi mantido. O UNICO erro e'
-- o bug classico: cash_flow lancado como -clean_price (-20.09398120) em vez de
-- +juros (1.883998). Fix cirurgico: UPDATE cash_flow := 1.883998 na serie + token.
-- Clean NAO muda (ja esta certo) -> nao precisa re-accruar nada por causa disto.
-- (positions do consorcio sao mecanica de REDEMPTION de cota, fora do escopo do cf-fix.)
--
-- Par: CR-CONSORTIUMS-29-01-SINGLE <-> NXCOF26-3. Evento = date::date 06-03 AND cash_flow<>0.
-- AUDITORIA: linha antiga -> `histories` (operation='update', created_by gabriel_sifuentes) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: as 2 linhas-alvo (serie+token), antes
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest, v.cash_flow AS cf_atual,
       1.883998::numeric AS cf_novo
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE a.name IN ('CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3')
  AND v.date::date='2026-06-03' AND v.cash_flow<>0
ORDER BY a.name;

-- (1) histories antes do UPDATE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'update',
       'cf-fix CONSORTIUMS-29 06-03: cash_flow -clean (-20.09398120) -> +juros 1.883998 (clean ja correto)'
FROM valuations v
WHERE v.asset_id IN (SELECT id FROM entities WHERE name IN ('CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3'))
  AND v.date::date='2026-06-03' AND v.cash_flow<>0;

-- (2) UPDATE
UPDATE valuations
SET cash_flow = 1.883998
WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3'))
  AND date::date='2026-06-03' AND cash_flow<>0;

-- (3) GUARDA: exatamente 2 linhas, cash_flow agora = 1.883998, clean intacto
DO $$
DECLARE n int; n_bad int;
BEGIN
  SELECT count(*) INTO n FROM valuations
   WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3'))
     AND date::date='2026-06-03' AND cash_flow=1.883998;
  IF n <> 2 THEN RAISE EXCEPTION 'esperava 2 linhas com cash_flow=1.883998, achei %', n; END IF;

  SELECT count(*) INTO n_bad FROM valuations
   WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3'))
     AND date::date='2026-06-03' AND cash_flow<>0 AND round(clean_price,8)<>20.09398120;
  IF n_bad <> 0 THEN RAISE EXCEPTION 'clean_price do evento 06-03 mudou (% linhas)', n_bad; END IF;
  RAISE NOTICE 'OK: cash_flow 06-03 corrigido p/ 1.883998 em serie+token; clean intacto';
END $$;

-- (4) POST-CHECK
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest, v.cash_flow
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE a.name IN ('CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3')
  AND v.date::date='2026-06-03' ORDER BY a.name, v.date;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
