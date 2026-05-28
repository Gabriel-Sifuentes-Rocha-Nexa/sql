-- ============================================================
-- 13 (BÔNUS). Não CR Cash Flow — UNIFICADA (consórcio + FGTS + NTN-I)
-- ------------------------------------------------------------
-- Não faz parte do porte 1:1 do V1. Consolida Q7 (consórcio), Q9 (FGTS) e
-- Q11 (NTN-I) — as cash flows de TOKENIZAÇÃO DIRETA (sem CR). Análoga à Q12,
-- mas a fonte é a composição teórica do token, não as contas do CR:
--   conta de colateral 'assets pledged as collateral - <token>' + TOKENIZATION.
-- `entities.reference_table_id` (2=ntnis, 3=fgts, 4=consortiums) escolhe a
-- coluna de face_value e a de vencimento.
--
-- QUANTIDADE: usa-se `face_value * total_quantity` nas TRÊS. Em consórcio/FGTS
-- `total_quantity` é sempre 1 (multiplicar é inócuo — equivale ao SUM(face_value)
-- da Q7/Q9); em NTN-I o vértice tem quantidade > 1 e a multiplicação é necessária
-- (equivale à Q11). Validado: bate com Q7/Q9/Q11.
--
-- MOEDA: consórcio/FGTS = BRL; NTN-I = USD. Coluna `currency` exposta de
-- propósito p/ a moeda não ficar implícita (ver Q12).
-- ============================================================
WITH composed AS (
    -- composição teórica do token: ativos na conta de colateral via TOKENIZATION
    SELECT pos.asset_id, pos.total_quantity
    FROM entities token_entity
    JOIN financial_accounts fa  ON fa.name = 'assets pledged as collateral - ' || token_entity.name
    JOIN positions pos          ON pos.financial_account_id = fa.id
    JOIN transaction_types tt   ON tt.id = pos.transaction_type_id
                               AND tt.name = 'TOKENIZATION'
    WHERE token_entity.name = ${ticker}
),
priced AS (
    SELECT
        rt.name                                                  AS asset_class,
        CASE WHEN e.reference_table_id = 2 THEN 'USD' ELSE 'BRL' END AS currency,
        CASE e.reference_table_id
            WHEN 4 THEN c.face_value
            WHEN 3 THEN f.face_value
            WHEN 2 THEN n.face_value_usd
        END                                                      AS face_value,
        CASE e.reference_table_id
            WHEN 4 THEN c.expected_maturity_date
            WHEN 3 THEN f.maturity_date
            WHEN 2 THEN n.maturity_date
        END                                                      AS maturity_date,
        composed.total_quantity
    FROM composed
    JOIN entities e            ON e.id = composed.asset_id
    JOIN reference_tables rt   ON rt.id = e.reference_table_id
    LEFT JOIN consortiums c    ON c.id = composed.asset_id AND e.reference_table_id = 4
    LEFT JOIN fgts f           ON f.id = composed.asset_id AND e.reference_table_id = 3
    LEFT JOIN ntnis n          ON n.id = composed.asset_id AND e.reference_table_id = 2
)
SELECT
    SUM(face_value * total_quantity)             AS expected_cash_flow_values,
    TO_CHAR(maturity_date, 'YYYY-MM')            AS month_year_maturity,
    asset_class,
    currency
FROM priced
WHERE maturity_date IS NOT NULL
GROUP BY month_year_maturity, asset_class, currency
ORDER BY month_year_maturity;
-- exemplos: 'NXCOC26-1' (consórcio) ; 'NXFGTSE34-1' (FGTS) ; 'NXNII27-1' (NTN-I)
