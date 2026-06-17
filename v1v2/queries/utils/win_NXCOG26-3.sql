-- diarias NXCOG26-3 (3256) em torno do gap 11-06 -> 11-10
SELECT v.id, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v
WHERE v.asset_id = 3256 AND v.date::date BETWEEN DATE '2025-11-03' AND DATE '2025-11-11'
ORDER BY v.date
