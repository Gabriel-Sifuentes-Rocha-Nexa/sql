-- ============================================================================
-- apaga_redemption_senior_e_antigas_FGTS08_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- A redencao do MEZZ falhou por UniqueViolation: a perna de caixa do mezz tenta
-- (2026-04-17 16:00:00, holder 1058783, BRL, conta 10), mas o SENIOR ja ocupa esse slot.
-- Solucao: apagar a redencao do SENIOR inteira (block 2606168162326088969) + os 2 valuations
-- 04-17 + as 2 pernas antigas (AMORTIZATION 12:00 da redencao bugada), deixando 04-17 LIMPO.
-- Depois o usuario re-booka SENIOR+MEZZ JUNTOS (engine escalona 16:00:00/16:00:01).
--
-- Apaga:
--   VALUATIONS: serie 1058788 + token 1058789, date 04-17 (ids 30740314, 30740315; clean 0).
--   POSITIONS block 2606168162326088969 (4 pernas): caixa -33.909.644,41 / colateral -348000 /
--     token integralized -359908 / token investments +11908.
--   POSITIONS antigas: id 4512101 (-347905,72) e 4512099 (-31905,60).
-- Apos: senior valuation volta vigente p/ 04-16 (clean 92,50); token positions voltam
--   integralized 359908 / token investments -11908; colateral volta +348000; caixa SPV recompoe.
-- AUDITORIA: linhas antigas -> histories (delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW
SELECT 'VAL' tipo, v.id, a.name ativo, v.date::text, v.clean_price::text val, v.cash_flow::text cf
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058788,1058789) AND v.date>='2026-04-17 00:00:00-03' AND v.date<'2026-04-18 00:00:00-03'
UNION ALL
SELECT 'POS', p.id, a.name, p.date::text, fa.name, p.variation::text
FROM positions p JOIN entities a ON a.id=p.asset_id LEFT JOIN financial_accounts fa ON fa.id=p.financial_account_id
WHERE p.block_id=2606168162326088969 OR p.id IN (4512101,4512099)
ORDER BY 1, 3;

-- (1) histories — valuations (delete)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'delete',
       'FGTS-08 apaga redemption senior 04-17 (refazer junto c/ mezz; colisao unique no caixa 16:00)'
FROM valuations v
WHERE v.asset_id IN (1058788,1058789) AND v.date>='2026-04-17 00:00:00-03' AND v.date<'2026-04-18 00:00:00-03';

-- (2) histories — positions (delete): redemption senior + 2 antigas
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','positions', to_jsonb(p),'delete',
       'FGTS-08 apaga pernas redemption senior (block 2606168162326088969) + 2 antigas (4512101/4512099)'
FROM positions p WHERE p.block_id=2606168162326088969 OR p.id IN (4512101,4512099);

-- (3) DELETE valuations 04-17 senior
DELETE FROM valuations
WHERE asset_id IN (1058788,1058789) AND date>='2026-04-17 00:00:00-03' AND date<'2026-04-18 00:00:00-03';

-- (4) DELETE positions: redemption senior + 2 antigas
DELETE FROM positions WHERE block_id=2606168162326088969 OR id IN (4512101,4512099);

-- (5) GUARDA
DO $$
DECLARE nval int; npos int; sdate timestamptz; tq_int numeric; tq_inv numeric;
BEGIN
  SELECT count(*) INTO nval FROM valuations WHERE asset_id IN (1058788,1058789)
     AND date>='2026-04-17 00:00:00-03' AND date<'2026-04-18 00:00:00-03';
  IF nval<>0 THEN RAISE EXCEPTION 'restaram % valuations 04-17 senior', nval; END IF;
  SELECT count(*) INTO npos FROM positions WHERE block_id=2606168162326088969 OR id IN (4512101,4512099);
  IF npos<>0 THEN RAISE EXCEPTION 'restaram % positions (block/antigas)', npos; END IF;
  -- senior valuation volta vigente p/ 04-16
  SELECT max(date) INTO sdate FROM valuations WHERE asset_id=1058788
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost') AND last_valuation_flag;
  IF sdate <> timestamptz '2026-04-16 03:00:00+00' THEN RAISE EXCEPTION 'senior vigente=% (esperado 04-16 03:00)', sdate; END IF;
  -- token positions voltam 359908 / -11908
  SELECT total_quantity INTO tq_int FROM positions WHERE asset_id=1058789 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='integralized tokens') AND last_position_flag;
  SELECT total_quantity INTO tq_inv FROM positions WHERE asset_id=1058789 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='token investments') AND last_position_flag;
  IF tq_int<>359908 OR tq_inv<>-11908 THEN RAISE EXCEPTION 'token positions nao voltaram (int=%, inv=%)', tq_int, tq_inv; END IF;
  RAISE NOTICE 'OK: 04-17 senior limpo; senior vigente 04-16 clean 92,50; token 359908/-11908';
END $$;

-- (6) POST-CHECK
SELECT a.name, v.date, v.clean_price, v.accrued_interest, v.last_valuation_flag vig
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1058788,1058789) AND v.last_valuation_flag ORDER BY a.name;
SELECT a.name ativo, fa.name conta, p.total_quantity
FROM positions p JOIN entities a ON a.id=p.asset_id JOIN financial_accounts fa ON fa.id=p.financial_account_id
WHERE p.asset_id IN (1058789,1058787) AND p.last_position_flag AND fa.name IN ('integralized tokens','token investments')
ORDER BY a.name, fa.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
