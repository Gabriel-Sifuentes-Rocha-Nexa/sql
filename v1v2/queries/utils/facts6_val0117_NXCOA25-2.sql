-- valuations do token (1685) no dia 2025-01-17 com id e methodology (p/ saber o que apagar / manter)
SELECT v.id, v.date, m.name AS metodologia, v.clean_price, v.accrued_interest,
       v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v
LEFT JOIN valuation_methodologies m ON m.id = v.methodology_id
WHERE v.asset_id = 1685 AND v.date::date = DATE '2025-01-17'
ORDER BY v.date
