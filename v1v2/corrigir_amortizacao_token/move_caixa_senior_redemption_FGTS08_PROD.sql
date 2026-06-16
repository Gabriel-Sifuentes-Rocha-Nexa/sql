-- ============================================================================
-- move_caixa_senior_redemption_FGTS08_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Mover a perna de CAIXA do redemption do senior (id 7808162, BRL/REDEMPTION/conta 10/
--   holder 1058783) de 2026-04-17 16:00:00 -> 16:00:01, liberando o slot unique
--   (date,holder,asset,fin_acct)=(16:00:00,1058783,2,10) p/ o redemption do MEZZ entrar.
-- As outras pernas do senior (colateral/token) sao de assets diferentes, nao precisam mexer.
-- AUDITORIA: linha antiga -> histories (update) ANTES. trigger recompoe total_quantity/flag.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW
SELECT id, date, variation, total_quantity FROM positions WHERE id=7808162;

-- guard: 16:00:01 livre
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM positions
   WHERE date=timestamptz '2026-04-17 16:00:01+00' AND holder_id=1058783 AND asset_id=2 AND financial_account_id=10;
  IF n<>0 THEN RAISE EXCEPTION '16:00:01 ja ocupado (%)', n; END IF;
END $$;

-- (1) histories
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','positions', to_jsonb(p),'update',
       'FGTS-08: move caixa redemption senior 16:00:00 -> 16:00:01 (libera slot p/ mezz)'
FROM positions p WHERE p.id=7808162;

-- (2) UPDATE date
UPDATE positions SET date=timestamptz '2026-04-17 16:00:01+00' WHERE id=7808162 AND date=timestamptz '2026-04-17 16:00:00+00';

-- (3) GUARDA: movido; 16:00:00 livre
DO $$
DECLARE d timestamptz; n int;
BEGIN
  SELECT date INTO d FROM positions WHERE id=7808162;
  IF d<>timestamptz '2026-04-17 16:00:01+00' THEN RAISE EXCEPTION 'nao moveu (date=%)', d; END IF;
  SELECT count(*) INTO n FROM positions
   WHERE date=timestamptz '2026-04-17 16:00:00+00' AND holder_id=1058783 AND asset_id=2 AND financial_account_id=10;
  IF n<>0 THEN RAISE EXCEPTION '16:00:00 ainda ocupado (%)', n; END IF;
  RAISE NOTICE 'OK: caixa senior em 16:00:01; slot 16:00:00 livre p/ mezz';
END $$;

-- (4) POST-CHECK
SELECT id, date, variation, total_quantity, last_position_flag FROM positions WHERE id=7808162;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
