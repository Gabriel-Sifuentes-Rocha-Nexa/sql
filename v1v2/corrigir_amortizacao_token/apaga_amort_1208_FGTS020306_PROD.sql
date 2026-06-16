-- ============================================================================
-- apaga_amort_1208_FGTS020306_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- O usuario rodou o amort de 2025-12-08 ANTES de terminar o accrual. A accrual
-- AINDA ESTA RODANDO (gerando dailies forward). Por isso o alvo e' PRECISO: so o
-- EVENTO de amort, nunca um range de datas (senao apagaria dailies novas).
--   * VALUATIONS (serie + token) com date::date='2025-12-08' AND cash_flow<>0
--     (= o evento 09:00; FGTS-02/03 tem, FGTS-06 nao). Dailies (cash_flow=0) FICAM.
--   * POSITIONS AMORTIZATION de 12-08 das 3 maes (CR-FGTS-02/03/06).
--
-- Pares: CR-FGTS-02-01-SINGLE<->NXFGTSH35-1, 03<->NXFGTSH35-2, 06<->NXFGTSI35-3.
-- AUDITORIA: cada linha -> `histories` (operation='delete', created_by gabriel_sifuentes) ANTES do DELETE.
-- DRY-RUN: BEGIN..ROLLBACK; trocar por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — rows de 12-08 (daily cash_flow=0 fica; evento cash_flow<>0 sai) + positions
SELECT a.name AS ativo, v.date, v.clean_price, v.accrued_interest, v.cash_flow,
       CASE WHEN v.cash_flow<>0 THEN 'APAGA (evento)' ELSE 'mantem (daily)' END AS acao
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-02-01-SINGLE','CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE',
                 'NXFGTSH35-1','NXFGTSH35-2','NXFGTSI35-3')
  AND v.date::date='2025-12-08'
ORDER BY a.name, v.date;

SELECT h.name AS mae, count(*) AS pos_a_apagar, sum(pp.variation) AS soma_var
FROM positions pp JOIN entities h ON h.id=pp.holder_id
WHERE h.name IN ('CR-FGTS-02','CR-FGTS-03','CR-FGTS-06')
  AND pp.date::date='2025-12-08' AND pp.transaction_type_id=(SELECT id FROM transaction_types WHERE name='AMORTIZATION')
GROUP BY h.name ORDER BY h.name;

-- (1) histories das VALUATIONS (so eventos 12-08) antes do DELETE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'apaga evento amort 2025-12-08 (rodado com accrual incompleto) de CR-FGTS-02/03/06 + tokens; dailies mantidas; re-rodar apos accrual completo'
FROM valuations v
WHERE v.asset_id IN (SELECT id FROM entities WHERE name IN
        ('CR-FGTS-02-01-SINGLE','CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE','NXFGTSH35-1','NXFGTSH35-2','NXFGTSI35-3'))
  AND v.date::date='2025-12-08' AND v.cash_flow <> 0;

-- (2) DELETE das VALUATIONS (so eventos 12-08)
DELETE FROM valuations
WHERE asset_id IN (SELECT id FROM entities WHERE name IN
        ('CR-FGTS-02-01-SINGLE','CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE','NXFGTSH35-1','NXFGTSH35-2','NXFGTSI35-3'))
  AND date::date='2025-12-08' AND cash_flow <> 0;

-- (3) histories das POSITIONS antes do DELETE
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'positions', to_jsonb(pp), 'delete',
       'apaga position AMORTIZATION 2025-12-08 da mae (amort rodado com accrual incompleto) p/ re-rodar'
FROM positions pp
WHERE pp.holder_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-02','CR-FGTS-03','CR-FGTS-06'))
  AND pp.date::date='2025-12-08' AND pp.transaction_type_id=(SELECT id FROM transaction_types WHERE name='AMORTIZATION');

-- (4) DELETE das POSITIONS
DELETE FROM positions
WHERE holder_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-02','CR-FGTS-03','CR-FGTS-06'))
  AND date::date='2025-12-08' AND transaction_type_id=(SELECT id FROM transaction_types WHERE name='AMORTIZATION');

-- (5) GUARDA: nenhum evento 12-08 (cash_flow<>0) nem position amort 12-08 sobra
DO $$
DECLARE rem_ev int; rem_pos int;
BEGIN
  SELECT count(*) INTO rem_ev FROM valuations
   WHERE asset_id IN (SELECT id FROM entities WHERE name IN
         ('CR-FGTS-02-01-SINGLE','CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE','NXFGTSH35-1','NXFGTSH35-2','NXFGTSI35-3'))
     AND date::date='2025-12-08' AND cash_flow <> 0;
  IF rem_ev <> 0 THEN RAISE EXCEPTION 'ainda restam % evento(s) amort 12-08', rem_ev; END IF;

  SELECT count(*) INTO rem_pos FROM positions
   WHERE holder_id IN (SELECT id FROM entities WHERE name IN ('CR-FGTS-02','CR-FGTS-03','CR-FGTS-06'))
     AND date::date='2025-12-08' AND transaction_type_id=(SELECT id FROM transaction_types WHERE name='AMORTIZATION');
  IF rem_pos <> 0 THEN RAISE EXCEPTION 'ainda restam % position(s) amort 12-08', rem_pos; END IF;
  RAISE NOTICE 'OK: evento e position de amort 12-08 removidos; dailies preservadas';
END $$;

-- (6) POST-CHECK: o que sobrou em 12-08 (so daily, se a accrual ja chegou la) + estado geral
SELECT a.name AS ativo, count(*) FILTER (WHERE v.date::date='2025-12-08') AS rows_1208,
       count(*) AS n_total, max(v.date) AS maior
FROM valuations v JOIN entities a ON a.id = v.asset_id
WHERE a.name IN ('CR-FGTS-02-01-SINGLE','CR-FGTS-03-01-SINGLE','CR-FGTS-06-01-SINGLE','NXFGTSH35-1','NXFGTSH35-2','NXFGTSI35-3')
GROUP BY a.name ORDER BY a.name;

SELECT operation, table_name, count(*) AS gravadas_em_histories
FROM histories
WHERE created_by='gabriel_sifuentes' AND operation='delete'
  AND (description LIKE 'apaga evento amort 2025-12-08%CR-FGTS-02/03/06%'
       OR description LIKE 'apaga position AMORTIZATION 2025-12-08%')
GROUP BY operation, table_name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
