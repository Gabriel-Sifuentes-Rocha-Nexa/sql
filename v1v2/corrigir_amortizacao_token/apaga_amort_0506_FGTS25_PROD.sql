-- ============================================================================
-- apaga_amort_0506_FGTS25_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- FGTS-25 DIVERGE em 2026-05-06: o V2 sub-amortizou (clean 100 -> 96.20201, drop so
-- 3.798; V1 manda drop 5.26621213 -> clean 94.73378787) e ainda gravou cf=-clean.
-- O clean errado (96.20201) PROPAGOU de 05-06 ate hoje. Fix = re-run a partir de 05-06.
-- Apaga valuations (serie + token) date > '2026-05-06 00:00:00-03' (= evento 05-06 09:00
-- + todo o forward), MANTENDO o pre-amort 05-06 00:00 (clean 100, accrued 2.45958039).
-- NAO mexo em positions (o upsert sobrescreve a antiga -30796.20 no re-run).
--
-- Par: CR-FGTS-25-01-SINGLE <-> NXFGTSC31-1. quantity = 30800.
-- AUDITORIA: cada linha -> `histories` (operation='delete', created_by gabriel_sifuentes) ANTES do DELETE.
-- DRY-RUN: BEGIN..ROLLBACK; trocar por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW
SELECT a.name AS ativo, count(*) AS val_a_apagar, min(v.date) AS menor, max(v.date) AS maior,
       count(*) FILTER (WHERE v.cash_flow<>0) AS eventos
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-25-01-SINGLE','NXFGTSC31-1')
  AND v.date > timestamptz '2026-05-06 00:00:00-03'
GROUP BY a.name ORDER BY a.name;

-- (1) histories antes do DELETE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'apaga valuations > 2026-05-06 00:00 (DIVERGE: V2 sub-amortizou clean->96.20201, propagou) de CR-FGTS-25 + token NXFGTSC31-1; re-run a partir de 05-06'
FROM valuations v
WHERE v.asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-25-01-SINGLE','NXFGTSC31-1'))
  AND v.date > timestamptz '2026-05-06 00:00:00-03';

-- (2) DELETE
DELETE FROM valuations
WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-25-01-SINGLE','NXFGTSC31-1'))
  AND date > timestamptz '2026-05-06 00:00:00-03';

-- (3) GUARDA: 2 ativos terminam no pre-amort 05-06 00:00; sincronizados; nada > seed
DO $$
DECLARE ns int; nt int; ms timestamptz; mt timestamptz;
BEGIN
  SELECT count(*), max(date) INTO ns, ms FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='CR-FGTS-25-01-SINGLE');
  SELECT count(*), max(date) INTO nt, mt FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='NXFGTSC31-1');
  IF ms <> timestamptz '2026-05-06 00:00:00-03' OR mt <> timestamptz '2026-05-06 00:00:00-03'
     THEN RAISE EXCEPTION 'max(date) != pre-amort 05-06 00:00 (serie=%, token=%)', ms, mt; END IF;
  IF ns <> nt THEN RAISE EXCEPTION 'serie (%) e token (%) dessincronizados', ns, nt; END IF;
  RAISE NOTICE 'OK: serie e token com % linhas, terminando no pre-amort 05-06 00:00 (clean 100)', ns;
END $$;

-- (4) POST-CHECK: estado + o seed 05-06 00:00
SELECT a.name AS ativo, count(*) AS n, max(v.date) AS maior,
       count(*) FILTER (WHERE v.last_valuation_flag) AS vigente
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-25-01-SINGLE','NXFGTSC31-1') GROUP BY a.name ORDER BY a.name;

SELECT a.name, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag vig
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-25-01-SINGLE','NXFGTSC31-1') AND v.date::date='2026-05-06' ORDER BY a.name, v.date;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
