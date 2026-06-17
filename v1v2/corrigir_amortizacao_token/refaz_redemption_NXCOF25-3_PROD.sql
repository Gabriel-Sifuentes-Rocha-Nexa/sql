-- ============================================================================
-- refaz_redemption_NXCOF25-3_PROD.sql            (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Token NXCOF25-3 (asset 1946, qty 1340) — tokenizacao direta de 2 cotas:
--   CANOPUS-8300 (1906) redimiu 06-02 17:40 (R$105.949,58) ; ANCORA-99 (1892) redimiu 06-03 (R$36.741,27).
-- O V2 fatiou a redemption do token: 06-02 (clean->20,99) + 06-03 (clean->0), com diarias-lixo.
-- CERTO (= V1, conforme Gabriel): token cai a ZERO em 2025-06-02 distribuindo 142.178,94
--   (=> 106,10368657/un). Caixa: 105.949,58+36.741,27=142.690,85, distribui 142.178,94, RETEM 511,91.
-- Decisao do Gabriel: MOVER o resgate do subjacente ANCORA p/ 06-02 tambem (caixa nunca negativo).
--
-- Mecanica (UPDATE move data/valor; DELETE so' do lixo; flags por trigger; sem INSERT):
--   VALUATIONS token 1946:
--     UPDATE 648267 (06-02 20:00, clean 20,99): -> clean 0, accrued 0, cash_flow 106.10368657
--     DELETE 633965 (06-03 diaria clean100), 649697 (06-03 snap 20,99), 649698 (06-03 final clean0)
--   VALUATIONS cota ANCORA 1892 (3 metodologias):
--     UPDATE 535433/535434/535435 (redemption) -> date 2025-06-02 17:40:02
--     DELETE 544132/589280/612321 (diarias 06-03 00:00, viram lixo apos mover)
--   POSITIONS:
--     UPDATE 16805 (ANCORA caixa-in) -> date 06-02 17:40:02, total 142690.85
--     UPDATE 16806 (ANCORA cota out) -> date 06-02 17:40:02
--     DELETE 21076 (block 3808, BRL AMORTIZATION -105949.58 fragmentada)
--     UPDATE 21077 (block 3809, BRL) -> date 06-02 20:00, variation -142178.94, total 511.91
--     UPDATE 21078 (block 3809, token -1340) -> date 06-02 20:00
--   (mantem block 3112 = resgate CANOPUS, ja' em 06-02; e a valuation da CANOPUS, ja' 06-02)
-- AUDITORIA: cada linha -> histories (update/delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW
SELECT 'VAL token' AS t, v.id, v.date::text, v.clean_price::text, v.cash_flow::text, v.last_valuation_flag::text AS vig
FROM valuations v WHERE v.asset_id=1946 AND v.date::date BETWEEN '2025-06-02' AND '2025-06-03'
UNION ALL
SELECT 'VAL ancora', v.id, v.date::text, v.clean_price::text, v.cash_flow::text, v.last_valuation_flag::text
FROM valuations v WHERE v.asset_id=1892 AND v.date::date BETWEEN '2025-06-02' AND '2025-06-03'
UNION ALL
SELECT 'POS', p.id, p.date::text, tt.name, p.variation::text, p.total_quantity::text
FROM positions p JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.id IN (16755,16805,16806,21076,21077,21078)
ORDER BY 1,3;

-- (1) histories — valuations a APAGAR
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'delete',
       'NXCOF25-3 apaga diarias/fracoes lixo 06-03 (token + cota ANCORA) ao consolidar redemption em 06-02'
FROM valuations v WHERE v.id IN (633965,649697,649698, 544132,589280,612321);

-- (2) histories — valuations a ATUALIZAR
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'update',
       'NXCOF25-3 redemption token -> 06-02 clean0 cash_flow 106.10368657 (142178.94/1340); cota ANCORA redemption -> 06-02'
FROM valuations v WHERE v.id IN (648267, 535433,535434,535435);

-- (3) histories — positions a APAGAR
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','positions', to_jsonb(p),'delete',
       'NXCOF25-3 apaga perna BRL AMORTIZATION fragmentada (block 3808)'
FROM positions p WHERE p.id IN (21076);

-- (4) histories — positions a ATUALIZAR
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','positions', to_jsonb(p),'update',
       'NXCOF25-3 move ANCORA caixa-in/cota -> 06-02; redemption token (BRL 142178.94 retem 511.91 + baixa 1340) -> 06-02'
FROM positions p WHERE p.id IN (16805,16806,21077,21078);

-- (5) DELETE valuations lixo
DELETE FROM valuations WHERE id IN (633965,649697,649698, 544132,589280,612321);

-- (6) UPDATE valuations
UPDATE valuations SET clean_price=0, accrued_interest=0, cash_flow=106.10368657 WHERE id=648267;          -- redemption token (ja' 06-02 20:00)
UPDATE valuations SET date = timestamptz '2025-06-02 17:40:02-03' WHERE id IN (535433,535434,535435);       -- cota ANCORA redemption -> 06-02

-- (7) DELETE position lixo
DELETE FROM positions WHERE id IN (21076);

-- (8) UPDATE positions
UPDATE positions SET date = timestamptz '2025-06-02 17:40:02-03', total_quantity = 142690.85 WHERE id=16805;  -- ANCORA caixa-in
UPDATE positions SET date = timestamptz '2025-06-02 17:40:02-03' WHERE id=16806;                              -- ANCORA cota out
UPDATE positions SET date = timestamptz '2025-06-02 20:00:00-03', variation=-142178.94, total_quantity=511.91 WHERE id=21077;  -- caixa-out
UPDATE positions SET date = timestamptz '2025-06-02 20:00:00-03' WHERE id=21078;                              -- baixa token

-- (9) GUARDA
DO $$
DECLARE vdate timestamptz; vclean numeric; vcf numeric; n int; tok_tot numeric; tok_date timestamptz; brl_tot numeric; brl_date timestamptz;
BEGIN
  SELECT date,clean_price,cash_flow INTO vdate,vclean,vcf FROM valuations
   WHERE asset_id=1946 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost') AND last_valuation_flag;
  IF vdate <> timestamptz '2025-06-02 20:00:00-03' THEN RAISE EXCEPTION 'token vigente date=% (esp 06-02 20:00)', vdate; END IF;
  IF vclean <> 0 THEN RAISE EXCEPTION 'token vigente clean=% (esp 0)', vclean; END IF;
  IF round(vcf,8) <> 106.10368657 THEN RAISE EXCEPTION 'token vigente cf=% (esp 106.10368657)', vcf; END IF;

  SELECT count(*) INTO n FROM valuations WHERE asset_id=1946 AND date::date='2025-06-03';
  IF n <> 0 THEN RAISE EXCEPTION 'restaram % valuations token em 06-03', n; END IF;
  SELECT count(*) INTO n FROM valuations WHERE asset_id=1892 AND date::date='2025-06-03';
  IF n <> 0 THEN RAISE EXCEPTION 'restaram % valuations cota ANCORA em 06-03', n; END IF;

  SELECT total_quantity,date INTO tok_tot,tok_date FROM positions
   WHERE asset_id=1946 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='token investments') AND last_position_flag;
  IF tok_tot <> 0 OR tok_date <> timestamptz '2025-06-02 20:00:00-03' THEN RAISE EXCEPTION 'token pos total=% date=% (esp 0/06-02)', tok_tot,tok_date; END IF;

  SELECT total_quantity,date INTO brl_tot,brl_date FROM positions
   WHERE asset_id=2 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='assets pledged as collateral - NXCOF25-3') AND last_position_flag;
  IF brl_tot <> 511.91 OR brl_date <> timestamptz '2025-06-02 20:00:00-03' THEN RAISE EXCEPTION 'BRL colateral total=% date=% (esp 511.91/06-02)', brl_tot,brl_date; END IF;

  RAISE NOTICE 'OK NXCOF25-3: redemption 06-02 clean0 cf 106.10368657/un (142178.94), token 0, retido 511.91, sem lixo 06-03';
END $$;

-- (10) POST-CHECK
SELECT 'token' AS o, v.date, v.clean_price, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v WHERE v.asset_id=1946 AND v.date::date BETWEEN '2025-06-02' AND '2025-06-03' ORDER BY v.date;
SELECT tt.name AS txn, p.date, p.variation, p.total_quantity, p.last_position_flag AS vig
FROM positions p JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.id IN (16755,16805,16806,21077,21078) ORDER BY p.date,p.id;
SELECT operation, table_name, count(*) FROM histories WHERE created_by='gabriel_sifuentes' AND description LIKE 'NXCOF25-3 %' GROUP BY operation,table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
