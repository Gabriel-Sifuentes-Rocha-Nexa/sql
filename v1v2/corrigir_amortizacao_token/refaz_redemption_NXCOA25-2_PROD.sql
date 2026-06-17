-- ============================================================================
-- refaz_redemption_NXCOA25-2_PROD.sql            (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Token NXCOA25-2 (asset 1685, qty 2377) — tokenizacao direta de 3 cotas GMAC.
-- O V2 bookou a redemption do token ERRADA em 2025-01-17: (a) burst de over-accrual
-- as 10:51 (accrued 1.895 -> 2.443) e (b) resgate fatiado em 3 eventos as 20:00:00/01/02
-- (clean 76.8 -> 27.7 -> 0, cash_flow 23.19+49.13+30.13). O CERTO (= V1, conforme Gabriel):
-- token cai a ZERO em 2025-01-21, distribuindo 241.836,51 (=> 101,74022297/unidade).
--
-- O resgate do SUBJACENTE (3 cotas GMAC, blocks 1702/1703/1704, caixa-in 243.534,80 em
-- 01-17 10:51) e' o evento real e FICA. So' o nivel-token (distribuicao) move p/ 01-21.
-- Spread retido na conta de colateral = 243.534,80 - 241.836,51 = 1.698,29.
--
-- Mecanica (preserva todas as colunas; flags sao recompostas por trigger em UPDATE/DELETE):
--   VALUATIONS 1685:
--     DELETE 260144/260145/260146 (burst 10:51) + 260147/260148 (fracoes 20:00:00/01)
--     UPDATE 188248 (clean 0, vigente): date -> 2025-01-21 20:00, cash_flow -> 101.74022297
--     (mantem 260143 = diaria 01-17 00:00, clean 100.012)
--   POSITIONS (conta 'assets pledged as collateral - NXCOA25-2' + 'token investments'):
--     DELETE blocks 1708 (id 9946) e 1709 (id 9947)  [pernas BRL AMORTIZATION fragmentadas]
--     UPDATE block 1710: id 9949 (BRL) date->01-21, variation -241836.51, total 1698.29
--                        id 9950 (token) date->01-21
--   (mantem blocks 1702/1703/1704 = resgate das cotas)
-- AUDITORIA: cada linha -> histories (update/delete) ANTES da operacao.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — estado atual
SELECT 'VAL antes' AS t, v.id, v.date::text, v.clean_price::text, v.accrued_interest::text, v.cash_flow::text, v.last_valuation_flag AS vig
FROM valuations v WHERE v.asset_id=1685 AND v.date::date='2025-01-17'
UNION ALL
SELECT 'POS antes', p.id, p.date::text, fa.name, tt.name, p.variation::text, p.last_position_flag
FROM positions p
JOIN financial_accounts fa ON fa.id=p.financial_account_id
JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.block_id IN (1708,1709,1710,1702,1703,1704)
ORDER BY 1,3;

-- (1) histories — valuations a APAGAR (burst + fracoes)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'delete',
       'NXCOA25-2 apaga burst over-accrual 10:51 + fracoes de redemption 20:00 (refaz redemption unica em 01-21)'
FROM valuations v WHERE v.id IN (260144,260145,260146,260147,260148);

-- (2) histories — valuation a ATUALIZAR (a vigente clean=0)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'update',
       'NXCOA25-2 move redemption 01-17->01-21 e cash_flow 30.13->101.74022297 (241836.51/2377), igual V1'
FROM valuations v WHERE v.id=188248;

-- (3) histories — positions a APAGAR (BRL AMORTIZATION fragmentadas)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','positions', to_jsonb(p),'delete',
       'NXCOA25-2 apaga pernas BRL AMORTIZATION fragmentadas (blocks 1708/1709) — caixa consolida no block 1710'
FROM positions p WHERE p.id IN (9946,9947);

-- (4) histories — positions a ATUALIZAR (block 1710)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','positions', to_jsonb(p),'update',
       'NXCOA25-2 move redemption block 1710 -> 01-21; BRL distribui 241836.51 (retem 1698.29)'
FROM positions p WHERE p.id IN (9949,9950);

-- (5) DELETE valuations lixo
DELETE FROM valuations WHERE id IN (260144,260145,260146,260147,260148);

-- (6) UPDATE valuation redemption -> data certa + cash_flow certo
UPDATE valuations
SET date = timestamptz '2025-01-21 20:00:00-03', cash_flow = 101.74022297
WHERE id = 188248;

-- (7) DELETE positions lixo (pernas BRL fragmentadas)
DELETE FROM positions WHERE id IN (9946,9947);

-- (8) UPDATE positions block 1710 -> data certa; BRL = distribuicao real
UPDATE positions SET date = timestamptz '2025-01-21 20:00:00-03',
       variation = -241836.51, total_quantity = 1698.29
WHERE id = 9949;                                  -- perna BRL (caixa out)
UPDATE positions SET date = timestamptz '2025-01-21 20:00:00-03'
WHERE id = 9950;                                  -- perna token (baixa -2377)

-- (9) GUARDA
DO $$
DECLARE vdate timestamptz; vclean numeric; vcf numeric; nlixo int;
        tok_tot numeric; tok_date timestamptz; brl_tot numeric; brl_date timestamptz;
BEGIN
  SELECT date, clean_price, cash_flow INTO vdate, vclean, vcf
    FROM valuations WHERE asset_id=1685 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost') AND last_valuation_flag;
  IF vdate <> timestamptz '2025-01-21 20:00:00-03' THEN RAISE EXCEPTION 'vigente date=% (esperado 01-21 20:00)', vdate; END IF;
  IF vclean <> 0 THEN RAISE EXCEPTION 'vigente clean=% (esperado 0)', vclean; END IF;
  IF round(vcf,8) <> 101.74022297 THEN RAISE EXCEPTION 'vigente cash_flow=% (esperado 101.74022297)', vcf; END IF;

  SELECT count(*) INTO nlixo FROM valuations WHERE id IN (260144,260145,260146,260147,260148);
  IF nlixo <> 0 THEN RAISE EXCEPTION 'restaram % valuations lixo', nlixo; END IF;
  SELECT count(*) INTO nlixo FROM positions WHERE id IN (9946,9947);
  IF nlixo <> 0 THEN RAISE EXCEPTION 'restaram % positions lixo', nlixo; END IF;

  -- token vigente: total 0 em 01-21
  SELECT total_quantity, date INTO tok_tot, tok_date FROM positions
   WHERE asset_id=1685 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='token investments') AND last_position_flag;
  IF tok_tot <> 0 OR tok_date <> timestamptz '2025-01-21 20:00:00-03' THEN RAISE EXCEPTION 'token pos total=% date=% (esperado 0 / 01-21)', tok_tot, tok_date; END IF;

  -- caixa BRL na conta de colateral: retido 1698.29 em 01-21
  SELECT total_quantity, date INTO brl_tot, brl_date FROM positions
   WHERE asset_id=2 AND financial_account_id=(SELECT id FROM financial_accounts WHERE name='assets pledged as collateral - NXCOA25-2') AND last_position_flag;
  IF brl_tot <> 1698.29 OR brl_date <> timestamptz '2025-01-21 20:00:00-03' THEN RAISE EXCEPTION 'BRL colateral total=% date=% (esperado 1698.29 / 01-21)', brl_tot, brl_date; END IF;

  RAISE NOTICE 'OK NXCOA25-2: redemption em 01-21, clean 0, cash_flow 101.74022297/un (241836.51 total), token 0, retido 1698.29';
END $$;

-- (10) POST-CHECK
SELECT a.name, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id=1685 AND (v.date::date IN ('2025-01-17','2025-01-21')) ORDER BY v.date;
SELECT fa.name AS conta, tt.name AS txn, p.date, p.variation, p.total_quantity, p.last_position_flag AS vig
FROM positions p JOIN financial_accounts fa ON fa.id=p.financial_account_id JOIN transaction_types tt ON tt.id=p.transaction_type_id
WHERE p.id IN (9949,9950,9924,9927,9930) ORDER BY p.date, p.id;
SELECT operation, table_name, count(*) FROM histories
WHERE created_by='gabriel_sifuentes' AND description LIKE 'NXCOA25-2 %' GROUP BY operation, table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
