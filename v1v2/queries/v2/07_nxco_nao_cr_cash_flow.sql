-- ============================================================
-- 7. NXCO Não CR — Cash Flow
-- ------------------------------------------------------------
-- V1 ORIGINAL (Supabase, securities + metadata JSONB):
-- ------------------------------------------------------------
-- SELECT
--   SUM((s2.metadata->'linhas'->0->'recebivel'->'valor_contrato')::numeric) AS expected_cash_flow_values,
--   TO_CHAR(
--     TO_DATE(s2.metadata->'linhas'->0->'recebivel'->>'data_resgate', 'YYYY-MM-DD'),
--     'YYYY-MM'
--   ) AS month_year_maturity
-- FROM
--   securities s1,
--   lateral jsonb_array_elements(s1.metadata->'composition') AS composition
-- JOIN securities s2 ON
--   s2.aux_id = (composition->>'asset_aux_id')::uuid
-- WHERE
--   s1.name = ${ticker}
--   AND s2.metadata->'linhas'->0->'recebivel'->>'data_resgate' IS NOT NULL
-- GROUP BY month_year_maturity
-- ------------------------------------------------------------
-- Não CR = composição teórica do token (subjacentes ligados via fa do colateral).
-- SUM(face_value) sem multiplicar por quantidade (diferente de CR).
-- ============================================================
SELECT
    SUM(c.face_value)                                       AS expected_cash_flow_values,
    TO_CHAR(c.expected_maturity_date, 'YYYY-MM')              AS month_year_maturity
FROM consortiums c
JOIN positions pos                          ON pos.asset_id = c.id
JOIN transaction_types tt                   ON tt.id = pos.transaction_type_id
                                            AND tt.name = 'TOKENIZATION'
JOIN financial_accounts token_fa            ON token_fa.id = pos.financial_account_id
JOIN entities token_entity                  ON token_fa.name = 'assets pledged as collateral - ' || token_entity.name
WHERE token_entity.name = 'NXCOC26-1'
  AND c.expected_maturity_date IS NOT NULL
GROUP BY month_year_maturity;
