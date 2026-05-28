-- ============================================================
-- 10. NTNI CR — Cash Flow
-- ------------------------------------------------------------
-- V1 ORIGINAL (Supabase, securities + metadata JSONB):
-- ------------------------------------------------------------
-- WITH issuer AS (
--   SELECT metadata->>'issuer' FROM securities WHERE name = ${ticker}
-- ), items AS (
--   SELECT DISTINCT ON (p.asset_aux_id) *
--   FROM positions p
--   WHERE p.holder_aux_id = (SELECT * FROM issuer)::uuid OR p.metadata->>'event_related' = (SELECT name FROM entities WHERE aux_id = (SELECT * FROM issuer)::uuid)
--   ORDER BY p.asset_aux_id, p.holder_aux_id, p.position_date DESC
-- )
-- SELECT
--   SUM((s.metadata->>'ntni_base_pricing_price')::numeric * (i.metadata->>'reserved_amount')::numeric) AS expected_cash_flow_values,
--   TO_CHAR(
--     TO_DATE(s.metadata->>'maturity_date', 'YYYY-MM-DD'),
--     'YYYY-MM'
--   ) AS month_year_maturity
-- FROM items i
-- JOIN securities s ON s.aux_id = i.asset_aux_id
-- WHERE s.metadata->>'maturity_date' IS NOT NULL
-- GROUP BY month_year_maturity
-- ------------------------------------------------------------
-- CR = vértices NTN-I reservados/detidos pelo CR (issuer do token). Mesmo padrão
-- da Q6/Q8: a tradução literal do V1 (holder_id/event_code + JOIN ntnis) subconta —
-- pega só o que está em `investments` com holder=CR e ignora a conta RESERVATION
-- (cujo holder é o FIDC, não o CR). Os vértices entram por ASSIGNMENT/LOCK (não
-- ISSUANCE — ISSUANCE é da série, na conta de colateral). reserved_amount (V1)
-- = positions.total_quantity; ntni_base_pricing_price (V1) = ntnis.face_value_usd.
-- As posições vivem em duas financial_accounts:
--   1. RESERVATION-<issuer>  — vértices reservados pro CR (holder = FIDC).
--   2. investments           — conta global; filtrar holder_id = issuer (o CR).
-- Perf: branches separados (UNION ALL) p/ empurrar holder_id no scan de investments.
-- OBS: não há linha em expected_cash_flows p/ o CR NTN-I — sem oráculo de validação.
-- ============================================================
WITH cr AS (
    SELECT issuer_entity.id   AS issuer_id,
           issuer_entity.name AS issuer_name
    FROM tokens tk
    JOIN entities token_entity   ON token_entity.id = tk.id
    JOIN entities issuer_entity  ON issuer_entity.id = tk.issuer_id
    WHERE token_entity.name = 'NXNII27-1'
),
held AS (
    -- 1. vértices reservados pro CR (RESERVATION-<issuer>): saldo corrente, qualquer holder
    SELECT pos.asset_id, pos.total_quantity
    FROM cr
    JOIN financial_accounts fa  ON fa.name = 'RESERVATION-' || cr.issuer_name
    JOIN positions pos          ON pos.financial_account_id = fa.id
                               AND pos.last_position_flag = TRUE
    UNION ALL
    -- 2. vértices na conta investments do próprio CR (holder = issuer)
    SELECT pos.asset_id, pos.total_quantity
    FROM cr
    JOIN financial_accounts fa  ON fa.name = 'investments'
    JOIN positions pos          ON pos.financial_account_id = fa.id
                               AND pos.holder_id = cr.issuer_id
                               AND pos.last_position_flag = TRUE
)
SELECT
    SUM(n.face_value_usd * held.total_quantity)  AS expected_cash_flow_values,
    TO_CHAR(n.maturity_date, 'YYYY-MM')          AS month_year_maturity
FROM held
JOIN ntnis n  ON n.id = held.asset_id
WHERE n.maturity_date IS NOT NULL
GROUP BY month_year_maturity
ORDER BY month_year_maturity;
