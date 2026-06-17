-- Datas com eventos de cash_flow (cash_flow<>0) em jan/2025, p/ confirmar que o engine bookava eventos no periodo
SELECT v.date::date AS dia,
       count(*) AS eventos,
       count(*) FILTER (WHERE a.id IN (SELECT id FROM tokens)) AS eventos_token
FROM valuations v
JOIN entities a ON a.id = v.asset_id
WHERE v.date::date BETWEEN DATE '2025-01-01' AND DATE '2025-01-31'
  AND v.cash_flow <> 0
GROUP BY v.date::date
ORDER BY dia
