-- ============================================================================
-- corrige_FGTS32_taxa_e_apaga_PROD.sql        (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- FGTS-32: DOIS problemas (ver reference_fgts_rate_and_startday_bug):
--   (1) TAXA: V2 spread_over_indexer=0.1821 (errada) vs 0.1832 (serie = V1).
--       Diagnostico: V2 accrua 0.06640796/dia, V1 0.06677729/dia (em 100, 1o dia 05-06).
--       Inicio ALINHADO (ambos comecam 05-06) -> e' SO taxa, sem shift.
--   (2) AMORT 06-10 FALTANDO: V1 extraordinary_repayment=4.44595619/un (last_value
--       101.68287871 -> 97.23692252). V2 nunca amortizou (clean travado em 100).
--
-- Como a taxa estava errada DESDE 05-06, todo o accrued esta' errado -> apagar do seed
-- (manter 05-04 emissao + 05-05, ambos 100/0) e re-accruar com 0.1832.
-- Depois o usuario: re-accrua ate 06-09, BOOKA amort 06-10 (4.44595619 x 40400 = 179616.63),
-- re-accrua 06-10 -> current.
--
-- Serie 1350805 (CR-FGTS-32-01-SINGLE) + token 1350806 (NXFGTSK35-3). qty 40400.
-- UPDATE de accrued NAO dispara trigger last_valuation_flag; DELETE dispara (recompoe).
-- AUDITORIA: linha antiga -> histories (update/delete) ANTES.
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW: taxa atual + curva inicio
SELECT id, spread_over_indexer AS taxa_atual, 0.1832::numeric AS taxa_nova FROM securitization_series WHERE id=1350805;
SELECT a.name AS ativo, v.date::date d, v.clean_price, v.accrued_interest,
       CASE WHEN v.date > timestamptz '2026-05-05 00:00:00-03' THEN '-> DELETE' ELSE '(mantem seed)' END AS acao
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1350805,1350806)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date < timestamptz '2026-05-12 00:00:00-03' ORDER BY a.name, v.date;

-- (1) histories — taxa (securitization_series)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'securitization_series', to_jsonb(ss), 'update',
       'FGTS-32: corrige taxa spread_over_indexer 0.1821 -> 0.1832 (serie = V1)'
FROM securitization_series ss WHERE ss.id=1350805;

-- (2) histories — valuations a apagar (05-06+)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes', 'valuations', to_jsonb(v), 'delete',
       'FGTS-32 apaga accrual com taxa errada (>05-05) p/ re-accruar em 0.1832; amort 06-10 sera bookado depois'
FROM valuations v
WHERE v.asset_id IN (1350805,1350806)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND v.date > timestamptz '2026-05-05 00:00:00-03';

-- (3) UPDATE taxa
UPDATE securitization_series SET spread_over_indexer = 0.1832 WHERE id=1350805;

-- (4) DELETE valuations > 05-05 (mantem seed 05-04/05-05 = 100/0)
DELETE FROM valuations
WHERE asset_id IN (1350805,1350806)
  AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
  AND date > timestamptz '2026-05-05 00:00:00-03';

-- (5) GUARDA: taxa 0.1832; seed presente (05-05 100/0); nada >05-05
DO $$
DECLARE r numeric; bad int; seedok int;
BEGIN
  SELECT spread_over_indexer INTO r FROM securitization_series WHERE id=1350805;
  IF r <> 0.1832 THEN RAISE EXCEPTION 'taxa != 0.1832 (%)', r; END IF;
  SELECT count(*) INTO seedok FROM valuations
   WHERE asset_id IN (1350805,1350806)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date::date = DATE '2026-05-05' AND clean_price=100 AND accrued_interest=0;
  IF seedok <> 2 THEN RAISE EXCEPTION 'seed 05-05 100/0 ausente (% de 2)', seedok; END IF;
  SELECT count(*) INTO bad FROM valuations
   WHERE asset_id IN (1350805,1350806)
     AND methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
     AND date > timestamptz '2026-05-05 00:00:00-03';
  IF bad <> 0 THEN RAISE EXCEPTION 'ainda ha % linhas >05-05', bad; END IF;
  RAISE NOTICE 'OK: taxa 0.1832, seed 05-05 mantido, tudo >05-05 apagado';
END $$;

-- (6) POST-CHECK
SELECT a.name AS ativo, max(v.date)::date AS ultima_data, count(*) AS n
FROM valuations v JOIN entities a ON a.id=v.asset_id
WHERE v.asset_id IN (1350805,1350806)
  AND v.methodology_id=(SELECT id FROM valuation_methodologies WHERE name='amortized_cost')
GROUP BY a.name;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
