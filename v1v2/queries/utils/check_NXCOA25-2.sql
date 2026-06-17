-- Linha do tempo do token NXCOA25-2 (e diagnostico de cash_flow / amort)
-- Mostra todas as valuations; marca linhas de evento (cash_flow<>0).
SELECT a.name AS ativo,
       v.date,
       m.name AS metodologia,
       v.clean_price,
       v.accrued_interest,
       v.cash_flow,
       v.last_valuation_flag AS vig,
       CASE WHEN v.cash_flow <> 0 THEN '<<< EVENTO' ELSE '' END AS flag
FROM valuations v
JOIN entities a ON a.id = v.asset_id
LEFT JOIN valuation_methodologies m ON m.id = v.methodology_id
WHERE a.name = 'NXCOA25-2'
ORDER BY v.date
