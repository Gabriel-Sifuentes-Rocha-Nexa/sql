-- ============================================================================
-- apaga_valuations_FGTS020306_1114_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- GLITCH_ACCRUED em 2025-11-14: nos 3 CRs o evento de amort reverteu ~0.065 de
-- accrued (dirty contaminado) e isso PROPAGA/compoe forward (price_off vai de
-- -0.0666 ate -0.072). Fix = re-rodar a partir de 11-14. Aqui so apago VALUATIONS
-- (serie + token) com date > '2025-11-14 00:00:00-03' (= o evento 09:00 + todo o
-- forward ate hoje), MANTENDO o pre-amort 11-14 00:00 (seed) p/ o usuario re-rodar
-- a amortizacao de 11-14 pela API. NAO mexo em positions (upsert sobrescreve no re-run).
--
-- Pares confirmados por quantidade (serie.quantity == token.issuance_amount):
--   CR-FGTS-02-01-SINGLE <-> NXFGTSH35-1
--   CR-FGTS-03-01-SINGLE <-> NXFGTSH35-2
--   CR-FGTS-06-01-SINGLE <-> NXFGTSI35-3
--
-- AUDITORIA: cada linha apagada -> `histories` (operation='delete', created_by gabriel_sifuentes) ANTES do DELETE.
-- DRY-RUN: BEGIN..ROLLBACK; trocar por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — o que sera apagado por ativo (menor deve ser 11-14 12:00Z = 09:00-03 = evento)
SELECT a.name AS ativo, count(*) AS val_a_apagar, min(v.date) AS menor, max(v.date) AS maior,
       count(*) FILTER (WHERE v.cash_flow <> 0) AS eventos_cf_nao_zero
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-02-01-SINGLE','CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE',
                 'NXFGTSH35-1','NXFGTSH35-2','NXFGTSI35-3')
  AND v.date > timestamptz '2025-11-14 00:00:00-03'
GROUP BY a.name ORDER BY a.name;

-- (1) histories (linha antiga) antes do DELETE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'apaga valuations > 2025-11-14 00:00 (GLITCH accrued revertido propagou forward) de CR-FGTS-02/03/06 + tokens NXFGTSH35-1/2, NXFGTSI35-3; re-run a partir de 11-14'
FROM valuations v
WHERE v.asset_id IN (SELECT id FROM entities WHERE name IN
        ('CR-FGTS-02-01-SINGLE','CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE',
         'NXFGTSH35-1','NXFGTSH35-2','NXFGTSI35-3'))
  AND v.date > timestamptz '2025-11-14 00:00:00-03';

-- (2) DELETE
DELETE FROM valuations
WHERE asset_id IN (SELECT id FROM entities WHERE name IN
        ('CR-FGTS-02-01-SINGLE','CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE',
         'NXFGTSH35-1','NXFGTSH35-2','NXFGTSI35-3'))
  AND date > timestamptz '2025-11-14 00:00:00-03';

-- (3) GUARDA: cada ativo termina no seed 11-14 00:00; pares serie/token sincronizados; nada > seed
DO $$
DECLARE r record; bad int := 0;
BEGIN
  -- nada pode restar apos o seed
  FOR r IN
    SELECT a.name, count(*) FILTER (WHERE v.date > timestamptz '2025-11-14 00:00:00-03') AS apos_seed,
           max(v.date) AS maxd, count(*) AS n
    FROM entities a LEFT JOIN valuations v ON v.asset_id=a.id
    WHERE a.name IN ('CR-FGTS-02-01-SINGLE','CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE',
                     'NXFGTSH35-1','NXFGTSH35-2','NXFGTSI35-3')
    GROUP BY a.name
  LOOP
    IF r.apos_seed <> 0 THEN RAISE EXCEPTION '% ainda tem % linhas apos o seed 11-14 00:00', r.name, r.apos_seed; END IF;
    IF r.maxd <> timestamptz '2025-11-14 00:00:00-03' THEN RAISE EXCEPTION '% max(date)=% != seed 11-14 00:00', r.name, r.maxd; END IF;
  END LOOP;
  -- pares sincronizados (serie count == token count)
  IF (SELECT count(*) FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='CR-FGTS-02-01-SINGLE'))
   <> (SELECT count(*) FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='NXFGTSH35-1')) THEN bad:=bad+1; END IF;
  IF (SELECT count(*) FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='CR-FGTS-03-01-SINGLE'))
   <> (SELECT count(*) FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='NXFGTSH35-2')) THEN bad:=bad+1; END IF;
  IF (SELECT count(*) FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='CR-FGTS-06-01-SINGLE'))
   <> (SELECT count(*) FROM valuations WHERE asset_id=(SELECT id FROM entities WHERE name='NXFGTSI35-3')) THEN bad:=bad+1; END IF;
  IF bad > 0 THEN RAISE EXCEPTION 'algum par serie/token ficou dessincronizado (% pares)', bad; END IF;
  RAISE NOTICE 'OK: 6 ativos terminam no pre-amort 11-14 00:00 e os 3 pares estao sincronizados';
END $$;

-- (4) POST-CHECK: estado + o seed mantido (11-14 00:00 = 03:00Z)
SELECT a.name AS ativo, count(*) AS n, max(v.date) AS maior,
       count(*) FILTER (WHERE v.last_valuation_flag) AS vigente
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-02-01-SINGLE','CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE',
                 'NXFGTSH35-1','NXFGTSH35-2','NXFGTSI35-3')
GROUP BY a.name ORDER BY a.name;

SELECT a.name, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-02-01-SINGLE','CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE',
                 'NXFGTSH35-1','NXFGTSH35-2','NXFGTSI35-3')
  AND v.date::date='2025-11-14'
ORDER BY a.name, v.date;

SELECT operation, table_name, count(*) AS gravadas_em_histories
FROM histories
WHERE created_by='gabriel_sifuentes' AND operation='delete'
  AND description LIKE 'apaga valuations > 2025-11-14%CR-FGTS-02/03/06%'
GROUP BY operation, table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
