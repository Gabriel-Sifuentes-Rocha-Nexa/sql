-- ============================================================================
-- forca_inicio_FGTS23_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- FGTS-23: a taxa ja' esta' corrigida (0.1645) e o engine accrua certo dali pra frente.
-- O UNICO residuo e' o shift de 1 dia no INICIO (V2 larga 03-03, V1 so' 03-04).
-- Estrategia (ideia do Gabriel): FORCAR as 3 primeiras linhas a baterem com o V1 e
-- deixar o engine reconstruir o resto (ele so' preenche buraco a partir da ultima linha).
--   V1: 03-03 accrued=0 (ainda nao accrua) | 03-04=0.06045152 | 03-05=0.12093958
-- Hoje o V2 esta' shiftado: 03-03=0.06045152, 03-04=0.12093958, 03-05=0.18146421, 03-06=0.24202543.
-- Fix = "puxar 1 dia pra tras": UPDATE accrued das 3 primeiras p/ o valor do V1 (clean fica 100,
-- cash_flow 0), e DELETE o 03-06 (shiftado) p/ o engine refazer dele em diante.
-- Verificacao apos re-accrual: o engine deve gerar 03-06 = 0.18146421 (= V1).
--
-- Serie 1057325 (CR-FGTS-23-01-SINGLE) + token 1057326 (NXFGTSB31-2). methodology amortized_cost.
-- UPDATE de accrued_interest NAO dispara o trigger de last_valuation_flag (so' date/asset/lot/method).
-- AUDITORIA: linha antiga -> `histories` (update/delete, created_by gabriel_sifuentes) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: estado atual das 4 primeiras dailies (shiftado) + alvo
SELECT a.name AS ativo, v.date::date d, v.clean_price, v.accrued_interest AS accrued_atual,
       CASE v.date::date
         WHEN DATE '2026-03-03' THEN 0::numeric
         WHEN DATE '2026-03-04' THEN 0.06045152::numeric
         WHEN DATE '2026-03-05' THEN 0.12093958::numeric
         WHEN DATE '2026-03-06' THEN NULL END AS accrued_alvo_v1
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1057325,1057326)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date::date IN (DATE '2026-03-03',DATE '2026-03-04',DATE '2026-03-05',DATE '2026-03-06')
ORDER BY a.name, v.date;

-- (1) histories ANTES (3 updates + 1 delete por ativo = 8 linhas)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v),
       (CASE WHEN v.date::date = DATE '2026-03-06' THEN 'delete' ELSE 'update' END)::operations_enum,
       'FGTS-23 forca inicio: alinha 03-03/04/05 accrued ao V1 (corrige shift de 1 dia) e apaga 03-06 p/ engine refazer'
FROM valuations v
WHERE v.asset_id IN (1057325,1057326)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date::date IN (DATE '2026-03-03',DATE '2026-03-04',DATE '2026-03-05',DATE '2026-03-06');

-- (2) UPDATE accrued das 3 primeiras p/ o valor do V1 (clean fica 100, cash_flow 0)
UPDATE valuations SET accrued_interest = 0
 WHERE asset_id IN (1057325,1057326)
   AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
   AND date::date = DATE '2026-03-03';
UPDATE valuations SET accrued_interest = 0.06045152
 WHERE asset_id IN (1057325,1057326)
   AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
   AND date::date = DATE '2026-03-04';
UPDATE valuations SET accrued_interest = 0.12093958
 WHERE asset_id IN (1057325,1057326)
   AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
   AND date::date = DATE '2026-03-05';

-- (3) DELETE o 03-06 (shiftado) -> engine reconstroi dele em diante
DELETE FROM valuations
 WHERE asset_id IN (1057325,1057326)
   AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
   AND date::date = DATE '2026-03-06';

-- (4) GUARDA: 03-03/04/05 com accrued do V1, clean 100; nada em 03-06; max date = 03-05
DO $$
DECLARE bad int; ms timestamptz; mt timestamptz;
BEGIN
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id IN (1057325,1057326)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND ( (date::date=DATE '2026-03-03' AND (accrued_interest<>0 OR clean_price<>100))
        OR (date::date=DATE '2026-03-04' AND (round(accrued_interest,8)<>0.06045152 OR clean_price<>100))
        OR (date::date=DATE '2026-03-05' AND (round(accrued_interest,8)<>0.12093958 OR clean_price<>100))
        OR (date::date=DATE '2026-03-06') );
  IF bad <> 0 THEN RAISE EXCEPTION 'estado pos-fix inesperado (% linhas)', bad; END IF;
  SELECT max(date) INTO ms FROM valuations WHERE asset_id=1057325 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost');
  SELECT max(date) INTO mt FROM valuations WHERE asset_id=1057326 AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost');
  IF ms<>timestamptz '2026-03-05 00:00:00-03' OR mt<>timestamptz '2026-03-05 00:00:00-03'
     THEN RAISE EXCEPTION 'max(date) != 03-05 (serie=%, token=%)', ms, mt; END IF;
  RAISE NOTICE 'OK: 03-03/04/05 alinhados ao V1, 03-06 apagado, max date = 03-05';
END $$;

-- (5) POST-CHECK
SELECT a.name AS ativo, v.date::date d, v.clean_price, v.accrued_interest,
       (v.clean_price+v.accrued_interest) AS dirty, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1057325,1057326)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date >= timestamptz '2026-03-02 00:00:00-03'
ORDER BY a.name, v.date;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
