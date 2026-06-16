-- ============================================================================
-- corrige_positions_amort_FGTS08_SR_MZ_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- A amort 03-16 lancou caixa SO' do principal (e SO' no mezz):
--   - MEZZ: position BRL/AMORTIZATION (id 7808148) variation -240000 = 7,5*32000 (so' principal)
--   - SENIOR: NAO criou a perna de caixa (faltando totalmente).
-- "Valor certo pago" = principal + juros (= delta V1 por unidade) x qty emissao:
--   - SENIOR: 13.46473125 * 348000 = 4.685.726,475
--   - MEZZ:   14.03100134 * 32000  =   448.992,04288
-- Perna de caixa = BRL (asset 2) / fin_acct 10 (cash and equivalents) / AMORTIZATION (tt 1) /
--   holder CR-FGTS-08 (1058783) / lot 0. total_quantity e last_position_flag sao mantidos por
--   trigger (recalcula o saldo corrido do grupo). unique=(date,holder,asset,fin_acct) -> senior
--   entra em 12:00:01 (mezz fica 12:00:00).
-- AUDITORIA: mezz (UPDATE) -> histories ANTES. Senior e' INSERT (linha nova, sem old_value;
--   operations_enum so' tem delete/update).
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: estado atual (mezz existe principal-only; senior ausente) + saldo vigente do caixa
SELECT p.id, p.date, p.variation, p.total_quantity, p.last_position_flag vig, p.block_id
FROM positions p
WHERE p.holder_id=1058783 AND p.asset_id=2 AND p.financial_account_id=10 AND p.transaction_type_id=1
ORDER BY p.date;

-- (1) histories — mezz (UPDATE) old_value ANTES
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'positions', to_jsonb(p), 'update',
       'FGTS-08 mezz amort: caixa de -240000 (so principal) -> -448992.04288 (principal+juros = valor pago)'
FROM positions p WHERE p.id=7808148;

-- (2) UPDATE mezz: variation -> total pago (principal + juros)
UPDATE positions SET variation = -448992.04288 WHERE id=7808148 AND variation = -240000.000000;

-- (3) INSERT senior: perna de caixa que faltava (12:00:01 p/ nao colidir com o mezz 12:00:00)
INSERT INTO positions (date, holder_id, asset_id, lot_id, financial_account_id, transaction_type_id,
                       variation, total_quantity, block_id, doc_id, last_position_flag)
VALUES (timestamptz '2026-03-15 12:00:01+00', 1058783, 2, 0, 10, 1,
        -4685726.475, 0, (SELECT max(block_id)+1 FROM positions),
        (SELECT max(block_id)+1 FROM positions), false);

-- (4) GUARDA: mezz corrigido, senior presente
DO $$
DECLARE mz numeric; sr int; srvar numeric;
BEGIN
  SELECT variation INTO mz FROM positions WHERE id=7808148;
  IF mz <> -448992.04288 THEN RAISE EXCEPTION 'mezz variation=% (esperado -448992.04288)', mz; END IF;
  SELECT count(*), max(variation) INTO sr, srvar FROM positions
   WHERE holder_id=1058783 AND asset_id=2 AND financial_account_id=10 AND transaction_type_id=1
     AND date = timestamptz '2026-03-15 12:00:01+00';
  IF sr <> 1 THEN RAISE EXCEPTION 'esperado 1 perna senior 12:00:01, achei %', sr; END IF;
  IF srvar <> -4685726.475 THEN RAISE EXCEPTION 'senior variation=% (esperado -4685726.475)', srvar; END IF;
  RAISE NOTICE 'OK: mezz=-448992.04288 ; senior=-4685726.475 inserido';
END $$;

-- (5) POST-CHECK: as pernas de caixa AMORTIZATION do SPV + saldo vigente recalculado
SELECT p.id, p.date, p.variation, p.total_quantity, p.last_position_flag vig
FROM positions p
WHERE p.holder_id=1058783 AND p.asset_id=2 AND p.financial_account_id=10 AND p.transaction_type_id=1
ORDER BY p.date;
SELECT 'saldo caixa SPV vigente' AS info, p.total_quantity
FROM positions p
WHERE p.holder_id=1058783 AND p.asset_id=2 AND p.financial_account_id=10 AND p.last_position_flag=TRUE;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
