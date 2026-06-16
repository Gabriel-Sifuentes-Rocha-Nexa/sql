-- ============================================================================
-- apaga_valuations_extra_FGTS01_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- O usuario accruou sem querer ALEM do 02-11 (dailies 02-12 -> 06-11), sem rodar
-- os amorts de 03-05/04-07/05-07. Apaga esses dailies extras (date > 02-11 09:00)
-- na SERIE CR-FGTS-01-01-SINGLE e no TOKEN NXFGTSJ34-1 (os dois espelham; manter sync),
-- voltando ao estado VALIDADO do 02-11 (amort 02-11 09:00 mantido).
-- Cada linha apagada -> `histories` (operation='delete') ANTES do DELETE. IDs por nome.
-- DRY-RUN: BEGIN..ROLLBACK; trocar por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — o que sai (deve ser so daily, cash_flow=0)
SELECT a.name AS ativo, count(*) AS val_a_apagar, min(v.date) AS menor, max(v.date) AS maior,
       count(*) FILTER (WHERE v.cash_flow <> 0) AS eventos_cf_nao_zero
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1')
  AND v.date > timestamptz '2026-02-11 09:00:00-03'
GROUP BY a.name;

-- (1) GUARDA: nada do que vai sair pode ser evento (cash_flow<>0) — so daily acidental
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM valuations
  WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1'))
    AND date > timestamptz '2026-02-11 09:00:00-03' AND cash_flow <> 0;
  IF n > 0 THEN RAISE EXCEPTION 'ha % valuation(s) com cash_flow<>0 apos 02-11 (nao sao daily; abortando p/ revisar)', n; END IF;
END $$;

-- (2) histories (linha antiga) antes do DELETE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'apaga valuations dailies extras (accrual acidental 02-12..06-11) da serie CR-FGTS-01-01-SINGLE + token NXFGTSJ34-1; volta ao 02-11'
FROM valuations v
WHERE v.asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1'))
  AND v.date > timestamptz '2026-02-11 09:00:00-03';

-- (3) DELETE
DELETE FROM valuations
WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1'))
  AND date > timestamptz '2026-02-11 09:00:00-03';

-- (4) GUARDA FINAL: serie/token terminam no amort 02-11 09:00, nao vazios
DO $$
DECLARE ns int; nt int; ms timestamptz; mt timestamptz;
BEGIN
  SELECT count(*), max(date) INTO ns, ms FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='CR-FGTS-01-01-SINGLE');
  SELECT count(*), max(date) INTO nt, mt FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='NXFGTSJ34-1');
  IF ms <> timestamptz '2026-02-11 09:00:00-03' OR mt <> timestamptz '2026-02-11 09:00:00-03'
     THEN RAISE EXCEPTION 'max(date) != amort 02-11 09:00 (serie=%, token=%)', ms, mt; END IF;
  IF ns <> nt THEN RAISE EXCEPTION 'serie (%) e token (%) dessincronizados', ns, nt; END IF;
  RAISE NOTICE 'OK: serie e token com % linhas, terminando no amort 02-11 09:00', ns;
END $$;

-- (5) POST-CHECK
SELECT a.name AS ativo, count(*) AS n, max(v.date) AS maior
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-01-01-SINGLE','NXFGTSJ34-1') GROUP BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
