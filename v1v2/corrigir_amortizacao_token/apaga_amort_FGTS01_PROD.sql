-- ============================================================================
-- apaga_amort_FGTS01_PROD.sql        (PROD via tunel :5003 — aponte o DATABASE_URL)
-- ----------------------------------------------------------------------------
-- Replica em PROD a delecao feita no LOCAL p/ re-rodar a amortizacao de 2025-11-14:
--   * valuations da SERIE CR-FGTS-01-01-SINGLE e do TOKEN NXFGTSJ34-1 com
--     date > 11-14 00:00  (= o evento de amort 11-14 09:00 + tudo de 11-15 em diante).
--     MANTEM o seed pre-amort 11-14 00:00 e os anteriores.
--   * position de AMORTIZATION (type 1) de 11-14 da MAE CR-FGTS-01.
--
-- AUDITORIA OBRIGATORIA (PROD): cada linha apagada e' gravada em `histories`
--   (old_value = to_jsonb, operation = 'delete', created_by = 'gabriel_sifuentes') ANTES do DELETE.
--
-- IDs resolvidos por NOME (nao confiar nos ids do LOCAL).
-- DRY-RUN: roda em BEGIN ... ROLLBACK. Trocar ROLLBACK por COMMIT p/ aplicar.
--
-- ATENCAO: como apaga TUDO depois do seed, isso remove tb as valuations de 11-15+ da SERIE
--   (incluindo os eventos SIM que ja corrigi em prod: 12-08, 01-09, 02-11, 03-05, 04-07, 05-07).
--   Elas serao re-geradas quando voce re-rodar a amortizacao pra frente. Tudo fica em histories.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — o que sera apagado (nao altera nada)
SELECT a.name AS ativo, count(*) AS val_a_apagar, min(v.date) AS menor, max(v.date) AS maior
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1')
  AND v.date > timestamptz '2025-11-14 00:00:00-03'
GROUP BY a.name;

SELECT 'pos_amort_mae' AS alvo, count(*) AS pos_a_apagar
FROM positions
WHERE holder_id = (SELECT id FROM entities WHERE name='CR-FGTS-01')
  AND date::date = '2025-11-14' AND transaction_type_id = 1;

-- (1) histories das VALUATIONS (antes de apagar)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'apaga valuations da amortizacao 2025-11-14 em diante (serie CR-FGTS-01-01-SINGLE + token NXFGTSJ34-1) p/ re-rodar a correcao do dia'
FROM valuations v
WHERE v.asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1'))
  AND v.date > timestamptz '2025-11-14 00:00:00-03';

-- (2) DELETE das VALUATIONS
DELETE FROM valuations
WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1'))
  AND date > timestamptz '2025-11-14 00:00:00-03';

-- (3) histories da POSITION (antes de apagar)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'positions', to_jsonb(p), 'delete',
       'apaga position de AMORTIZATION 2025-11-14 da mae CR-FGTS-01 p/ re-rodar a correcao do dia'
FROM positions p
WHERE p.holder_id = (SELECT id FROM entities WHERE name='CR-FGTS-01')
  AND p.date::date = '2025-11-14' AND p.transaction_type_id = 1;

-- (4) DELETE da POSITION
DELETE FROM positions
WHERE holder_id = (SELECT id FROM entities WHERE name='CR-FGTS-01')
  AND date::date = '2025-11-14' AND transaction_type_id = 1;

-- (5) GUARDA: nada pode restar apos o seed; serie/token nao podem ficar vazios
DO $$
DECLARE rem_val int; rem_pos int; keep_serie int; keep_token int;
BEGIN
  SELECT count(*) INTO rem_val FROM valuations
    WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1'))
      AND date > timestamptz '2025-11-14 00:00:00-03';
  IF rem_val <> 0 THEN RAISE EXCEPTION 'ainda restam % valuations apos o seed', rem_val; END IF;

  SELECT count(*) INTO rem_pos FROM positions
    WHERE holder_id=(SELECT id FROM entities WHERE name='CR-FGTS-01')
      AND date::date='2025-11-14' AND transaction_type_id=1;
  IF rem_pos <> 0 THEN RAISE EXCEPTION 'ainda resta % position de amort', rem_pos; END IF;

  SELECT count(*) INTO keep_serie FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='CR-FGTS-01-01-SINGLE');
  SELECT count(*) INTO keep_token FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='NXFGTSJ34-1');
  IF keep_serie = 0 OR keep_token = 0 THEN RAISE EXCEPTION 'serie/token ficaram vazios (serie=%, token=%)', keep_serie, keep_token; END IF;

  RAISE NOTICE 'OK: serie mantem % linhas, token mantem %; nada apos o seed; position de amort removida', keep_serie, keep_token;
END $$;

-- (6) POST-CHECK: estado final + quantas linhas foram para histories nesta transacao
SELECT a.name AS ativo, count(*) AS n, min(v.date) AS menor, max(v.date) AS maior,
       count(*) FILTER (WHERE v.last_valuation_flag) AS flags_true
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1') GROUP BY a.name;

SELECT operation, table_name, count(*) AS gravadas_em_histories
FROM histories
WHERE created_by='gabriel_sifuentes' AND operation='delete' AND description LIKE 'apaga %2025-11-14%'
GROUP BY operation, table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar de verdade.
