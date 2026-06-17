-- NXCOF25-3 (1946): valuations 2025-05-30..2025-06-05
SELECT v.id, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v
WHERE v.asset_id = 1946 AND v.date::date BETWEEN DATE '2025-05-30' AND DATE '2025-06-05'
ORDER BY v.date
