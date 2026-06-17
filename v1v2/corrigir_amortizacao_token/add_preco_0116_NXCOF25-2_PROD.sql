-- ============================================================================
-- add_preco_0116_NXCOF25-2_PROD.sql            (PROD via tunel :5003)
-- ----------------------------------------------------------------------------
-- GAMBIARRA pedida pelo Gabriel: adicionar um PRECO em 2025-01-16 = 100 para o
-- token NXCOF25-2 (asset 1938), p/ fazer funcionar uma parada idiossincratica
-- downstream. 01-16 e' ANTES da emissao (01-17), entao a linha NAO vira vigente.
--   INSERT valuation: date 2025-01-16 00:00, clean_price 100, accrued 0, cash_flow 0,
--                     methodology amortized_cost (copia metadata da emissao 188239).
-- Idempotente: apaga qualquer valuation 1938 ja' existente em 2025-01-16 antes (com history).
-- DRY-RUN: BEGIN..ROLLBACK; trocar ROLLBACK por COMMIT p/ aplicar.
-- ============================================================================

BEGIN;

-- (0) PREVIEW — primeiras valuations do token + ja' existe algo em 01-16?
SELECT v.id, v.date, v.clean_price, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v WHERE v.asset_id=1938 AND v.date::date BETWEEN '2025-01-15' AND '2025-01-18'
ORDER BY v.date;

-- (1) histories — apaga linha 01-16 pre-existente (se houver)
INSERT INTO histories (created_by, table_name, old_value, operation, description)
SELECT 'gabriel_sifuentes','valuations', to_jsonb(v),'delete',
       'NXCOF25-2 gambiarra: remove valuation 01-16 pre-existente antes de reinserir clean=100'
FROM valuations v WHERE v.asset_id=1938 AND v.date::date='2025-01-16';

DELETE FROM valuations WHERE asset_id=1938 AND date::date='2025-01-16';

-- (2) INSERT preco 01-16 = 100 (copia metadata da emissao 188239)
INSERT INTO valuations (date, asset_id, lot_id, methodology_id, clean_price, accrued_interest,
   indexer_id, indexer_percentage, spread_over_indexer, spread_over_cdi, spread_over_inflation,
   cash_flow, currency_id, last_valuation_flag, duration_years)
SELECT timestamptz '2025-01-16 00:00:00-03', asset_id, lot_id, methodology_id, 100, 0,
   indexer_id, indexer_percentage, spread_over_indexer, spread_over_cdi, spread_over_inflation,
   0, currency_id, false, duration_years
FROM valuations WHERE id=188239;

-- (3) GUARDA
DO $$
DECLARE n int; cl numeric; vig boolean;
BEGIN
  SELECT count(*) INTO n FROM valuations WHERE asset_id=1938 AND date::date='2025-01-16';
  IF n <> 1 THEN RAISE EXCEPTION 'esperado 1 valuation em 01-16, achou %', n; END IF;
  SELECT clean_price, last_valuation_flag INTO cl, vig FROM valuations WHERE asset_id=1938 AND date::date='2025-01-16';
  IF cl <> 100 THEN RAISE EXCEPTION 'clean 01-16 = % (esp 100)', cl; END IF;
  IF vig THEN RAISE EXCEPTION '01-16 nao deveria ser vigente (e anterior a emissao)'; END IF;
  RAISE NOTICE 'OK NXCOF25-2: preco 01-16 = 100 inserido (nao-vigente)';
END $$;

-- (4) POST-CHECK
SELECT v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v WHERE v.asset_id=1938 AND v.date::date BETWEEN '2025-01-15' AND '2025-01-18' ORDER BY v.date;

ROLLBACK;   -- DRY-RUN. Troque por COMMIT para aplicar.
