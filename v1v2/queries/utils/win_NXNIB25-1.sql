-- diarias NXNIB25-1 (762) em torno do gap 02-17 -> 02-18
SELECT v.id, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v
WHERE v.asset_id = 762 AND v.date::date BETWEEN DATE '2025-02-10' AND DATE '2025-02-19'
ORDER BY v.date
