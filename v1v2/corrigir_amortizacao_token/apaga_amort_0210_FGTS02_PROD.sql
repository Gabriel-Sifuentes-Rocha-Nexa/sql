-- ============================================================================
-- apaga_amort_0210_FGTS02_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- O usuario rodou o amort do FGTS-02 pro dia ERRADO (2026-02-10; o correto e' 02-11).
-- Apaga so a transacao de 02-10 do FGTS-02 (serie + token + position da mae),
-- MANTENDO a daily 02-10 00:00 e a daily 02-11 00:00 (pre-amort p/ re-rodar no dia certo).
-- NAO toca FGTS-03 nem FGTS-06 (o amort de 02-10 deles e' legitimo e ja validado).
--
-- Alvo:
--   * VALUATIONS: CR-FGTS-02-01-SINGLE + NXFGTSH35-1, date::date='2026-02-10' AND cash_flow<>0 (o evento 09:00)
--   * POSITIONS: mae CR-FGTS-02, date::date='2026-02-10', AMORTIZATION (id 7799144, var -35156.02)
--
-- AUDITORIA: cada linha -> `histories` (operation='delete', created_by gabriel_sifuentes) ANTES do DELETE.
-- DRY-RUN: BEGIN..ROLLBACK; trocar por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — rows de 02-10 do FGTS-02 (daily fica; evento sai) + a position
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest, v.cash_flow,
       CASE WHEN v.cash_flow<>0 THEN 'APAGA (evento)' ELSE 'mantem (daily)' END AS acao
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE a.name IN ('CR-FGTS-02-01-SINGLE','NXFGTSH35-1') AND v.date::date='2026-02-10'
ORDER BY a.name, v.date;

SELECT h.name AS mae, pp.id, pp.date, pp.variation
FROM positions pp JOIN entities h ON h.id=pp.holder_id
WHERE h.name='CR-FGTS-02' AND pp.date::date='2026-02-10'
  AND pp.transaction_type_id=(SELECT id FROM transaction_types WHERE name='AMORTIZATION');

-- (1) histories da VALUATION (evento 02-10) antes do DELETE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'apaga evento amort 2026-02-10 do FGTS-02 (rodado no dia errado; correto e 02-11) serie+token; daily mantida'
FROM valuations v
WHERE v.asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-02-01-SINGLE','NXFGTSH35-1'))
  AND v.date::date='2026-02-10' AND v.cash_flow <> 0;

-- (2) DELETE da VALUATION
DELETE FROM valuations
WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-02-01-SINGLE','NXFGTSH35-1'))
  AND date::date='2026-02-10' AND cash_flow <> 0;

-- (3) histories da POSITION (02-10) antes do DELETE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'positions', to_jsonb(pp), 'delete',
       'apaga position AMORTIZATION 2026-02-10 da mae CR-FGTS-02 (amort rodado no dia errado) p/ re-rodar em 02-11'
FROM positions pp
WHERE pp.holder_id=(SELECT id FROM entities WHERE name='CR-FGTS-02')
  AND pp.date::date='2026-02-10' AND pp.transaction_type_id=(SELECT id FROM transaction_types WHERE name='AMORTIZATION');

-- (4) DELETE da POSITION
DELETE FROM positions
WHERE holder_id=(SELECT id FROM entities WHERE name='CR-FGTS-02')
  AND date::date='2026-02-10' AND transaction_type_id=(SELECT id FROM transaction_types WHERE name='AMORTIZATION');

-- (5) GUARDA: sem evento 02-10 nem position amort 02-10 no FGTS-02; serie=token; termina no pre-amort 02-11 00:00
DO $$
DECLARE rem_ev int; rem_pos int; ns int; nt int; ms timestamptz; mt timestamptz;
BEGIN
  SELECT count(*) INTO rem_ev FROM valuations
   WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-02-01-SINGLE','NXFGTSH35-1'))
     AND date::date='2026-02-10' AND cash_flow <> 0;
  IF rem_ev <> 0 THEN RAISE EXCEPTION 'ainda resta % evento 02-10 no FGTS-02', rem_ev; END IF;

  SELECT count(*) INTO rem_pos FROM positions
   WHERE holder_id=(SELECT id FROM entities WHERE name='CR-FGTS-02')
     AND date::date='2026-02-10' AND transaction_type_id=(SELECT id FROM transaction_types WHERE name='AMORTIZATION');
  IF rem_pos <> 0 THEN RAISE EXCEPTION 'ainda resta % position amort 02-10 no FGTS-02', rem_pos; END IF;

  SELECT count(*), max(date) INTO ns, ms FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='CR-FGTS-02-01-SINGLE');
  SELECT count(*), max(date) INTO nt, mt FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='NXFGTSH35-1');
  IF ns <> nt THEN RAISE EXCEPTION 'serie (%) e token (%) dessincronizados', ns, nt; END IF;
  IF ms <> timestamptz '2026-02-11 00:00:00-03' OR mt <> timestamptz '2026-02-11 00:00:00-03'
     THEN RAISE EXCEPTION 'max(date) != pre-amort 02-11 00:00 (serie=%, token=%)', ms, mt; END IF;
  RAISE NOTICE 'OK: FGTS-02 sem amort 02-10, serie=token (% linhas), terminando no pre-amort 02-11 00:00', ns;
END $$;

-- (6) POST-CHECK: rows 02-10/02-11 do FGTS-02 (so dailies) + FGTS-03/06 intactos em 02-10
SELECT a.name, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag vig
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE a.name IN ('CR-FGTS-02-01-SINGLE','NXFGTSH35-1') AND v.date::date IN ('2026-02-10','2026-02-11')
ORDER BY a.name, v.date;

SELECT 'FGTS-03/06 em 02-10 (intactos)' AS check, a.name, count(*) FILTER (WHERE v.cash_flow<>0) AS eventos
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE a.name IN ('CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE') AND v.date::date='2026-02-10'
GROUP BY a.name ORDER BY a.name;

SELECT operation, table_name, count(*) AS gravadas_em_histories
FROM histories
WHERE created_by='gabriel_sifuentes' AND operation='delete'
  AND (description LIKE 'apaga evento amort 2026-02-10 do FGTS-02%' OR description LIKE 'apaga position AMORTIZATION 2026-02-10 da mae CR-FGTS-02%')
GROUP BY operation, table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
