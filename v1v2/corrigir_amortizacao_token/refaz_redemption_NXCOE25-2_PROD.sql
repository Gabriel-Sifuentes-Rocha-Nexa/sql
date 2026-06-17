-- ============================================================================
-- refaz_redemption_NXCOE25-2_PROD.sql            (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Token NXCOE25-2 (asset 3032, qty 353) — tokenizacao direta da cota ANCORA-103 (1891).
-- O token NUNCA foi redimido: levou so' um amort parcial e ficou com 362 valuations-fantasma
-- (06-03-2025 .. 2026-05-27, clean travado 97,57); posicao do token ainda 353. O subjacente
-- ANCORA redimiu em 06-03 (R$36.466,94), sobrando -922,94 amort e 35.544 parados.
-- CERTO (= V1, conforme Gabriel): token cai a ZERO em 2025-06-02 distribuindo 36.466,94
--   (=> 103,30577904/un), RETEM 0. Decisao: apagar tudo pos-06-02 + mover subjacente p/ 06-02.
--
-- Mecanica (UPDATE + DELETE + 1 INSERT da baixa do token; flags por trigger):
--   VALUATIONS token 3032:
--     UPDATE 9198332 (06-03 partial clean97,57) -> clean 0, accrued 0, cash_flow 103.30577904, date 06-02 20:00
--     DELETE todas as 3032 com date>06-02 (exclui 9198332 ja' movida) = 361 diarias-fantasma
--   VALUATIONS cota ANCORA 1891 (3 metodologias):
--     UPDATE 535436/535437/535438 (redemption) -> date 06-02 17:40:00
--     DELETE 545411/589844/612928 (diarias 06-03 00:00)
--   POSITIONS:
--     UPDATE 16802 (ANCORA caixa-in) -> 06-02 17:40:00 ; UPDATE 16803 (cota out) -> 06-02 17:40:00
--     UPDATE 3227872 (amort -922,94) -> REDEMPTION, variation -36466.94, total 0, date 06-02 20:00  (caixa-out)
--     INSERT baixa do token: REDEMPTION -353, total 0, date 06-02 20:00, block 2604297748605486156 (copia de 13952)
--   (INSERT nao tem valor antigo -> sem histories; histories so' usa delete/update)
-- AUDITORIA: cada linha alterada/apagada -> histories ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW
SELECT 'token vig atual' AS t, v.id::text, v.date::text, v.clean_price::text, v.cash_flow::text
FROM valuations v WHERE v.asset_id=3032 AND v.last_valuation_flag
UNION ALL
SELECT 'token #apos0602', count(*)::text, '', '', '' FROM valuations v WHERE v.asset_id=3032 AND v.date::date>'2025-06-02'
UNION ALL
SELECT 'pos', p.id::text, p.date::text, tt.name, p.variation::text||' tot '||p.total_quantity::text
FROM positions p JOIN transaction_types tt ON tt.id=p.transaction_type_id WHERE p.id IN (13952,16802,16803,3227872)
ORDER BY 1,2;

-- (1) histories — valuations a ATUALIZAR (redemption token + redemption cota)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'update',
       'NXCOE25-2 redemption token -> 06-02 clean0 cash_flow 103.30577904 (36466.94/353); cota ANCORA redemption -> 06-02'
FROM valuations v WHERE v.id IN (9198332, 535436,535437,535438);

-- (2) histories — positions a ATUALIZAR
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','positions', to_jsonb(p),'update',
       'NXCOE25-2 move ANCORA caixa-in/cota -> 06-02; amort -922,94 reaproveitado como caixa-out redemption -36466.94'
FROM positions p WHERE p.id IN (16802,16803,3227872);

-- (3) histories — valuations a APAGAR (361 fantasmas do token, exceto a 9198332 que vira redemption; + 3 diarias da cota)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'delete',
       'NXCOE25-2 apaga valuations-fantasma pos-06-02 (token nunca redimiu) + diarias 06-03 da cota ANCORA'
FROM valuations v
WHERE (v.asset_id=3032 AND v.date::date>'2025-06-02' AND v.id<>9198332)
   OR v.id IN (545411,589844,612928);

-- (4) UPDATE valuation redemption do token (move + zera + cash_flow)
UPDATE valuations SET clean_price=0, accrued_interest=0, cash_flow=103.30577904,
       date = timestamptz '2025-06-02 20:00:00-03' WHERE id=9198332;

-- (5) UPDATE valuations redemption da cota ANCORA -> 06-02
UPDATE valuations SET date = timestamptz '2025-06-02 17:40:00-03' WHERE id IN (535436,535437,535438);

-- (6) UPDATE positions: caixa-in/cota da ANCORA -> 06-02
UPDATE positions SET date = timestamptz '2025-06-02 17:40:00-03' WHERE id IN (16802,16803);

-- (7) UPDATE position: amort -922,94 reaproveitado como caixa-out da redemption
UPDATE positions SET transaction_type_id=(SELECT id FROM transaction_types WHERE name='REDEMPTION'),
       variation=-36466.94, total_quantity=0, date = timestamptz '2025-06-02 20:00:00-03' WHERE id=3227872;

-- (8) INSERT baixa do token (-353) — nunca existiu; copia colunas da linha de TOKENIZATION 13952
INSERT INTO positions (date, holder_id, asset_id, lot_id, financial_account_id, transaction_type_id,
   variation, total_quantity, block_id, holder_bank_account_id, counterparty_bank_account_id,
   event_code, payment_code, originator_id, broker_id, doc_id, last_position_flag,
   transaction_unit_price, trade_date)
SELECT timestamptz '2025-06-02 20:00:00-03', holder_id, asset_id, lot_id, financial_account_id,
   (SELECT id FROM transaction_types WHERE name='REDEMPTION'),
   -353, 0, 2604297748605486156, holder_bank_account_id, counterparty_bank_account_id,
   event_code, payment_code, originator_id, broker_id, doc_id, true,
   transaction_unit_price, trade_date
FROM positions WHERE id=13952;

-- (9) DELETE valuations-fantasma do token (>06-02; 9198332 ja' eh 06-02) + diarias 06-03 da cota
DELETE FROM valuations
WHERE (asset_id=3032 AND date::date>'2025-06-02')
   OR id IN (545411,589844,612928);

-- (10) GUARDA
DO $$
DECLARE vdate timestamptz; vclean numeric; vcf numeric; n int; tok_tot numeric; tok_date timestamptz; brl_tot numeric; brl_date timestamptz;
BEGIN
  SELECT date,clean_price,cash_flow INTO vdate,vclean,vcf FROM valuations
   WHERE asset_id=3032 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost') AND last_valuation_flag;
  IF vdate <> timestamptz '2025-06-02 20:00:00-03' THEN RAISE EXCEPTION 'token vigente date=% (esp 06-02 20:00)', vdate; END IF;
  IF vclean <> 0 THEN RAISE EXCEPTION 'token vigente clean=% (esp 0)', vclean; END IF;
  IF round(vcf,8) <> 103.30577904 THEN RAISE EXCEPTION 'token vigente cf=% (esp 103.30577904)', vcf; END IF;

  SELECT count(*) INTO n FROM valuations WHERE asset_id=3032 AND date::date>'2025-06-02';
  IF n <> 0 THEN RAISE EXCEPTION 'restaram % valuations-fantasma do token apos 06-02', n; END IF;
  SELECT count(*) INTO n FROM valuations WHERE asset_id=1891 AND date::date='2025-06-03';
  IF n <> 0 THEN RAISE EXCEPTION 'restaram % valuations cota ANCORA em 06-03', n; END IF;

  SELECT total_quantity,date INTO tok_tot,tok_date FROM positions
   WHERE asset_id=3032 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='token investments') AND last_position_flag;
  IF tok_tot <> 0 OR tok_date <> timestamptz '2025-06-02 20:00:00-03' THEN RAISE EXCEPTION 'token pos total=% date=% (esp 0/06-02)', tok_tot,tok_date; END IF;

  SELECT total_quantity,date INTO brl_tot,brl_date FROM positions
   WHERE asset_id=2 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='assets pledged as collateral - NXCOE25-2') AND last_position_flag;
  IF brl_tot <> 0 OR brl_date <> timestamptz '2025-06-02 20:00:00-03' THEN RAISE EXCEPTION 'BRL colateral total=% date=% (esp 0/06-02)', brl_tot,brl_date; END IF;

  RAISE NOTICE 'OK NXCOE25-2: redemption 06-02 clean0 cf 103.30577904/un (36466.94), token 0, retido 0, sem fantasmas pos-06-02';
END $$;

-- (11) POST-CHECK
SELECT v.date, v.clean_price, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v WHERE v.asset_id=3032 AND v.date::date>='2025-06-01' ORDER BY v.date;
SELECT a.name AS asset, tt.name AS txn, p.date, p.variation, p.total_quantity, p.last_position_flag AS vig
FROM positions p JOIN entities a ON a.id=p.asset_id JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.asset_id IN (3032) OR p.id IN (16802,16803,3227872) ORDER BY p.date,p.id;
SELECT operation, table_name, count(*) FROM histories WHERE created_by='gabriel_sifuentes' AND description LIKE 'NXCOE25-2 %' GROUP BY operation,table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
