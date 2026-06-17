-- cota CANOPUS-8300-419 (1895, subjacente do NXCOF25-2) valuations 06-01..06-03
-- comparar com CANOPUS-8300-535 (1906, subjacente do NXCOF25-3) que redimiu por 105949.58
SELECT a.name AS cota, v.id, v.date, m.name AS meth, v.clean_price, v.cash_flow, v.last_valuation_flag AS vig
FROM valuations v JOIN entities a ON a.id = v.asset_id
LEFT JOIN valuation_methodologies m ON m.id = v.methodology_id
WHERE v.asset_id IN (1895,1906) AND v.date::date BETWEEN DATE '2025-06-01' AND DATE '2025-06-03'
ORDER BY a.name, v.date, v.id
