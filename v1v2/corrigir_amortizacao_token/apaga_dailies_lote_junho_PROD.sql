-- ============================================================================
-- apaga_dailies_lote_junho_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- LOTE DE JUNHO. A accrual NAO sobrescreve dailies a frente, so preenche buraco.
-- Por isso, antes de bookar os amorts MISSING de junho, apago as dailies que ja
-- accruaram a frente (com clean pre-amort alto), MANTENDO o seed pre-amort do dia
-- do amort. Depois o Gabriel booka os amorts e roda a accrual 1x (preenche os buracos).
-- NAO mexo em positions (o upsert do amort sobrescreve / cria a AMORTIZATION).
--
-- Grupo 06-08 (amort em 2026-06-08): apaga date > '2026-06-08 00:00:00-03'
--   FGTS-04 (CR-FGTS-04-01-SINGLE/NXFGTSI35-1), FGTS-05 (...05.../NXFGTSI35-2),
--   FGTS-10 (...10.../NXFGTSJ35-1), FGTS-12 (...12.../NXFGTSK35-2)
--   -> mantem o seed 06-08 03:00Z (=00:00-03), apaga 06-09/10/11 (3 dailies x 8 = 24)
-- Grupo 06-09 (amort em 2026-06-09): apaga date > '2026-06-09 00:00:00-03'
--   FGTS-07 (...07.../NXFGTSK35-1), FGTS-15 (...15.../NXFGTSB31-1),
--   CONSORTIUMS-29 (CR-CONSORTIUMS-29-01-SINGLE/NXCOF26-3)
--   -> mantem o seed 06-09 03:00Z, apaga 06-10/11 (2 dailies x 6 = 12)
-- Total esperado: 36 valuations (so methodology amortized_cost existe no forward).
--
-- AUDITORIA: cada linha -> `histories` (operation='delete', created_by gabriel_sifuentes) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: o que vai ser apagado por ativo + o seed que fica
SELECT 'APAGAR' AS acao, a.name AS ativo, count(*) AS n,
       min(v.date) AS menor, max(v.date) AS maior,
       count(*) FILTER (WHERE v.cash_flow<>0) AS eventos
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE (a.name IN ('CR-FGTS-04-01-SINGLE','NXFGTSI35-1','CR-FGTS-05-01-SINGLE','NXFGTSI35-2',
                  'CR-FGTS-10-01-SINGLE','NXFGTSJ35-1','CR-FGTS-12-01-SINGLE','NXFGTSK35-2')
       AND v.date > timestamptz '2026-06-08 00:00:00-03')
   OR (a.name IN ('CR-FGTS-07-01-SINGLE','NXFGTSK35-1','CR-FGTS-15-01-SINGLE','NXFGTSB31-1',
                  'CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3')
       AND v.date > timestamptz '2026-06-09 00:00:00-03')
GROUP BY a.name ORDER BY a.name;

-- (1A) histories — grupo 06-08
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'lote junho: apaga dailies > 2026-06-08 00:00 (forward pre-amort) p/ rebookar amort 06-08 e re-accruar'
FROM valuations v
WHERE v.asset_id IN (SELECT id FROM entities WHERE name IN
       ('CR-FGTS-04-01-SINGLE','NXFGTSI35-1','CR-FGTS-05-01-SINGLE','NXFGTSI35-2',
        'CR-FGTS-10-01-SINGLE','NXFGTSJ35-1','CR-FGTS-12-01-SINGLE','NXFGTSK35-2'))
  AND v.date > timestamptz '2026-06-08 00:00:00-03';

-- (1B) histories — grupo 06-09
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'lote junho: apaga dailies > 2026-06-09 00:00 (forward pre-amort) p/ rebookar amort 06-09 e re-accruar'
FROM valuations v
WHERE v.asset_id IN (SELECT id FROM entities WHERE name IN
       ('CR-FGTS-07-01-SINGLE','NXFGTSK35-1','CR-FGTS-15-01-SINGLE','NXFGTSB31-1',
        'CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3'))
  AND v.date > timestamptz '2026-06-09 00:00:00-03';

-- (2A) DELETE — grupo 06-08
DELETE FROM valuations
WHERE asset_id IN (SELECT id FROM entities WHERE name IN
       ('CR-FGTS-04-01-SINGLE','NXFGTSI35-1','CR-FGTS-05-01-SINGLE','NXFGTSI35-2',
        'CR-FGTS-10-01-SINGLE','NXFGTSJ35-1','CR-FGTS-12-01-SINGLE','NXFGTSK35-2'))
  AND date > timestamptz '2026-06-08 00:00:00-03';

-- (2B) DELETE — grupo 06-09
DELETE FROM valuations
WHERE asset_id IN (SELECT id FROM entities WHERE name IN
       ('CR-FGTS-07-01-SINGLE','NXFGTSK35-1','CR-FGTS-15-01-SINGLE','NXFGTSB31-1',
        'CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3'))
  AND date > timestamptz '2026-06-09 00:00:00-03';

-- (3) GUARDA: nada sobrou alem do seed; cada ativo termina no seed pre-amort esperado
DO $$
DECLARE n_a int; n_b int; bad int;
BEGIN
  -- grupo 06-08: nenhuma linha > 06-08 00:00; 8 ativos terminam exatamente em 06-08 03:00Z
  SELECT count(*) INTO n_a FROM valuations
   WHERE asset_id IN (SELECT id FROM entities WHERE name IN
        ('CR-FGTS-04-01-SINGLE','NXFGTSI35-1','CR-FGTS-05-01-SINGLE','NXFGTSI35-2',
         'CR-FGTS-10-01-SINGLE','NXFGTSJ35-1','CR-FGTS-12-01-SINGLE','NXFGTSK35-2'))
     AND date > timestamptz '2026-06-08 00:00:00-03';
  IF n_a <> 0 THEN RAISE EXCEPTION 'grupo 06-08: ainda ha % linhas > 06-08 00:00', n_a; END IF;

  -- grupo 06-09: nenhuma linha > 06-09 00:00
  SELECT count(*) INTO n_b FROM valuations
   WHERE asset_id IN (SELECT id FROM entities WHERE name IN
        ('CR-FGTS-07-01-SINGLE','NXFGTSK35-1','CR-FGTS-15-01-SINGLE','NXFGTSB31-1',
         'CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3'))
     AND date > timestamptz '2026-06-09 00:00:00-03';
  IF n_b <> 0 THEN RAISE EXCEPTION 'grupo 06-09: ainda ha % linhas > 06-09 00:00', n_b; END IF;

  -- seed pre-amort presente em cada ativo (8 ativos @ 06-08 03:00Z, 6 ativos @ 06-09 03:00Z)
  SELECT count(*) INTO bad FROM entities e WHERE e.name IN
        ('CR-FGTS-04-01-SINGLE','NXFGTSI35-1','CR-FGTS-05-01-SINGLE','NXFGTSI35-2',
         'CR-FGTS-10-01-SINGLE','NXFGTSJ35-1','CR-FGTS-12-01-SINGLE','NXFGTSK35-2')
     AND NOT EXISTS (SELECT 1 FROM valuations v WHERE v.asset_id=e.id AND v.date=timestamptz '2026-06-08 00:00:00-03');
  IF bad <> 0 THEN RAISE EXCEPTION 'grupo 06-08: % ativos sem seed 06-08 00:00', bad; END IF;

  SELECT count(*) INTO bad FROM entities e WHERE e.name IN
        ('CR-FGTS-07-01-SINGLE','NXFGTSK35-1','CR-FGTS-15-01-SINGLE','NXFGTSB31-1',
         'CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3')
     AND NOT EXISTS (SELECT 1 FROM valuations v WHERE v.asset_id=e.id AND v.date=timestamptz '2026-06-09 00:00:00-03');
  IF bad <> 0 THEN RAISE EXCEPTION 'grupo 06-09: % ativos sem seed 06-09 00:00', bad; END IF;

  RAISE NOTICE 'OK: grupo 06-08 e 06-09 limpos, seeds pre-amort presentes';
END $$;

-- (4) POST-CHECK: estado final (max date deve ser o seed, vigente = seed)
SELECT a.name AS ativo, count(*) AS n, max(v.date) AS maior,
       count(*) FILTER (WHERE v.last_valuation_flag) AS vigentes
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE a.name IN ('CR-FGTS-04-01-SINGLE','NXFGTSI35-1','CR-FGTS-05-01-SINGLE','NXFGTSI35-2',
                 'CR-FGTS-10-01-SINGLE','NXFGTSJ35-1','CR-FGTS-12-01-SINGLE','NXFGTSK35-2',
                 'CR-FGTS-07-01-SINGLE','NXFGTSK35-1','CR-FGTS-15-01-SINGLE','NXFGTSB31-1',
                 'CR-CONSORTIUMS-29-01-SINGLE','NXCOF26-3')
GROUP BY a.name ORDER BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
