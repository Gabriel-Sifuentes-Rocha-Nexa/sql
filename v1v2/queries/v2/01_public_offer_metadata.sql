-- ============================================================
-- 1. Public Offer — Obter metadados do Asset
-- ------------------------------------------------------------
-- V1 ORIGINAL (Supabase, securities + metadata JSONB):
-- ------------------------------------------------------------
-- SELECT
--     s2.name,
--     s2.full_name,
--     s2.code,
--     s2.metadata,
--     (s2.metadata->'series_index') as series_index,
--     (s2.metadata->'series_number') as series_number,
--     (s2.metadata->'series_type') as series_type,
--     (s2.metadata->'series_issuance_date') as series_issuance_date,
--     (s2.metadata->'series_maturity_date') as series_maturity_date,
--     (s2.metadata->'series_issuance_amount') as series_issuance_amount,
--     (s2.metadata->'series_issuance_unit_price') as series_issuance_unit_price,
--     (s2.metadata->'series_monetary_adjustment') as series_monetary_adjustment,
--     (s2.metadata->'series_abs_spread_over_index') as series_abs_spread_over_index,
--     (s2.metadata->'series_relative_spread_over_index') as series_relative_spread_over_index
-- FROM securities s1
-- CROSS JOIN LATERAL jsonb_array_elements(s1.metadata->'composition') as compositions
-- JOIN securities s2 ON s2.aux_id = (compositions->>'asset_aux_id')::uuid
-- WHERE s1.code = ${ticker}
-- ------------------------------------------------------------
-- ============================================================
SELECT
    series_entity.name                    AS securitizations_series_name,
    issuer_entity.name                    AS issuer_name,
    ss.issuance_number,
    ss.series_number,
    sen.name                              AS seniority_name,           -- series_type
    ss.seniority_number,
    idx.name                              AS indexer_name,             -- series_index
    ss.indexer_percentage,                                             -- series_relative_spread_over_index
    ss.spread_over_indexer,                                            -- series_abs_spread_over_index
    ss.issuance_date,                                                  -- series_issuance_date
    ss.maturity_date,                                                  -- series_maturity_date
    ss.initial_price,                                                  -- series_issuance_unit_price
    ss.quantity,                                                       -- series_issuance_amount
    o.name                                AS offer_type,
    ss.register_id,
    ss.register_b3,
    sua.name                              AS underlying_asset_name
FROM securitization_series ss
JOIN entities series_entity               ON series_entity.id = ss.id
JOIN entities issuer_entity               ON issuer_entity.id = ss.issuer_id
JOIN securitizations issuer_details       ON issuer_details.id = issuer_entity.id
JOIN indexers idx                         ON idx.id = ss.indexer_id
JOIN seniorities sen                      ON sen.id = ss.seniority_id
JOIN offers o                             ON o.id = ss.offer_id
JOIN securitization_underlying_assets sua ON sua.id = issuer_details.underlying_asset_id
JOIN positions pos                        ON pos.asset_id = ss.id
JOIN transaction_types tt                 ON tt.id = pos.transaction_type_id
                                          AND tt.name = 'ISSUANCE'
JOIN financial_accounts token_fa          ON token_fa.id = pos.financial_account_id
JOIN entities token_entity                ON token_fa.name = 'assets pledged as collateral - ' || token_entity.name
-- WHERE token_entity.name = ${ticker};
WHERE token_entity.name = 'NXFGTSB31-3';  -- exemplo para testes
