-- ============================================================
-- 6. NXCO CR — Cash Flow
-- ------------------------------------------------------------
-- V1 ORIGINAL (Supabase, securities + metadata JSONB):
-- ------------------------------------------------------------
-- WITH issuer AS (
--   SELECT metadata->>'issuer' FROM securities WHERE name = ${ticker}
-- ), items AS (
--   SELECT DISTINCT ON (p.asset_aux_id, p.holder_aux_id) *
--   FROM positions p
--   WHERE p.holder_aux_id = (SELECT * FROM issuer)::uuid OR p.metadata->>'event_related' = (SELECT name FROM entities WHERE aux_id = (SELECT * FROM issuer)::uuid)
--   ORDER BY p.asset_aux_id, p.holder_aux_id, p.position_date DESC
-- )
-- SELECT
--   SUM((s.metadata->'linhas'->0->'recebivel'->'valor_contrato')::numeric * i.amount) AS expected_cash_flow_values,
--   TO_CHAR(
--     TO_DATE(s.metadata->'linhas'->0->'recebivel'->>'data_resgate', 'YYYY-MM-DD'),
--     'YYYY-MM'
--   ) AS month_year_maturity
-- FROM items i
-- JOIN securities s ON s.aux_id = i.asset_aux_id
-- WHERE s.metadata->'linhas'->0->'recebivel'->>'data_resgate' IS NOT NULL
-- GROUP BY month_year_maturity
-- ------------------------------------------------------------
WITH cr AS (
    SELECT issuer_entity.id   AS issuer_id,
           issuer_entity.name AS issuer_name
    FROM tokens tk
    JOIN entities token_entity   ON token_entity.id = tk.id
    JOIN entities issuer_entity  ON issuer_entity.id = tk.issuer_id
    WHERE token_entity.name = 'NXCOL26-4'
),
held AS (
    -- 1. cotas reservadas pro CR (RESERVATION-<issuer>): saldo corrente, qualquer holder
    SELECT pos.asset_id, pos.total_quantity
    FROM cr
    JOIN financial_accounts fa  ON fa.name = 'RESERVATION-' || cr.issuer_name
    JOIN positions pos          ON pos.financial_account_id = fa.id
                               AND pos.last_position_flag = TRUE
    UNION ALL
    -- 2. cotas na conta investments do próprio CR (holder = issuer)
    SELECT pos.asset_id, pos.total_quantity
    FROM cr
    JOIN financial_accounts fa  ON fa.name = 'investments'
    JOIN positions pos          ON pos.financial_account_id = fa.id
                               AND pos.holder_id = cr.issuer_id
                               AND pos.last_position_flag = TRUE
)
SELECT
    SUM(c.face_value * held.total_quantity)      AS expected_cash_flow_values,
    TO_CHAR(c.expected_maturity_date, 'YYYY-MM') AS month_year_maturity
FROM held
JOIN consortiums c  ON c.id = held.asset_id
WHERE c.expected_maturity_date IS NOT NULL
GROUP BY month_year_maturity
ORDER BY month_year_maturity;
-- exemplo para testes: token 'NXCOL26-4' (issuer CR-CONSORTIUMS-26)
