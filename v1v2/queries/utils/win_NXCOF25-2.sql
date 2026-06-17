-- NXCOF25-2 (1938) valuations 05-29..06-04 (procurar burst/parcial/diaria estranha)
SELECT v.id, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v
WHERE v.asset_id = 1938 AND v.date::date BETWEEN DATE '2025-05-29' AND DATE '2025-06-04'
ORDER BY v.date
