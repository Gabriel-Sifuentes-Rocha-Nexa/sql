-- ============================================================================
-- apaga_amort_1208_FGTS01_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- A amortizacao de 2025-12-08 saiu ERRADA (accrued inflou de 6.855 -> 14.484, dirty
-- subiu num evento de amortizacao). Apaga p/ o usuario re-rodar:
--   * valuations da SERIE CR-FGTS-01-01-SINGLE e do TOKEN NXFGTSJ34-1 com
--     date > 12-08 00:00 (= o evento de amort 12-08 09:00 + todo o forward ate 06-11).
--     MANTEM o pre-amort 12-08 00:00 (seed) e tudo antes (inclui o amort de 11-14 ja correto).
--   * position de AMORTIZATION (type 1) de 12-08 da MAE CR-FGTS-01.
--
-- AUDITORIA: cada linha apagada -> `histories` (operation='delete', created_by gabriel_sifuentes) ANTES do DELETE.
-- IDs por NOME. DRY-RUN: BEGIN..ROLLBACK; trocar por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — o que sera apagado
SELECT a.name AS ativo, count(*) AS val_a_apagar, min(v.date) AS menor, max(v.date) AS maior
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1')
  AND v.date > timestamptz '2025-12-08 00:00:00-03'
GROUP BY a.name;

SELECT 'pos_amort_mae_1208' AS alvo, count(*) AS pos_a_apagar
FROM positions
WHERE holder_id = (SELECT id FROM entities WHERE name='CR-FGTS-01')
  AND date::date = '2025-12-08' AND transaction_type_id = (SELECT id FROM transaction_types WHERE name='AMORTIZATION');

-- (1) histories das VALUATIONS (antes de apagar)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'apaga valuations da amortizacao 2025-12-08 (serie CR-FGTS-01-01-SINGLE + token NXFGTSJ34-1; upsert re-amortizou o clean) p/ re-rodar'
FROM valuations v
WHERE v.asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1'))
  AND v.date > timestamptz '2025-12-08 00:00:00-03';

-- (2) DELETE das VALUATIONS
DELETE FROM valuations
WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1'))
  AND date > timestamptz '2025-12-08 00:00:00-03';

-- (3) histories da POSITION (antes de apagar)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'positions', to_jsonb(p), 'delete',
       'apaga position de AMORTIZATION 2025-12-08 da mae CR-FGTS-01 (amortizacao errada) p/ re-rodar'
FROM positions p
WHERE p.holder_id = (SELECT id FROM entities WHERE name='CR-FGTS-01')
  AND p.date::date = '2025-12-08' AND p.transaction_type_id = (SELECT id FROM transaction_types WHERE name='AMORTIZATION');

-- (4) DELETE da POSITION
DELETE FROM positions
WHERE holder_id = (SELECT id FROM entities WHERE name='CR-FGTS-01')
  AND date::date = '2025-12-08' AND transaction_type_id = (SELECT id FROM transaction_types WHERE name='AMORTIZATION');

-- (5) GUARDA: nada apos o seed 12-08 00:00; serie/token nao vazios; position fora
DO $$
DECLARE rem_val int; rem_pos int; keep_serie int; keep_token int; ms timestamptz; mt timestamptz;
BEGIN
  SELECT count(*) INTO rem_val FROM valuations
    WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1'))
      AND date > timestamptz '2025-12-08 00:00:00-03';
  IF rem_val <> 0 THEN RAISE EXCEPTION 'ainda restam % valuations apos o seed 12-08', rem_val; END IF;

  SELECT count(*) INTO rem_pos FROM positions
    WHERE holder_id=(SELECT id FROM entities WHERE name='CR-FGTS-01')
      AND date::date='2025-12-08' AND transaction_type_id=(SELECT id FROM transaction_types WHERE name='AMORTIZATION');
  IF rem_pos <> 0 THEN RAISE EXCEPTION 'ainda resta % position de amort 12-08', rem_pos; END IF;

  SELECT count(*), max(date) INTO keep_serie, ms FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='CR-FGTS-01-01-SINGLE');
  SELECT count(*), max(date) INTO keep_token, mt FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='NXFGTSJ34-1');
  IF keep_serie = 0 OR keep_token = 0 THEN RAISE EXCEPTION 'serie/token ficaram vazios'; END IF;
  IF ms <> timestamptz '2025-12-08 00:00:00-03' OR mt <> timestamptz '2025-12-08 00:00:00-03'
     THEN RAISE EXCEPTION 'max(date) != seed 12-08 00:00 (serie=%, token=%)', ms, mt; END IF;
  RAISE NOTICE 'OK: serie/token terminam no pre-amort 12-08 00:00 (serie=% linhas, token=%); position de amort removida', keep_serie, keep_token;
END $$;

-- (6) POST-CHECK
SELECT a.name AS ativo, count(*) AS n, max(v.date) AS maior,
       count(*) FILTER (WHERE v.last_valuation_flag) AS flags_true
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1') GROUP BY a.name;

SELECT operation, table_name, count(*) AS gravadas_em_histories
FROM histories
WHERE created_by='gabriel_sifuentes' AND operation='delete' AND description LIKE 'apaga %2025-12-08%'
GROUP BY operation, table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
