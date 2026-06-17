-- NXCOE25-2 (3032): ultimas valuations ate' 06-02 (achar a ultima diaria boa)
SELECT v.id, v.date, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v
WHERE v.asset_id = 3032 AND v.date <= timestamptz '2025-06-02 23:59:59-03'
ORDER BY v.date DESC
LIMIT 6
