-- ============================================================================
-- corrige_NXCOF25-3_igual_v1_PROD.sql            (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- CORRIGE o fix anterior (refaz_redemption_NXCOF25-3) que ERRADAMENTE consolidou
-- a redemption em 06-02. O V1 tem DUAS amortizacoes (token_amortization):
--   06-02  CANOPUS  distribui 105.949,58  -> pu V1 = 26,769446
--   06-03  ANCORA   distribui  36.741,27  -> pu V1 = -0,632523 (vigente, fica)
-- Total distribuido = 142.690,85 (NAO 142.178,94). Por unidade (/1340): 79.06685075 e 27.41885821.
-- Alvo: valuations do token = V1 (clean = pu V1; accrued 0). ANCORA volta p/ 06-03.
--
-- IDEMPOTENTE (mesmo alvo partindo do meu fix-errado [PROD] ou do original [LOCAL]):
--   VALUATIONS token 1946:
--     DELETE tudo com date>='2025-06-02 20:00' (apaga a regiao de amort, qualquer que seja)
--     INSERT 06-02 amort: clean 26.769446, accrued 0, cash_flow 79.06685075
--     INSERT 06-03 amort: clean -0.632523, accrued 0, cash_flow 27.41885821 (vigente)
--   VALUATIONS cota ANCORA 1892: UPDATE 535433/34/35 date -> 06-03 14:41:32.850509
--   POSITIONS:
--     DELETE id 21076 (se existir) e INSERT caixa-out CANOPUS 06-02 (-105949.58, AMORTIZATION)
--     UPDATE 16805 (ANCORA caixa-in) -> 06-03 14:41, total 36741.27 ; 16806 -> 06-03 14:41
--     UPDATE 21077 (caixa-out token) -> 06-03 20:00, var -36741.27, total 0 ; 21078 (baixa) -> 06-03 20:00
-- AUDITORIA: histories (delete/update) ANTES. INSERT nao gera history.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW
SELECT 'VAL token 06-02/03' AS t, v.id::text, v.date::text, v.clean_price::text, v.cash_flow::text, v.last_valuation_flag::text
FROM valuations v WHERE v.asset_id=1946 AND v.date::date BETWEEN '2025-06-02' AND '2025-06-03'
UNION ALL
SELECT 'POS', p.id::text, p.date::text, tt.name, p.variation::text, p.total_quantity::text
FROM positions p JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.id IN (16755,16805,16806,21076,21077,21078)
ORDER BY 1,3;

-- (1) histories — valuations do token na regiao amort (a apagar)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'delete',
       'NXCOF25-3 corrige p/ V1: remove regiao amort do token (>=06-02 20:00) p/ reconstruir 2 amorts'
FROM valuations v WHERE v.asset_id=1946 AND v.date >= timestamptz '2025-06-02 20:00:00-03';

-- (2) histories — position caixa-out 06-02 a apagar (se existir, id 21076)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','positions', to_jsonb(p),'delete',
       'NXCOF25-3 corrige p/ V1: remove caixa-out 06-02 antigo (sera reinserido limpo)'
FROM positions p WHERE p.id=21076;

-- (3) histories — valuations cota ANCORA a atualizar (volta p/ 06-03)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'update',
       'NXCOF25-3 corrige p/ V1: cota ANCORA redemption volta p/ 06-03'
FROM valuations v WHERE v.id IN (535433,535434,535435);

-- (4) histories — positions a atualizar (ANCORA p/ 06-03; caixa-out/baixa token p/ 06-03)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','positions', to_jsonb(p),'update',
       'NXCOF25-3 corrige p/ V1: ANCORA caixa-in/cota -> 06-03; caixa-out token -36741.27 e baixa -> 06-03'
FROM positions p WHERE p.id IN (16805,16806,21077,21078);

-- (5) DELETE regiao amort do token + caixa-out 06-02 antigo
DELETE FROM valuations WHERE asset_id=1946 AND date >= timestamptz '2025-06-02 20:00:00-03';
DELETE FROM positions WHERE id=21076;

-- (6) INSERT 06-02 amort (CANOPUS) — copia metadata de uma diaria do token (648265)
INSERT INTO valuations (date, asset_id, lot_id, methodology_id, clean_price, accrued_interest,
   indexer_id, indexer_percentage, spread_over_indexer, spread_over_cdi, spread_over_inflation,
   cash_flow, currency_id, last_valuation_flag, duration_years)
SELECT timestamptz '2025-06-02 20:00:00-03', asset_id, lot_id, methodology_id, 26.769446, 0,
   indexer_id, indexer_percentage, spread_over_indexer, spread_over_cdi, spread_over_inflation,
   79.06685075, currency_id, false, duration_years
FROM valuations WHERE id=648265;

-- (7) INSERT 06-03 amort (ANCORA) — vigente
INSERT INTO valuations (date, asset_id, lot_id, methodology_id, clean_price, accrued_interest,
   indexer_id, indexer_percentage, spread_over_indexer, spread_over_cdi, spread_over_inflation,
   cash_flow, currency_id, last_valuation_flag, duration_years)
SELECT timestamptz '2025-06-03 20:00:00-03', asset_id, lot_id, methodology_id, -0.632523, 0,
   indexer_id, indexer_percentage, spread_over_indexer, spread_over_cdi, spread_over_inflation,
   27.41885821, currency_id, true, duration_years
FROM valuations WHERE id=648265;

-- (8) UPDATE cota ANCORA redemption -> 06-03
UPDATE valuations SET date = timestamptz '2025-06-03 14:41:32.850509-03' WHERE id IN (535433,535434,535435);

-- (9) UPDATE ANCORA caixa-in/cota -> 06-03 ; caixa-out/baixa token -> 06-03
--     (ANTES do INSERT p/ liberar o slot 06-02 20:00 — no PROD o 21077 ainda esta' la' por causa do fix antigo)
UPDATE positions SET date = timestamptz '2025-06-03 14:41:32.850509-03', total_quantity = 36741.27 WHERE id=16805;
UPDATE positions SET date = timestamptz '2025-06-03 14:41:32.850509-03' WHERE id=16806;
UPDATE positions SET date = timestamptz '2025-06-03 20:00:00-03', variation=-36741.27, total_quantity=0 WHERE id=21077;
UPDATE positions SET date = timestamptz '2025-06-03 20:00:00-03' WHERE id=21078;

-- (10) INSERT caixa-out CANOPUS 06-02 (-105949.58, AMORTIZATION) — copia de 16755 (caixa-in CANOPUS)
--      Agora o slot 06-02 20:00 (BRL, conta colateral) esta' livre.
INSERT INTO positions (date, holder_id, asset_id, lot_id, financial_account_id, transaction_type_id,
   variation, total_quantity, block_id, holder_bank_account_id, counterparty_bank_account_id,
   event_code, payment_code, originator_id, broker_id, doc_id, last_position_flag,
   transaction_unit_price, trade_date)
SELECT timestamptz '2025-06-02 20:00:00-03', holder_id, asset_id, lot_id, financial_account_id,
   (SELECT id FROM transaction_types WHERE name='AMORTIZATION'),
   -105949.58, 0, 3808, holder_bank_account_id, counterparty_bank_account_id,
   event_code, payment_code, originator_id, broker_id, doc_id, false,
   transaction_unit_price, trade_date
FROM positions WHERE id=16755;

-- (11) GUARDA
DO $$
DECLARE vdate timestamptz; vclean numeric; vcf numeric; c2 int; n_after int;
        cf0602 numeric; clean0602 numeric; tok_tot numeric; tok_date timestamptz;
        brl_tot numeric; brl_date numeric; anc_tot numeric; co int;
BEGIN
  -- vigente do token = 06-03 amort
  SELECT date,clean_price,cash_flow INTO vdate,vclean,vcf FROM valuations
   WHERE asset_id=1946 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost') AND last_valuation_flag;
  IF vdate <> timestamptz '2025-06-03 20:00:00-03' THEN RAISE EXCEPTION 'token vigente date=% (esp 06-03 20:00)', vdate; END IF;
  IF vclean <> -0.632523 THEN RAISE EXCEPTION 'token vigente clean=% (esp -0.632523)', vclean; END IF;
  IF round(vcf,8) <> 27.41885821 THEN RAISE EXCEPTION 'token vigente cf=% (esp 27.41885821)', vcf; END IF;
  -- 06-02 amort
  SELECT count(*) INTO c2 FROM valuations WHERE asset_id=1946 AND date=timestamptz '2025-06-02 20:00:00-03'
     AND clean_price=26.769446 AND round(cash_flow,8)=79.06685075;
  IF c2 <> 1 THEN RAISE EXCEPTION 'amort 06-02 esperado 1 row (clean 26.769446 cf 79.06685075), achou %', c2; END IF;
  -- nada apos 06-03 20:00
  SELECT count(*) INTO n_after FROM valuations WHERE asset_id=1946 AND date > timestamptz '2025-06-03 20:00:00-03';
  IF n_after <> 0 THEN RAISE EXCEPTION 'token tem % valuations apos 06-03 20:00', n_after; END IF;
  -- caixa-out CANOPUS 06-02 existe
  SELECT count(*) INTO co FROM positions WHERE asset_id=2
     AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='assets pledged as collateral - NXCOF25-3')
     AND date=timestamptz '2025-06-02 20:00:00-03' AND variation=-105949.58;
  IF co <> 1 THEN RAISE EXCEPTION 'caixa-out CANOPUS 06-02 (-105949.58) esperado 1, achou %', co; END IF;
  -- token pos vigente: -1340 total 0 em 06-03
  SELECT total_quantity,date INTO tok_tot,tok_date FROM positions
   WHERE asset_id=1946 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='token investments') AND last_position_flag;
  IF tok_tot <> 0 OR tok_date <> timestamptz '2025-06-03 20:00:00-03' THEN RAISE EXCEPTION 'token pos total=% date=% (esp 0/06-03)', tok_tot,tok_date; END IF;
  -- BRL colateral vigente: total 0 em 06-03 20:00
  SELECT total_quantity INTO brl_tot FROM positions
   WHERE asset_id=2 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='assets pledged as collateral - NXCOF25-3') AND last_position_flag;
  IF brl_tot <> 0 THEN RAISE EXCEPTION 'BRL colateral vigente total=% (esp 0)', brl_tot; END IF;
  RAISE NOTICE 'OK NXCOF25-3: 2 amorts (06-02 clean 26.769446 cf 79.06685075 / 06-03 clean -0.632523 cf 27.41885821), token 0 em 06-03, igual V1';
END $$;

-- (12) POST-CHECK
SELECT v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v WHERE v.asset_id=1946 AND v.date::date BETWEEN '2025-06-02' AND '2025-06-03' ORDER BY v.date;
SELECT a.name AS asset, tt.name AS txn, p.date, p.variation, p.total_quantity, p.last_position_flag AS vig
FROM positions p JOIN entities a ON a.id=p.asset_id JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.financial_account_id=(SELECT id FROM financial_accounts WHERE name='assets pledged as collateral - NXCOF25-3')
   OR (p.asset_id=1946 AND p.financial_account_id=(SELECT id FROM financial_accounts WHERE name='token investments'))
ORDER BY p.date, p.id;
SELECT operation, table_name, count(*) FROM histories WHERE created_by='gabriel_sifuentes' AND description LIKE 'NXCOF25-3 corrige p/ V1%' GROUP BY operation, table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
