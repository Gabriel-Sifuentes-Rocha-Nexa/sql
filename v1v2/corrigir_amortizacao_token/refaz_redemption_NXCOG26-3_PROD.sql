-- ============================================================================
-- refaz_redemption_NXCOG26-3_PROD.sql            (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Token NXCOG26-3 (asset 3256, qty 876) — tokenizacao direta da cota CANOPUS.
-- O V2 bookou a redemption ERRADA em 2025-11-06: burst de over-accrual as 15:04 e
-- 19:59:59.999 (accrued 8.715 -> 20.839) + resgate as 20:00 com o valor CHEIO do
-- subjacente (120,91385845/un = 105.920,54). O CERTO (= V1, conforme Gabriel): token
-- cai a ZERO em 2025-11-10, distribuindo 105.030,24 (=> 119,89753425/unidade).
--
-- O resgate do SUBJACENTE (cota CANOPUS, block 2604217675483861109, caixa-in 105.920,54
-- em 11-06 15:04) FICA. So' o nivel-token (distribuicao) move p/ 11-10.
-- Spread retido na conta de colateral = 105.920,54 - 105.030,24 = 890,30.
--
-- Mecanica (UPDATE move data/valor; DELETE so' do burst; flags por trigger):
--   VALUATIONS 3256:
--     DELETE 5956654 (15:04) + 5961251 (19:59:59.999)  [burst over-accrual]
--     UPDATE 5961252 (clean 0, vigente): date -> 2025-11-10 20:00, cash_flow -> 119.89753425
--     (mantem 5956653 = diaria 11-06 00:00, clean 100.075)
--   POSITIONS block 2604217675915715393:
--     id 2417649 (BRL): date->11-10, variation -105030.24, total 890.30
--     id 2417650 (token -876): date->11-10
--   (mantem block 2604217675483861109 = resgate da cota)
-- AUDITORIA: cada linha -> histories (update/delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW
SELECT 'VAL antes' AS t, v.id, v.date::text, v.clean_price::text, v.accrued_interest::text, v.cash_flow::text, v.last_valuation_flag AS vig
FROM valuations v WHERE v.asset_id=3256 AND v.date::date='2025-11-06'
UNION ALL
SELECT 'POS antes', p.id, p.date::text, fa.name, tt.name, p.variation::text, p.last_position_flag
FROM positions p JOIN financial_accounts fa ON fa.id=p.financial_account_id JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.block_id IN (2604217675915715393, 2604217675483861109)
ORDER BY 1,3;

-- (1) histories — valuations a APAGAR (burst)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'delete',
       'NXCOG26-3 apaga burst over-accrual 11-06 15:04 e 19:59:59.999 (refaz redemption unica em 11-10)'
FROM valuations v WHERE v.id IN (5956654,5961251);

-- (2) histories — valuation a ATUALIZAR
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'update',
       'NXCOG26-3 move redemption 11-06->11-10 e cash_flow 120.91->119.89753425 (105030.24/876), igual V1'
FROM valuations v WHERE v.id=5961252;

-- (3) histories — positions a ATUALIZAR (block ...393)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','positions', to_jsonb(p),'update',
       'NXCOG26-3 move redemption block 2604217675915715393 -> 11-10; BRL distribui 105030.24 (retem 890.30)'
FROM positions p WHERE p.id IN (2417649,2417650);

-- (4) DELETE valuations burst
DELETE FROM valuations WHERE id IN (5956654,5961251);

-- (5) UPDATE valuation redemption -> data + cash_flow certos
UPDATE valuations
SET date = timestamptz '2025-11-10 20:00:00-03', cash_flow = 119.89753425
WHERE id = 5961252;

-- (6) UPDATE positions block ...393 -> data certa; BRL = distribuicao real
UPDATE positions SET date = timestamptz '2025-11-10 20:00:00-03',
       variation = -105030.24, total_quantity = 890.30
WHERE id = 2417649;                               -- perna BRL (caixa out)
UPDATE positions SET date = timestamptz '2025-11-10 20:00:00-03'
WHERE id = 2417650;                               -- perna token (baixa -876)

-- (7) GUARDA
DO $$
DECLARE vdate timestamptz; vclean numeric; vcf numeric; nlixo int;
        tok_tot numeric; tok_date timestamptz; brl_tot numeric; brl_date timestamptz;
BEGIN
  SELECT date, clean_price, cash_flow INTO vdate, vclean, vcf
    FROM valuations WHERE asset_id=3256 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost') AND last_valuation_flag;
  IF vdate <> timestamptz '2025-11-10 20:00:00-03' THEN RAISE EXCEPTION 'vigente date=% (esperado 11-10 20:00)', vdate; END IF;
  IF vclean <> 0 THEN RAISE EXCEPTION 'vigente clean=% (esperado 0)', vclean; END IF;
  IF round(vcf,8) <> 119.89753425 THEN RAISE EXCEPTION 'vigente cash_flow=% (esperado 119.89753425)', vcf; END IF;

  SELECT count(*) INTO nlixo FROM valuations WHERE id IN (5956654,5961251);
  IF nlixo <> 0 THEN RAISE EXCEPTION 'restaram % valuations burst', nlixo; END IF;

  SELECT total_quantity, date INTO tok_tot, tok_date FROM positions
   WHERE asset_id=3256 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='token investments') AND last_position_flag;
  IF tok_tot <> 0 OR tok_date <> timestamptz '2025-11-10 20:00:00-03' THEN RAISE EXCEPTION 'token pos total=% date=% (esperado 0 / 11-10)', tok_tot, tok_date; END IF;

  SELECT total_quantity, date INTO brl_tot, brl_date FROM positions
   WHERE asset_id=2 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='assets pledged as collateral - NXCOG26-3') AND last_position_flag;
  IF brl_tot <> 890.30 OR brl_date <> timestamptz '2025-11-10 20:00:00-03' THEN RAISE EXCEPTION 'BRL colateral total=% date=% (esperado 890.30 / 11-10)', brl_tot, brl_date; END IF;

  RAISE NOTICE 'OK NXCOG26-3: redemption em 11-10, clean 0, cash_flow 119.89753425/un (105030.24 total), token 0, retido 890.30';
END $$;

-- (8) POST-CHECK
SELECT a.name, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id=3256 AND (v.date::date IN ('2025-11-06','2025-11-10')) ORDER BY v.date;
SELECT fa.name AS conta, tt.name AS txn, p.date, p.variation, p.total_quantity, p.last_position_flag AS vig
FROM positions p JOIN financial_accounts fa ON fa.id=p.financial_account_id JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.id IN (2417649,2417650,2417577,2417578) ORDER BY p.date, p.id;
SELECT operation, table_name, count(*) FROM histories
WHERE created_by='gabriel_sifuentes' AND description LIKE 'NXCOG26-3 %' GROUP BY operation, table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
