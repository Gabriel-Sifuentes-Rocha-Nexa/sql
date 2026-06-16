-- ============================================================================
-- apaga_valuations_FGTS23_desde_accrual_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- FGTS-23: reconstrucao desde o INICIO do accrual. Motivo: testar se, ao re-accruar
-- do zero, o engine PARA de comecar a accruar no dia errado (V2 larga em 03-03; V1 so
-- em 03-04) e tb refazer a janela de FREEZE (04-15->04-27, accrued travado em 1.78260679).
-- Mantemos o seed pre-accrual: ultimo daily com accrued=0 / clean=100 = 2026-03-02 00:00-03
-- (e toda a historia <= 03-02, incluindo a emissao 02-13). Apagamos 03-03 -> 06-11 (inclui
-- o amort errado de 05-07). Re-accrual regenera; depois re-bookar 05-07 (5475.53) e 06-08 (48753.23).
-- NAO mexo em positions (o upsert do re-book sobrescreve a AMORTIZATION de 05-07; 06-08 e' novo).
--
-- Par: CR-FGTS-23-01-SINGLE <-> NXFGTSB31-2. quantity = 10100.
-- AUDITORIA: cada linha -> `histories` (operation='delete', created_by gabriel_sifuentes) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: o que vai ser apagado (03-03+) + o seed que fica (03-02)
SELECT a.name AS ativo, count(*) AS val_a_apagar, min(v.date) AS menor, max(v.date) AS maior,
       count(*) FILTER (WHERE v.cash_flow<>0) AS eventos
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-23-01-SINGLE','NXFGTSB31-2')
  AND v.date > timestamptz '2026-03-02 00:00:00-03'
GROUP BY a.name ORDER BY a.name;

-- seed que permanece (deve ser clean=100, accrued=0)
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-23-01-SINGLE','NXFGTSB31-2')
  AND v.date = timestamptz '2026-03-02 00:00:00-03' ORDER BY a.name;

-- (1) histories antes do DELETE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'FGTS-23: apaga valuations > 2026-03-02 00:00 (re-accrual desde o inicio p/ testar dia de largada + refazer FREEZE 04-15..04-27 + amort 05-07 errado)'
FROM valuations v
WHERE v.asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-23-01-SINGLE','NXFGTSB31-2'))
  AND v.date > timestamptz '2026-03-02 00:00:00-03';

-- (2) DELETE
DELETE FROM valuations
WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-23-01-SINGLE','NXFGTSB31-2'))
  AND date > timestamptz '2026-03-02 00:00:00-03';

-- (3) GUARDA: serie e token terminam no seed 03-02 00:00, sincronizados, seed = clean 100 / accrued 0
DO $$
DECLARE ns int; nt int; ms timestamptz; mt timestamptz; seed_bad int;
BEGIN
  SELECT count(*), max(date) INTO ns, ms FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='CR-FGTS-23-01-SINGLE');
  SELECT count(*), max(date) INTO nt, mt FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='NXFGTSB31-2');
  IF ms <> timestamptz '2026-03-02 00:00:00-03' OR mt <> timestamptz '2026-03-02 00:00:00-03'
     THEN RAISE EXCEPTION 'max(date) != seed 03-02 00:00 (serie=%, token=%)', ms, mt; END IF;
  IF ns <> nt THEN RAISE EXCEPTION 'serie (%) e token (%) dessincronizados', ns, nt; END IF;
  SELECT count(*) INTO seed_bad FROM valuations
   WHERE asset_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-23-01-SINGLE','NXFGTSB31-2'))
     AND date = timestamptz '2026-03-02 00:00:00-03'
     AND (clean_price<>100 OR COALESCE(accrued_interest,0)<>0);
  IF seed_bad <> 0 THEN RAISE EXCEPTION 'seed 03-02 nao esta clean=100/accrued=0 (% linhas)', seed_bad; END IF;
  RAISE NOTICE 'OK: serie e token com % linhas, terminando no seed 03-02 00:00 (clean 100, accrued 0)', ns;
END $$;

-- (4) POST-CHECK
SELECT a.name AS ativo, count(*) AS n, max(v.date) AS maior,
       count(*) FILTER (WHERE v.last_valuation_flag) AS vigente
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-23-01-SINGLE','NXFGTSB31-2') GROUP BY a.name ORDER BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
