-- ============================================================
-- 9. FGTS Não CR — Cash Flow
-- ------------------------------------------------------------
-- V1 ORIGINAL (Supabase, securities + metadata JSONB):
-- ------------------------------------------------------------
-- SELECT
--   SUM((s2.metadata->'valor_nominal'):: numeric) AS expected_cash_flow_values,
--   TO_CHAR(
--     TO_DATE(s2.metadata->>'data_vencimento', 'YYYY-MM-DD'),
--     'YYYY-MM'
--   ) AS month_year_maturity
-- FROM
--   securities s1,
--   lateral jsonb_array_elements(s1.metadata->'composition') AS composition
-- JOIN securities s2 ON
--   s2.aux_id = (composition->>'asset_aux_id')::uuid
-- WHERE
--   s1.name = ${ticker}
--   AND s2.metadata->>'data_vencimento' IS NOT NULL
-- GROUP BY month_year_maturity
-- ------------------------------------------------------------
-- Não CR = composição teórica do token (subjacentes via fa do colateral).
-- ============================================================
SELECT
    SUM(f.face_value)                                         AS expected_cash_flow_values,
    TO_CHAR(f.maturity_date, 'YYYY-MM')                       AS month_year_maturity
FROM fgts f
JOIN positions pos                          ON pos.asset_id = f.id
JOIN transaction_types tt                   ON tt.id = pos.transaction_type_id
                                            AND tt.name = 'TOKENIZATION'
JOIN financial_accounts token_fa            ON token_fa.id = pos.financial_account_id
JOIN entities token_entity                  ON token_fa.name = 'assets pledged as collateral - ' || token_entity.name
WHERE token_entity.name = 'NXFGTSE34-1'
  AND f.maturity_date IS NOT NULL
GROUP BY month_year_maturity;
