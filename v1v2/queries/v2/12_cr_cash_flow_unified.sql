-- ============================================================
-- 12 (BÔNUS). CR Cash Flow — UNIFICADA (consórcio + FGTS + NTN-I)
-- ------------------------------------------------------------
-- Não faz parte do porte 1:1 do V1. Consolida Q6 (consórcio), Q8 (FGTS) e
-- Q10 (NTN-I) numa única query, já que a lógica CR é idêntica nas três:
--   posições do ativo em RESERVATION-<issuer> + investments(holder=issuer),
--   last_position_flag, valor = face_value * total_quantity, por mês de venc.
-- A ÚNICA coisa que muda por classe é a coluna de face_value e a de vencimento.
-- `entities.reference_table_id` (FK -> reference_tables) diz a classe do ativo:
--   2 = ntnis, 3 = fgts, 4 = consortiums.
--
-- MOEDA: consórcio/FGTS = BRL; NTN-I = USD. Como cada CR é mono-classe, o
-- resultado é mono-moeda — mas a coluna `currency` é exposta de propósito p/
-- não somar BRL com USD por engano (e deixar a moeda explícita ao consumidor).
-- Equivalência com Q6/Q8/Q10 validada (mesmos números por ticker).
-- ============================================================
WITH cr AS (
    SELECT issuer_entity.id   AS issuer_id,
           issuer_entity.name AS issuer_name
    FROM tokens tk
    JOIN entities token_entity   ON token_entity.id = tk.id
    JOIN entities issuer_entity  ON issuer_entity.id = tk.issuer_id
    WHERE token_entity.name = ${ticker}
),
held AS (
    -- 1. ativos reservados pro CR (RESERVATION-<issuer>): saldo corrente, qualquer holder
    SELECT pos.asset_id, pos.total_quantity
    FROM cr
    JOIN financial_accounts fa  ON fa.name = 'RESERVATION-' || cr.issuer_name
    JOIN positions pos          ON pos.financial_account_id = fa.id
                               AND pos.last_position_flag = TRUE
    UNION ALL
    -- 2. ativos na conta investments do próprio CR (holder = issuer)
    SELECT pos.asset_id, pos.total_quantity
    FROM cr
    JOIN financial_accounts fa  ON fa.name = 'investments'
    JOIN positions pos          ON pos.financial_account_id = fa.id
                               AND pos.holder_id = cr.issuer_id
                               AND pos.last_position_flag = TRUE
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
        held.total_quantity
    FROM held
    JOIN entities e            ON e.id = held.asset_id
    JOIN reference_tables rt   ON rt.id = e.reference_table_id
    LEFT JOIN consortiums c    ON c.id = held.asset_id AND e.reference_table_id = 4
    LEFT JOIN fgts f           ON f.id = held.asset_id AND e.reference_table_id = 3
    LEFT JOIN ntnis n          ON n.id = held.asset_id AND e.reference_table_id = 2
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
-- exemplos: 'NXCOL26-4' (consórcio) ; 'NXFGTSB31-1' (FGTS) ; 'NXNII27-2' (NTN-I)
