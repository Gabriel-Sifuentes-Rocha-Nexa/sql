-- ============================================================================
-- refaz_redemption_NXNIB25-1_PROD.sql            (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Token NXNIB25-1 (asset 762, qty 582) — tokenizacao direta da NTN-I/2025-02-15.
-- A redemption do token esta' na DATA ERRADA (2025-02-17 20:00). O CERTO (= V1): a
-- distribuicao e o zeramento acontecem em 2025-02-18, no mesmo dia. Valor inalterado
-- (97,92603093/unidade x 582 = 56.992,95) — Gabriel so' corrigiu a data.
--
-- O resgate do SUBJACENTE (NTN-I, block 1901, caixa-in 56.992,95 em 02-17 09:00) FICA.
-- So' o nivel-token (valuation clean=0 + perna BRL out + baixa do token) move p/ 02-18.
-- accrued da NTN-I e' FX/PTAX (ruidoso, nao-extrapolavel) — por isso NAO se cria diaria
-- intermediaria; a vigente ate' 02-18 segue a diaria 02-17 09:00 (clean 100.16).
--
-- Mecanica (so' UPDATE de data; flags recompostas por trigger):
--   VALUATIONS 762:  UPDATE 196211 (clean 0, vigente): date -> 2025-02-18 20:00
--   POSITIONS block 1903:  id 10979 (BRL -56992.95) e id 10980 (token -582): date -> 02-18 20:00
-- AUDITORIA: cada linha -> histories (update) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW
SELECT 'VAL antes' AS t, v.id, v.date::text, v.clean_price::text, v.accrued_interest::text, v.cash_flow::text, v.last_valuation_flag AS vig
FROM valuations v WHERE v.id=196211
UNION ALL
SELECT 'POS antes', p.id, p.date::text, fa.name, tt.name, p.variation::text, p.last_position_flag
FROM positions p JOIN financial_accounts fa ON fa.id=p.financial_account_id JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.id IN (10979,10980,10940,10941)
ORDER BY 1,3;

-- (1) histories — valuation (update)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'update',
       'NXNIB25-1 move redemption 02-17->02-18 (distribuicao e zeramento no mesmo dia, igual V1; valor inalterado)'
FROM valuations v WHERE v.id=196211;

-- (2) histories — positions (update)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','positions', to_jsonb(p),'update',
       'NXNIB25-1 move redemption block 1903 (BRL out + baixa token) 02-17->02-18'
FROM positions p WHERE p.id IN (10979,10980);

-- (3) UPDATE valuation -> 02-18
UPDATE valuations SET date = timestamptz '2025-02-18 20:00:00-03' WHERE id = 196211;

-- (4) UPDATE positions -> 02-18
UPDATE positions SET date = timestamptz '2025-02-18 20:00:00-03' WHERE id IN (10979,10980);

-- (5) GUARDA
DO $$
DECLARE vdate timestamptz; vclean numeric; vcf numeric; tok_tot numeric; tok_date timestamptz; brl_date timestamptz;
BEGIN
  SELECT date, clean_price, cash_flow INTO vdate, vclean, vcf
    FROM valuations WHERE asset_id=762 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost') AND last_valuation_flag;
  IF vdate <> timestamptz '2025-02-18 20:00:00-03' THEN RAISE EXCEPTION 'vigente date=% (esperado 02-18 20:00)', vdate; END IF;
  IF vclean <> 0 THEN RAISE EXCEPTION 'vigente clean=% (esperado 0)', vclean; END IF;
  IF round(vcf,8) <> 97.92603093 THEN RAISE EXCEPTION 'vigente cash_flow=% (esperado 97.92603093 inalterado)', vcf; END IF;

  SELECT total_quantity, date INTO tok_tot, tok_date FROM positions
   WHERE asset_id=762 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='token investments') AND last_position_flag;
  IF tok_tot <> 0 OR tok_date <> timestamptz '2025-02-18 20:00:00-03' THEN RAISE EXCEPTION 'token pos total=% date=% (esperado 0 / 02-18)', tok_tot, tok_date; END IF;

  SELECT date INTO brl_date FROM positions
   WHERE asset_id=2 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='assets pledged as collateral - NXNIB25-1') AND last_position_flag;
  IF brl_date <> timestamptz '2025-02-18 20:00:00-03' THEN RAISE EXCEPTION 'BRL colateral vigente date=% (esperado 02-18)', brl_date; END IF;

  RAISE NOTICE 'OK NXNIB25-1: redemption movida p/ 02-18, clean 0, cash_flow 97.92603093/un, token 0';
END $$;

-- (6) POST-CHECK
SELECT a.name, v.date, v.clean_price, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id=v.asset_id WHERE v.id=196211;
SELECT fa.name AS conta, tt.name AS txn, p.date, p.variation, p.total_quantity, p.last_position_flag AS vig
FROM positions p JOIN financial_accounts fa ON fa.id=p.financial_account_id JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.id IN (10979,10980,10940,10941) ORDER BY p.date, p.id;
SELECT operation, table_name, count(*) FROM histories
WHERE created_by='gabriel_sifuentes' AND description LIKE 'NXNIB25-1 %' GROUP BY operation, table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
