-- ============================================================
-- 3. NXNI — Obter metadados do Asset
-- ------------------------------------------------------------
-- V1 ORIGINAL (Supabase, securities + metadata JSONB):
-- ------------------------------------------------------------
-- SELECT
--     s1.name,
--     s1.full_name,
--     s1.code,
--     t.metadata,
--     'Nota do Tesouro Nacional Série I' as instrument,
--     (t.metadata->'token_true_yield') as token_true_yield,
--     (t.metadata->'estimatedSpreadOverCDI') as estimated_spread_over_cdi,
--     (t.metadata->'last_maturity_date') as last_maturity_date,
--     t.transaction_date
-- FROM securities s1
-- CROSS JOIN LATERAL jsonb_array_elements(s1.metadata->'composition') as compositions
-- JOIN transactions t ON t.asset_aux_id = (compositions->>'asset_aux_id')::uuid
-- WHERE s1.code = ${ticker} and t.type = 'collateralize'
-- ORDER BY t.transaction_date
-- LIMIT 1
-- ------------------------------------------------------------
-- ============================================================
SELECT
    -- Identificação
    token_entity.name                       AS token_name,                 -- s1.name (V1)
    'Nota do Tesouro Nacional Série I'      AS instrument,
    tk.issuer_code,
    -- Estratégia / estrutura
    ts.strategy_code,
    ts.strategy_name,
    ts.strategy_asset,
    tstruct.structure_name,
    issuer_entity.name                      AS issuer_name,
    -- Indexador (registro do token)
    idx.name                                AS indexer_name,
    -- Datas
    tk.max_offering_date,
    tk.maturity_date                        AS last_maturity_date,         -- (V1: last_maturity_date)
    pos.date                                AS transaction_date,
    -- Valores e emissão
    tk.issuance_count,
    tk.issuance_price,
    tk.issuance_amount,
    tk.minimum_issuance_amount,
    tk.face_value,
    tk.offering_duration,
    tk.duration_months,
    tk.estimated_moic,
    -- Taxas / spreads estimados (registro)
    tk.internal_rate_of_return              AS token_true_yield,           -- (V1: token_true_yield)
    tk.return_percentage_cdi,
    tk.estimated_spread_over_cdi,                                          -- (V1: estimated_spread_over_cdi)
    tk.estimated_spread_over_inflation,
    tk.referral_fee,
    -- NTN-I subjacente colateralizado nessa transação
    n.maturity_date                         AS ntni_maturity_date,
    n.face_value_usd                        AS ntni_face_value_usd
FROM ntnis n
JOIN positions pos                          ON pos.asset_id = n.id
JOIN transaction_types tt                   ON tt.id = pos.transaction_type_id
                                            AND tt.name = 'TOKENIZATION'
JOIN financial_accounts token_fa            ON token_fa.id = pos.financial_account_id
JOIN entities token_entity                  ON token_fa.name = 'assets pledged as collateral - ' || token_entity.name
JOIN tokens tk                              ON tk.id = token_entity.id
JOIN token_strategies ts                    ON ts.id = tk.strategy_id
JOIN token_structures tstruct               ON tstruct.id = tk.structure_id
JOIN entities issuer_entity                 ON issuer_entity.id = tk.issuer_id
LEFT JOIN indexers idx                      ON idx.id = tk.indexer_id
-- WHERE token_entity.name = ${ticker}
WHERE token_entity.name = 'NXNIC26-2'
ORDER BY pos.date
LIMIT 1;
