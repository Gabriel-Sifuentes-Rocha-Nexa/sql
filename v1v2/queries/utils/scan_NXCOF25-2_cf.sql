-- NXCOF25-2 (1938) todos os eventos de cash_flow + a(s) vigente(s)
SELECT v.id, v.date, m.name AS meth, v.clean_price, v.accrued_interest, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v LEFT JOIN valuation_methodologies m ON m.id=v.methodology_id
WHERE v.asset_id=1938 AND (v.cash_flow <> 0 OR v.last_valuation_flag)
ORDER BY v.date, v.id
