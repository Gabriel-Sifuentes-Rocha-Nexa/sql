-- ============================================================
-- 11. NTNI Não CR — Cash Flow
-- ------------------------------------------------------------
-- V1 ORIGINAL (Supabase, securities + metadata JSONB):
-- ------------------------------------------------------------
-- SELECT
--   SUM((s1.metadata->'composition'->0->'amount')::numeric * (s2.metadata->'ntni_base_pricing_price')::numeric) AS expected_cash_flow_values,
--   TO_CHAR(
--     TO_DATE(s2.metadata->>'maturity_date', 'YYYY-MM-DD'),
--     'YYYY-MM'
--   ) AS month_year_maturity
-- FROM
--   securities s1,
--   lateral jsonb_array_elements(s1.metadata->'composition') AS composition
-- JOIN securities s2 on
--   s2.aux_id = (composition->>'asset_aux_id')::uuid
-- WHERE
--   s1.name = ${ticker}
--   AND s2.metadata->>'maturity_date' IS NOT NULL
-- GROUP BY month_year_maturity
-- ------------------------------------------------------------
-- Não CR = composição teórica do token (NTN-I vertices via fa do colateral).
-- Em V1 multiplicava por composition[0].amount (sempre o primeiro item, valor uniforme).
-- Em V2 multiplico por positions.total_quantity de cada vertex (mais preciso por
-- vertex, mas se a semântica original "uniforme" for necessária, ajustar).
-- ============================================================
SELECT
    SUM(n.face_value_usd * pos.total_quantity)                AS expected_cash_flow_values,
    TO_CHAR(n.maturity_date, 'YYYY-MM')                       AS month_year_maturity
FROM ntnis n
JOIN positions pos                          ON pos.asset_id = n.id
JOIN transaction_types tt                   ON tt.id = pos.transaction_type_id
                                            AND tt.name = 'TOKENIZATION'
JOIN financial_accounts token_fa            ON token_fa.id = pos.financial_account_id
JOIN entities token_entity                  ON token_fa.name = 'assets pledged as collateral - ' || token_entity.name
WHERE token_entity.name = 'NXNIC27-1'
  AND n.maturity_date IS NOT NULL
GROUP BY month_year_maturity;
-- WHERE token_entity.name = 'NXFGTSB31-3';  -- exemplo para testes
