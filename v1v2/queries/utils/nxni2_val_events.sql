-- NXNIB25-1: linhas de evento (cash_flow<>0) + a vigente
SELECT v.id, v.date, m.name AS meth, v.clean_price, v.accrued_interest, v.cash_flow,
       v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id = v.asset_id
LEFT JOIN valuation_methodologies m ON m.id = v.methodology_id
WHERE a.name = 'NXNIB25-1' AND (v.cash_flow <> 0 OR v.last_valuation_flag)
ORDER BY v.date
