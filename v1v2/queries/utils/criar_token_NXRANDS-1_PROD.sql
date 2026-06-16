-- ============================================================
-- Criar token NXRANDS-1 no Engine V2 (PROD) + serie historica de valuations
-- Gerado a partir do V1 (Supabase): securities.aux_id = ce7269f5-d5c2-4af5-974f-494dcb04b3e5
--   V1: type=token, strategy=FIP, issuer=NEXA DIGITAL ASSETS SA, issuer_code=NX
--   Subjacente V1 (FIP Patria): NAO inserido (sem positions, por decisao do usuario).
-- Decisoes: strategy NOVA 'FIP'; structure NOVA 'virtual'; SEM positions.
-- Valuations: 122 linhas (2025-12-17 .. 2026-06-16).
--   methodology=amortized_cost, lot_id=1, clean_price=PU(V1), accrued=0,
--   indexer=NULL, spreads=0, cash_flow=0, currency=BRL (issuer 'BRA').
-- IDs resolvidos por NOME em runtime (portavel). Roda como UMA transacao.
-- Pre-check aborta se NXRANDS-1 ja existir ou se faltar emissor/lookup base.
-- ============================================================
BEGIN;

-- 0) Pre-check
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM entities WHERE name = 'NXRANDS-1') THEN
    RAISE EXCEPTION 'NXRANDS-1 ja existe em entities -- abortando';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM entities WHERE name = 'NEXA DIGITAL ASSETS SA') THEN
    RAISE EXCEPTION 'Emissor NEXA DIGITAL ASSETS SA nao encontrado -- abortando';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM sources WHERE name = 'INTERNAL') THEN
    RAISE EXCEPTION 'source INTERNAL nao encontrado -- abortando';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM reference_tables WHERE name = 'tokens') THEN
    RAISE EXCEPTION 'reference_table tokens nao encontrado -- abortando';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM valuation_methodologies WHERE name = 'amortized_cost') THEN
    RAISE EXCEPTION 'methodology amortized_cost nao encontrada -- abortando';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM currencies c JOIN currency_issuers ci ON ci.id=c.currency_issuer_id WHERE ci.name='BRA') THEN
    RAISE EXCEPTION 'currency BRA nao encontrada -- abortando';
  END IF;
END $$;

-- 1) Lookups novos (idempotentes)
INSERT INTO token_strategies (strategy_code, strategy_name, strategy_asset)
SELECT 'FIP', 'fip', 'tokens'
WHERE NOT EXISTS (
    SELECT 1 FROM token_strategies WHERE strategy_code = 'FIP' AND strategy_name = 'fip'
);

INSERT INTO token_structures (structure_name)
SELECT 'virtual'
WHERE NOT EXISTS (
    SELECT 1 FROM token_structures WHERE structure_name = 'virtual'
);

-- 2) Entity do token
INSERT INTO entities (name, source_id, reference_table_id)
VALUES (
    'NXRANDS-1',
    (SELECT id FROM sources WHERE name = 'INTERNAL'),
    (SELECT id FROM reference_tables WHERE name = 'tokens')
);

-- 3) Token (id = entity recem-criada; FKs por nome)
INSERT INTO tokens (
    id, strategy_id, structure_id, issuance_count, issuer_id, issuer_code,
    indexer_id, estimated_moic, issuance_price, issuance_amount,
    offering_duration, internal_rate_of_return, maturity_date,
    return_percentage_cdi, minimum_issuance_amount,
    estimated_spread_over_cdi, estimated_spread_over_inflation,
    distributor, referral_fee
)
SELECT
    (SELECT id FROM entities WHERE name = 'NXRANDS-1'),
    (SELECT id FROM token_strategies WHERE strategy_code = 'FIP' AND strategy_name = 'fip'),
    (SELECT id FROM token_structures WHERE structure_name = 'virtual'),
    1,
    (SELECT id FROM entities WHERE name = 'NEXA DIGITAL ASSETS SA'),
    'NX',
    NULL,            -- indexer_id (FIP: sem indexador)
    0,               -- estimated_moic
    0.01,            -- issuance_price
    55420959,        -- issuance_amount
    90,              -- offering_duration
    0,               -- internal_rate_of_return
    DATE '2035-12-17',  -- maturity_date (V1 last_maturity_date)
    0,               -- return_percentage_cdi
    1,               -- minimum_issuance_amount
    0,               -- estimated_spread_over_cdi
    0,               -- estimated_spread_over_inflation
    'platform',      -- distributor
    0;               -- referral_fee

-- 4) Valuations (122 linhas) -- last_valuation_flag=TRUE so na ultima data (2026-06-16)
INSERT INTO valuations (
    date, asset_id, lot_id, methodology_id, clean_price, accrued_interest,
    indexer_id, indexer_percentage, spread_over_indexer, spread_over_cdi, spread_over_inflation,
    cash_flow, currency_id, last_valuation_flag
)
SELECT
    v.d,
    (SELECT id FROM entities WHERE name = 'NXRANDS-1'),
    1,
    (SELECT id FROM valuation_methodologies WHERE name = 'amortized_cost'),
    v.pu,
    0,               -- accrued_interest
    NULL,            -- indexer_id
    0, 0, 0, 0,      -- indexer_percentage, spread_over_indexer, spread_over_cdi, spread_over_inflation
    0,               -- cash_flow
    (SELECT c.id FROM currencies c JOIN currency_issuers ci ON ci.id = c.currency_issuer_id WHERE ci.name = 'BRA'),
    (v.d = TIMESTAMPTZ '2026-06-16 00:00:00-03')
FROM (VALUES
    (TIMESTAMPTZ '2025-12-17 00:00:00-03', 0.01),
    (TIMESTAMPTZ '2025-12-18 00:00:00-03', 0.01),
    (TIMESTAMPTZ '2025-12-19 00:00:00-03', 0.00999926),
    (TIMESTAMPTZ '2025-12-22 00:00:00-03', 0.00999889),
    (TIMESTAMPTZ '2025-12-23 00:00:00-03', 0.00999852),
    (TIMESTAMPTZ '2025-12-24 00:00:00-03', 0.00999815),
    (TIMESTAMPTZ '2025-12-26 00:00:00-03', 0.00999778),
    (TIMESTAMPTZ '2025-12-29 00:00:00-03', 0.00999741),
    (TIMESTAMPTZ '2025-12-30 00:00:00-03', 0.00999704),
    (TIMESTAMPTZ '2025-12-31 00:00:00-03', 0.00999667),
    (TIMESTAMPTZ '2026-01-02 00:00:00-03', 0.0099963),
    (TIMESTAMPTZ '2026-01-05 00:00:00-03', 0.00999593),
    (TIMESTAMPTZ '2026-01-06 00:00:00-03', 0.00999556),
    (TIMESTAMPTZ '2026-01-07 00:00:00-03', 0.00999519),
    (TIMESTAMPTZ '2026-01-08 00:00:00-03', 0.00999482),
    (TIMESTAMPTZ '2026-01-09 00:00:00-03', 0.00999445),
    (TIMESTAMPTZ '2026-01-12 00:00:00-03', 0.00999408),
    (TIMESTAMPTZ '2026-01-13 00:00:00-03', 0.00999371),
    (TIMESTAMPTZ '2026-01-14 00:00:00-03', 0.00999334),
    (TIMESTAMPTZ '2026-01-15 00:00:00-03', 0.00999296),
    (TIMESTAMPTZ '2026-01-16 00:00:00-03', 0.00999259),
    (TIMESTAMPTZ '2026-01-19 00:00:00-03', 0.00999222),
    (TIMESTAMPTZ '2026-01-20 00:00:00-03', 0.00999185),
    (TIMESTAMPTZ '2026-01-21 00:00:00-03', 0.00999148),
    (TIMESTAMPTZ '2026-01-22 00:00:00-03', 0.00999111),
    (TIMESTAMPTZ '2026-01-23 00:00:00-03', 0.00999074),
    (TIMESTAMPTZ '2026-01-26 00:00:00-03', 0.00999037),
    (TIMESTAMPTZ '2026-01-27 00:00:00-03', 0.00999),
    (TIMESTAMPTZ '2026-01-28 00:00:00-03', 0.00998963),
    (TIMESTAMPTZ '2026-01-29 00:00:00-03', 0.00998926),
    (TIMESTAMPTZ '2026-01-30 00:00:00-03', 0.00998889),
    (TIMESTAMPTZ '2026-02-02 00:00:00-03', 0.00998852),
    (TIMESTAMPTZ '2026-02-03 00:00:00-03', 0.00998815),
    (TIMESTAMPTZ '2026-02-04 00:00:00-03', 0.00998777),
    (TIMESTAMPTZ '2026-02-05 00:00:00-03', 0.0099874),
    (TIMESTAMPTZ '2026-02-06 00:00:00-03', 0.00998703),
    (TIMESTAMPTZ '2026-02-09 00:00:00-03', 0.00998665),
    (TIMESTAMPTZ '2026-02-10 00:00:00-03', 0.00998627),
    (TIMESTAMPTZ '2026-02-11 00:00:00-03', 0.00998589),
    (TIMESTAMPTZ '2026-02-12 00:00:00-03', 0.00998551),
    (TIMESTAMPTZ '2026-02-13 00:00:00-03', 0.00998513),
    (TIMESTAMPTZ '2026-02-18 00:00:00-03', 0.00998473),
    (TIMESTAMPTZ '2026-02-19 00:00:00-03', 0.0099844),
    (TIMESTAMPTZ '2026-02-20 00:00:00-03', 0.00998402),
    (TIMESTAMPTZ '2026-02-23 00:00:00-03', 0.00998364),
    (TIMESTAMPTZ '2026-02-24 00:00:00-03', 0.00998327),
    (TIMESTAMPTZ '2026-02-25 00:00:00-03', 0.00998287),
    (TIMESTAMPTZ '2026-02-26 00:00:00-03', 0.00998248),
    (TIMESTAMPTZ '2026-02-27 00:00:00-03', 0.00998208),
    (TIMESTAMPTZ '2026-03-02 00:00:00-03', 0.00998168),
    (TIMESTAMPTZ '2026-03-03 00:00:00-03', 0.00998129),
    (TIMESTAMPTZ '2026-03-04 00:00:00-03', 0.00998089),
    (TIMESTAMPTZ '2026-03-05 00:00:00-03', 0.00998049),
    (TIMESTAMPTZ '2026-03-06 00:00:00-03', 0.0099801),
    (TIMESTAMPTZ '2026-03-09 00:00:00-03', 0.0099797),
    (TIMESTAMPTZ '2026-03-10 00:00:00-03', 0.0099793),
    (TIMESTAMPTZ '2026-03-11 00:00:00-03', 0.0099789),
    (TIMESTAMPTZ '2026-03-12 00:00:00-03', 0.0099785),
    (TIMESTAMPTZ '2026-03-13 00:00:00-03', 0.0099781),
    (TIMESTAMPTZ '2026-03-16 00:00:00-03', 0.0099778),
    (TIMESTAMPTZ '2026-03-17 00:00:00-03', 0.0099774),
    (TIMESTAMPTZ '2026-03-18 00:00:00-03', 0.009977),
    (TIMESTAMPTZ '2026-03-19 00:00:00-03', 0.0099766),
    (TIMESTAMPTZ '2026-03-20 00:00:00-03', 0.0099762),
    (TIMESTAMPTZ '2026-03-23 00:00:00-03', 0.00997578),
    (TIMESTAMPTZ '2026-03-24 00:00:00-03', 0.00997538),
    (TIMESTAMPTZ '2026-03-25 00:00:00-03', 0.00997498),
    (TIMESTAMPTZ '2026-03-26 00:00:00-03', 0.00997474),
    (TIMESTAMPTZ '2026-03-27 00:00:00-03', 0.00997435),
    (TIMESTAMPTZ '2026-03-30 00:00:00-03', 0.00997394),
    (TIMESTAMPTZ '2026-03-31 00:00:00-03', 0.00997354),
    (TIMESTAMPTZ '2026-04-01 00:00:00-03', 0.00997314),
    (TIMESTAMPTZ '2026-04-02 00:00:00-03', 0.00997274),
    (TIMESTAMPTZ '2026-04-06 00:00:00-03', 0.00997238),
    (TIMESTAMPTZ '2026-04-07 00:00:00-03', 0.00997198),
    (TIMESTAMPTZ '2026-04-08 00:00:00-03', 0.00997158),
    (TIMESTAMPTZ '2026-04-09 00:00:00-03', 0.00997117),
    (TIMESTAMPTZ '2026-04-10 00:00:00-03', 0.00997076),
    (TIMESTAMPTZ '2026-04-13 00:00:00-03', 0.00997035),
    (TIMESTAMPTZ '2026-04-14 00:00:00-03', 0.00996994),
    (TIMESTAMPTZ '2026-04-15 00:00:00-03', 0.00996957),
    (TIMESTAMPTZ '2026-04-16 00:00:00-03', 0.00996916),
    (TIMESTAMPTZ '2026-04-17 00:00:00-03', 0.00996875),
    (TIMESTAMPTZ '2026-04-20 00:00:00-03', 0.00996834),
    (TIMESTAMPTZ '2026-04-22 00:00:00-03', 0.00996793),
    (TIMESTAMPTZ '2026-04-23 00:00:00-03', 0.00996753),
    (TIMESTAMPTZ '2026-04-24 00:00:00-03', 0.00996713),
    (TIMESTAMPTZ '2026-04-27 00:00:00-03', 0.00996672),
    (TIMESTAMPTZ '2026-04-28 00:00:00-03', 0.00996631),
    (TIMESTAMPTZ '2026-04-29 00:00:00-03', 0.0099659),
    (TIMESTAMPTZ '2026-04-30 00:00:00-03', 0.0099655),
    (TIMESTAMPTZ '2026-05-04 00:00:00-03', 0.0099651),
    (TIMESTAMPTZ '2026-05-05 00:00:00-03', 0.0099647),
    (TIMESTAMPTZ '2026-05-06 00:00:00-03', 0.0099643),
    (TIMESTAMPTZ '2026-05-07 00:00:00-03', 0.0099639),
    (TIMESTAMPTZ '2026-05-08 00:00:00-03', 0.0099634),
    (TIMESTAMPTZ '2026-05-11 00:00:00-03', 0.0099649),
    (TIMESTAMPTZ '2026-05-12 00:00:00-03', 0.0099645),
    (TIMESTAMPTZ '2026-05-13 00:00:00-03', 0.0099641),
    (TIMESTAMPTZ '2026-05-14 00:00:00-03', 0.0099637),
    (TIMESTAMPTZ '2026-05-15 00:00:00-03', 0.0099633),
    (TIMESTAMPTZ '2026-05-18 00:00:00-03', 0.0099628),
    (TIMESTAMPTZ '2026-05-19 00:00:00-03', 0.0099624),
    (TIMESTAMPTZ '2026-05-20 00:00:00-03', 0.0099621),
    (TIMESTAMPTZ '2026-05-21 00:00:00-03', 0.0099617),
    (TIMESTAMPTZ '2026-05-22 00:00:00-03', 0.0099612),
    (TIMESTAMPTZ '2026-05-25 00:00:00-03', 0.0099608),
    (TIMESTAMPTZ '2026-05-26 00:00:00-03', 0.0099604),
    (TIMESTAMPTZ '2026-05-27 00:00:00-03', 0.0099600),
    (TIMESTAMPTZ '2026-05-28 00:00:00-03', 0.0099596),
    (TIMESTAMPTZ '2026-05-29 00:00:00-03', 0.0099592),
    (TIMESTAMPTZ '2026-06-01 00:00:00-03', 0.0099588),
    (TIMESTAMPTZ '2026-06-02 00:00:00-03', 0.0099655),
    (TIMESTAMPTZ '2026-06-03 00:00:00-03', 0.0099655),
    (TIMESTAMPTZ '2026-06-05 00:00:00-03', 0.0099655),
    (TIMESTAMPTZ '2026-06-08 00:00:00-03', 0.0099655),
    (TIMESTAMPTZ '2026-06-09 00:00:00-03', 0.0099655),
    (TIMESTAMPTZ '2026-06-10 00:00:00-03', 0.0099655),
    (TIMESTAMPTZ '2026-06-11 00:00:00-03', 0.0099655),
    (TIMESTAMPTZ '2026-06-12 00:00:00-03', 0.0099655),
    (TIMESTAMPTZ '2026-06-15 00:00:00-03', 0.0099655),
    (TIMESTAMPTZ '2026-06-16 00:00:00-03', 0.0099655)
) AS v(d, pu);

-- Conferencia (rodar antes do COMMIT):
--   SELECT count(*) FROM valuations WHERE asset_id = (SELECT id FROM entities WHERE name='NXRANDS-1');  -- esperado 122
--   SELECT count(*) FROM valuations WHERE asset_id = (SELECT id FROM entities WHERE name='NXRANDS-1') AND last_valuation_flag;  -- esperado 1

COMMIT;
