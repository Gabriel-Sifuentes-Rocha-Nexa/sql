-- ============================================================================
-- apaga_pos_amort_1208_FGTS01_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- Apaga SOMENTE a position de AMORTIZATION de 2025-12-08 da mae CR-FGTS-01 (stale,
-- sobrou da carga antiga) p/ re-rodar a amortizacao do dia. NAO toca em nenhuma
-- outra position (nem outras datas, nem outros tipos).
-- Linha antiga -> `histories` (operation='delete') ANTES do DELETE. IDs por nome.
-- DRY-RUN: BEGIN..ROLLBACK; trocar por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — exatamente a(s) linha(s)-alvo
SELECT p.id, p.date, tt.name AS ttype, h.name AS holder, p.variation, p.total_quantity, p.financial_account_id
FROM positions p
JOIN transaction_types tt ON tt.id = p.transaction_type_id
JOIN entities h ON h.id = p.holder_id
WHERE p.holder_id = (SELECT id FROM entities WHERE name='CR-FGTS-01')
  AND p.date::date = '2025-12-08'
  AND p.transaction_type_id = (SELECT id FROM transaction_types WHERE name='AMORTIZATION');

-- (1) GUARDA: tem que ser exatamente 1 linha
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM positions p
  WHERE p.holder_id = (SELECT id FROM entities WHERE name='CR-FGTS-01')
    AND p.date::date = '2025-12-08'
    AND p.transaction_type_id = (SELECT id FROM transaction_types WHERE name='AMORTIZATION');
  IF n <> 1 THEN RAISE EXCEPTION 'esperava 1 position de AMORTIZATION em 12-08 da mae, achei %', n; END IF;
END $$;

-- (2) histories (linha antiga) antes do DELETE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'positions', to_jsonb(p), 'delete',
       'apaga position de AMORTIZATION 2025-12-08 da mae CR-FGTS-01 (stale) p/ re-rodar a amortizacao do dia'
FROM positions p
WHERE p.holder_id = (SELECT id FROM entities WHERE name='CR-FGTS-01')
  AND p.date::date = '2025-12-08'
  AND p.transaction_type_id = (SELECT id FROM transaction_types WHERE name='AMORTIZATION');

-- (3) DELETE
DELETE FROM positions p
WHERE p.holder_id = (SELECT id FROM entities WHERE name='CR-FGTS-01')
  AND p.date::date = '2025-12-08'
  AND p.transaction_type_id = (SELECT id FROM transaction_types WHERE name='AMORTIZATION');

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
