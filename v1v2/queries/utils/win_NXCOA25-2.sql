-- diarias NXCOA25-2 (1685) em torno do gap 01-17 -> 01-21
SELECT v.id, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v
WHERE v.asset_id = 1685 AND v.date::date BETWEEN DATE '2025-01-14' AND DATE '2025-01-22'
ORDER BY v.date
